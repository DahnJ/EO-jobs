(ns eojobs.net
  "Cheap, no-LLM HTTP sweeps over the DB: link-rot (dead website/careers URLs)
  and redirect detection (a site that now lands on a different company's domain
  is likely acquired/rebranded).

  Concurrency uses a virtual-thread executor: ~600 blocking HTTP calls is exactly
  what cheap unbounded virtual threads are for, with no third-party library."
  (:require [clojure.string :as str]
            [clojure.tools.cli :as cli]
            [eojobs.db :as db])
  (:import (java.net URI)
           (java.net.http HttpClient HttpClient$Redirect
                          HttpRequest HttpRequest$BodyPublishers
                          HttpResponse$BodyHandlers)
           (java.time Duration)
           (java.util.concurrent Callable Executors)))

(def ^:private ua "Mozilla/5.0 (compatible; EO-jobs-linkcheck/1.0)")

(defn- client [timeout]
  (-> (HttpClient/newBuilder)
      (.followRedirects HttpClient$Redirect/NORMAL)
      (.connectTimeout (Duration/ofSeconds timeout))
      (.build)))

(defn- send-once
  "Send one request; returns {:status int :final url-string}. Throws on network error."
  [cl url method timeout]
  (let [req  (-> (HttpRequest/newBuilder (URI/create url))
                 (.timeout (Duration/ofSeconds timeout))
                 (.header "User-Agent" ua)
                 (.method method (HttpRequest$BodyPublishers/noBody))
                 (.build))
        resp (.send cl req (HttpResponse$BodyHandlers/discarding))]
    ;; java.net.http does NOT throw on 4xx/5xx and auto-follows redirects;
    ;; .uri is the final post-redirect URI.
    {:status (.statusCode resp) :final (str (.uri resp))}))

(defn- pmap-vthreads
  "Run (f x) for each x concurrently on virtual threads; returns results in order."
  [f xs]
  (with-open [ex (Executors/newVirtualThreadPerTaskExecutor)]
    (let [futs (mapv (fn [x] (.submit ex ^Callable (fn [] (f x)))) xs)]
      (mapv #(.get %) futs))))

;; ---------- link-rot ----------
(defn- alive?
  "Returns {:ok bool :detail str} for a URL (HEAD, GET-fallback; 403/416 != dead)."
  [cl url timeout]
  (if-not (and url (str/starts-with? url "http"))
    {:ok false :detail "no-url"}
    (letfn [(judge [s] {:ok (or (< s 400) (contains? #{403 416} s)) :detail (str s)})]
      (try
        (let [s (:status (send-once cl url "HEAD" timeout))]
          (if (contains? #{403 405 416 501} s)
            (judge (:status (send-once cl url "GET" timeout)))
            (judge s)))
        (catch Exception _
          (try (judge (:status (send-once cl url "GET" timeout)))
               (catch Exception e {:ok false :detail (.. e getClass getSimpleName)})))))))

(defn check-links [args]
  (let [{:keys [options]}
        (cli/parse-opts args [[nil "--listed-only"]
                              [nil "--timeout SECS" :parse-fn parse-long :default 8]
                              [nil "--workers N" :parse-fn parse-long :default 16]]) ; accepted, ignored (vthreads)
        {:keys [listed-only timeout]} options
        cl      (client timeout)
        targets (for [[slug rec] (db/load-all)
                      :when (or (not listed-only) (:listed rec))
                      [kind url] (concat (when (:website rec) [["website" (:website rec)]])
                                         (map (fn [u] ["careers" u]) (:careers-urls rec [])))]
                  {:slug slug :kind kind :url url})
        bad     (->> (pmap-vthreads #(assoc % :res (alive? cl (:url %) timeout)) targets)
                     (remove #(:ok (:res %)))
                     (sort-by (juxt :slug :kind)))]
    (spit "/tmp/linkrot.txt"
          (str (str/join "\n" (for [{:keys [slug kind url res]} bad]
                                (str slug "\t" kind "\t" (:detail res) "\t" url))) "\n"))
    (printf "checked %d urls across %d companies; %d dead/unreachable%n"
            (count targets) (count (distinct (map :slug targets))) (count bad))
    (println "full report: /tmp/linkrot.txt")
    (doseq [{:keys [slug kind url res]} (take 40 bad)]
      (printf "  %-30s %-8s %-14s %s%n" slug kind (:detail res) url))))

;; ---------- redirect detection ----------
(def ^:private two-part-second #{"co" "com" "org" "gov" "ac" "net"})
(def ^:private two-part-tld     #{"uk" "au" "nz" "za" "in" "br" "jp" "kr"})

(defn reg-domain
  "Naive registrable domain: last 2 labels (last 3 for common 2-part TLDs)."
  [url]
  (let [host  (or (.getHost (URI/create (if (str/starts-with? url "http") url (str "https://" url)))) "")
        host  (str/lower-case host)
        host  (if (str/starts-with? host "www.") (subs host 4) host)
        parts (str/split host #"\.")]
    (cond
      (and (>= (count parts) 3)
           (two-part-second (nth parts (- (count parts) 2)))
           (two-part-tld (last parts)))
      (str/join "." (take-last 3 parts))
      (>= (count parts) 2) (str/join "." (take-last 2 parts))
      :else host)))

(defn- final-of [cl url timeout]
  (try
    (let [{:keys [final]} (send-once cl url "HEAD" timeout)]
      (if (str/blank? final) (:final (send-once cl url "GET" timeout)) final))
    (catch Exception _
      (try (:final (send-once cl url "GET" timeout)) (catch Exception _ "")))))

(defn check-redirects [args]
  (let [{:keys [options]}
        (cli/parse-opts args [[nil "--timeout SECS" :parse-fn parse-long :default 10]
                              [nil "--workers N" :parse-fn parse-long :default 16]])
        timeout (:timeout options)
        cl      (client timeout)
        listed  (for [[slug rec] (db/load-all)
                      :when (and (:listed rec) (:website rec))]
                  {:slug slug :name (:name rec) :web (:website rec)})
        moved   (->> (pmap-vthreads
                      (fn [c] (assoc c :final (final-of cl (:web c) timeout))) listed)
                     (keep (fn [{:keys [slug name web final]}]
                             (let [a (reg-domain web) b (reg-domain final)]
                               (when (and (seq a) (seq b) (not= a b))
                                 [slug name a b]))))
                     (sort))]
    (spit "/tmp/redirects.txt"
          (str (str/join "\n" (for [[s n a b] moved] (str s "\t" n "\t" a " -> " b))) "\n"))
    (printf "checked %d listed websites; %d redirect to a DIFFERENT domain:%n%n"
            (count listed) (count moved))
    (doseq [[_ n a b] moved] (printf "  %-28s %s  ->  %s%n" n a b))))
