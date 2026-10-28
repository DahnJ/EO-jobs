(ns eojobs.fixup
  "Idempotent data hygiene: normalize the free-text :remote field to canonical
  values, and backfill a flag emoji on locations lacking one."
  (:require [eojobs.db :as db]
            [eojobs.flags :as flags]))

(def remote-map
  {"US based" "Yes (US)" "US-based" "Yes (US)" "Yes (US-based)" "Yes (US)"
   "Yes (US-based?)" "Yes (US)" "Yes (~US?)" "Yes (US)" "US resident" "Yes (US)"
   "Canada-based" "Yes (Canada)" "Australia-based" "Yes (Australia)"
   "Yes (UK-based?)" "Yes (UK)" "Yes (UK-elligible)" "Yes (UK)"
   "Yes (France-based?)" "Yes (France)"
   "~Yes" "Yes"
   "Some roles remote" "Hybrid" "Some" "Hybrid" "Occasionally" "Hybrid"
   "No (Partial)" "Hybrid"
   "Maybe" "" "?" ""
   "No jobs" "" "No Jobs" "" "None" "" "N/A" "" "TBD" ""
   "Yes (UK, Luxembroug, France, Belgium, Germany)"
   "Yes (UK, Luxembourg, France, Belgium, Germany)"})

(defn fixup-one
  "Returns [new-record remote-changed? locs-flagged-count]."
  [rec]
  (let [rv      (:remote rec "")
        rv'     (get remote-map rv rv)
        locs    (:locations rec [])
        locs'   (flags/flag-all locs)
        flagged (count (filter true? (map not= locs locs')))]
    [(assoc rec :remote rv' :locations locs')
     (not= rv' rv)
     flagged]))

(defn run [_]
  (loop [pairs (db/load-all), remote-changed 0, locs-flagged 0]
    (if-let [[slug rec] (first pairs)]
      (let [[out rc? lf] (fixup-one rec)]
        (when (or rc? (pos? lf)) (db/save slug out))
        (recur (rest pairs) (+ remote-changed (if rc? 1 0)) (+ locs-flagged lf)))
      (printf "remote normalized: %d; locations flagged: %d%n"
              remote-changed locs-flagged))))
