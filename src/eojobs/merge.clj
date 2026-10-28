(ns eojobs.merge
  "Apply verified inbox records into the DB. Each per-field rule is its own small
  function threaded with `->`, so the precedence logic reads as a pipeline."
  (:require [cheshire.core :as json]
            [clojure.string :as str]
            [clojure.tools.cli :as cli]
            [eojobs.db :as db]
            [eojobs.flags :as flags]))

(defn- today [] (str (java.time.LocalDate/now)))

(def ^:private new-record
  {:name "" :status "unknown" :website "" :careers-urls [] :locations []
   :remote "" :remote-evidence "" :description "" :satellites ""
   :category "" :listed false :links {} :source "" :body ""})

(def ^:private conf-rank {"high" 3 "medium" 2 "low" 1 "" 0 nil 0})

(defn- set-if [rec k v]
  (if (and v (not= v "")) (assoc rec k v) rec))

(defn- apply-status [rec r]
  ;; never downgrade a known status to "unknown" (e.g. a fetch failure)
  (let [s (:status r)]
    (if (and s (not (and (= s "unknown")
                         (not (contains? #{"" "unknown" nil} (:status rec))))))
      (assoc rec :status s)
      rec)))

(defn- apply-careers [rec r]
  (if-let [cu (some-> (:careers_url r) str/trim not-empty)]
    (assoc rec :careers-urls [cu])
    rec))

(defn- apply-locations [rec r]
  (if (seq (:locations r))
    (assoc rec :locations (flags/flag-all (:locations r)))
    rec))

(defn- apply-remote [rec r]
  ;; don't let a lower-confidence remote finding overwrite a higher one
  (let [inc-rank   (conf-rank (:remote_confidence r) 0)
        exist-rank (conf-rank (:remote-confidence rec) 0)
        downgrade? (and (pos? inc-rank) (pos? exist-rank) (< inc-rank exist-rank))]
    (if downgrade?
      rec
      (-> rec
          (set-if :remote (:remote r))
          (set-if :remote-evidence (:remote_evidence r))
          (set-if :remote-confidence (:remote_confidence r))))))

(defn- apply-links [rec r]
  ;; union: add new non-empty links, never clobber an existing one.
  ;; plain `merge` with existing on the right == Python's setdefault. (merge-with
  ;; would only be needed if we combined both values — we don't.)
  (let [incoming (into {} (remove (comp str/blank? val) (or (:links r) {})))]
    (update rec :links #(merge incoming %))))

(defn- apply-note [rec r source]
  (if-let [note (some-> (:note r) str/trim not-empty)]
    (let [stamp (str "[" source " " (today) "] " note)
          body  (:body rec "")]
      (assoc rec :body (if (str/blank? body) stamp (str (str/trim body) "\n\n" stamp))))
    rec))

(defn merge-one
  "Merge inbox record `r` into `existing` (nil => create new)."
  [existing r source]
  (-> (or existing (assoc new-record
                          :name (or (:name r) (:slug r))
                          :source source))
      (apply-status r)
      (set-if :website (:website r))
      (apply-careers r)
      (apply-locations r)
      (apply-remote r)
      (set-if :description (:description r))
      (apply-links r)
      (assoc :last-checked (today))
      (apply-note r source)))

(defn run [args]
  (let [{:keys [options]}
        (cli/parse-opts args [["-s" "--source SOURCE" "source tag for new files"
                               :default "discovery-sweep"]])
        source (:source options)
        results
        (for [f (db/ls db/inbox-dir #".*\.json")
              r (json/parse-string (slurp f) true)]
          (let [s (str/trim (or (:slug r) ""))]
            (if (empty? s)
              [:skipped (or (:name r) "?")]
              (let [p        (db/path s)
                    existing (when (.exists p) (db/parse (slurp p)))
                    merged   (merge-one existing (assoc r :slug s) source)]
                (db/save s merged)
                [(if existing :updated :created) s]))))
        by (group-by first results)]
    (printf "created %d, updated %d, skipped %d%n"
            (count (:created by)) (count (:updated by)) (count (:skipped by)))
    (when-let [u (seq (:updated by))]
      (println "updated:" (str/join ", " (sort (map second u)))))
    (when-let [sk (seq (:skipped by))]
      (println "skipped (no slug):" (str/join ", " (map second sk))))))
