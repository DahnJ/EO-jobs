(ns eojobs.dedup
  "Merge confirmed duplicate entries from known_duplicates.json into the keeper,
  union their list/map fields, then delete the dropped files. Re-runnable: a
  group whose dropped files are already gone is a no-op."
  (:require [cheshire.core :as json]
            [clojure.string :as str]
            [eojobs.db :as db]))

(defn- union-vec [a b]
  (into (vec a) (remove (set a) b)))

(defn- fold-group [g]
  (let [keep (:keep g)
        kp   (db/path keep)]
    (if-not (.exists kp)
      (do (println "skip" (:slugs g) ": keeper" keep "missing") nil)
      (let [{:keys [krec dropped]}
            (reduce
             (fn [acc s]
               (let [dp (db/path s)]
                 (if (or (= s keep) (not (.exists dp)))
                   acc
                   (let [drec (db/parse (slurp dp))]
                     (.delete dp)
                     (-> acc
                         (update :dropped conj s)
                         (update :krec
                                 (fn [k]
                                   (-> k
                                       (update :careers-urls union-vec (:careers-urls drec))
                                       (update :locations union-vec (:locations drec))
                                       ;; keep keeper's links; add the dropped one's extras
                                       (update :links #(merge (:links drec) %))))))))))
             {:krec (db/parse (slurp kp)) :dropped []}
             (:slugs g))]
        (when (seq dropped)
          (let [note (str "[dedup] merged duplicate(s) " (str/join ", " dropped)
                          " — " (:reason g))
                body (:body krec "")]
            (db/save keep (assoc krec :body
                                 (if (str/blank? body) note
                                     (str (str/trim body) "\n\n" note))))
            (println "merged" dropped "->" keep)
            keep))))))

(defn run [_]
  (let [groups (json/parse-string (slurp "known_duplicates.json") true)
        merged (count (remove nil? (map fold-group groups)))]
    (println "done:" merged "group(s) merged")))
