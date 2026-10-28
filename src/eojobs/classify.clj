(ns eojobs.classify
  "Set each company's :type (from agent verdicts in companies/_inbox/class_*.json,
  with a conglomerate override) and derive :listed for the README.

  NOTE: the type decision is a plain `cond` — override > agent > existing. A
  multimethod would fit if `:type` dispatched to genuinely different *behaviour*,
  but here it only selects a value, so a multimethod would be over-engineering."
  (:require [cheshire.core :as json]
            [clojure.string :as str]
            [eojobs.db :as db]))

;; Large multi-division parents where EO is one small division — forced override.
(def conglomerates
  #{"airbus-space" "airbus-defence-and-space" "trimble" "harris" "gmv"
    "telespazio" "hexagon-geospatial" "nv5" "merrick" "red-wire-space"
    "iabg" "l3harris"})

(def valid
  #{"commercial-eo" "consultancy" "reseller" "software"
    "conglomerate" "nonprofit" "not-eo"})

(defn load-verdicts
  "slug -> [type reason] from class_*.json inbox files."
  []
  (into {}
        (for [f (db/ls db/inbox-dir #"class_.*\.json")
              r (json/parse-string (slurp f) true)
              :when (valid (:type r))]
          [(:slug r) [(:type r) (:reason r "")]])))

(defn- has-careers? [rec]
  (boolean (some #(and (string? %) (str/starts-with? % "http"))
                 (:careers-urls rec))))

(defn classify-one [slug rec verdicts]
  (let [[typ reason]
        (cond
          (conglomerates slug) ["conglomerate" "known large multi-division company"]
          (verdicts slug)      (let [[t r] (verdicts slug)] [t (str r " [agent]")])
          :else                [(or (:type rec) "commercial-eo")
                                (or (:type-reason rec) "unclassified")])]
    (assoc rec
           :type typ
           :type-reason reason
           :listed (boolean (and (= typ "commercial-eo")
                                 (= (:status rec) "active")
                                 (has-careers? rec))))))

(defn run [_]
  (let [verdicts (load-verdicts)]
    (loop [pairs (db/load-all), counts {}, changed [], listed 0]
      (if-let [[slug rec] (first pairs)]
        (let [out (classify-one slug rec verdicts)
              old (:type rec)]
          (db/save slug out)
          (recur (rest pairs)
                 (update counts (:type out) (fnil inc 0))
                 (if (and old (not= old (:type out)))
                   (conj changed [(:name out) old (:type out)])
                   changed)
                 (if (:listed out) (inc listed) listed)))
        (do
          (println "type distribution:" counts)
          (println "LISTED (commercial-eo + active + has careers):" listed)
          (printf "%ntype changed vs previous: %d%n" (count changed))
          (doseq [[name o n] (sort changed)]
            (printf "  %s: %s -> %s%n" name o n)))))))
