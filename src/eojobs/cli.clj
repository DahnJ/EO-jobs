(ns eojobs.cli
  "Subcommand dispatch + the small `stats` summary."
  (:require [clojure.string :as str]
            [eojobs.db :as db]
            [eojobs.merge :as merge]
            [eojobs.classify :as classify]
            [eojobs.dedup :as dedup]
            [eojobs.fixup :as fixup]
            [eojobs.flags :as flags]
            [eojobs.readme :as readme]
            [eojobs.net :as net]
            [eojobs.export :as export]))

(defn stats [_]
  (let [recs (map second (db/load-all))]
    (println "loaded" (count recs) "companies")
    (println "by status:" (frequencies (map :status recs)))
    (println "by source:" (frequencies (map :source recs)))
    (println "listed (README candidates):" (count (filter :listed recs)))))

(defn flags-cmd
  "Backfill flags across the DB and report unflagged stragglers."
  [_]
  (let [results (for [[slug rec] (db/load-all)]
                  (let [locs (:locations rec []) new (flags/flag-all locs)]
                    (when (not= new locs) (db/save slug (assoc rec :locations new)))
                    {:fixed (count (filter true? (map not= locs new)))
                     :misses (remove flags/has-flag? new)}))
        fixed   (reduce + (map :fixed results))
        misses  (sort (distinct (mapcat :misses results)))]
    (printf "flagged %d locations; still unflagged: %d%n" fixed (count misses))
    (when (seq misses) (println "unmatched:" (vec misses)))))

(def commands
  {"merge"           merge/run
   "classify"        classify/run
   "dedup"           dedup/run
   "fixup"           fixup/run
   "flags"           flags-cmd
   "readme"          readme/run
   "check-links"     net/check-links
   "check-redirects" net/check-redirects
   "stats"           stats
   "class-input"     export/class-input
   "dedup-index"     export/dedup-index})

(defn -main [& [cmd & args]]
  (if-let [f (get commands cmd)]
    (do (f (vec args)) (flush) (System/exit 0))
    (do (println "unknown command:" cmd)
        (println "available:" (str/join " " (sort (keys commands))))
        (System/exit 1))))
