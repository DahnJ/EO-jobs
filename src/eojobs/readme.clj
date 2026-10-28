(ns eojobs.readme
  "Generate README.md from the DB. Only :listed companies appear. The table is
  rendered row-independent (each cell minimal-width) so refresh diffs stay
  row-local; GitHub renders it identically to a padded table."
  (:require [clojure.string :as str]
            [eojobs.db :as db]))

(def ^:private height 25)

(def ^:private i-business
  {"crunchbase" "https://i.imgur.com/H3e6fly.png"
   "spac"       "https://i.imgur.com/BjJ1vkt.png"})

(def ^:private i-socials
  {"twitter"  "https://i.imgur.com/d4HTDdM.png"
   "youtube"  "https://i.imgur.com/P1O5Rjh.png"
   "github"   "https://i.imgur.com/5rpIT2Z.png"
   "linkedin" "https://i.imgur.com/SSBwtJu.png"})

(def ^:private hide-remote #{"" "No" "No jobs"})
(def ^:private columns ["Name" "Description" "Jobs" "Locations" "Remote" "Social" "Business"])

(defn- icons [links icon-links]
  (apply str
         (for [[k src] icon-links :when (get links k)]
           (str "<a href=\"" (get links k) "\"><img src=" src " height=" height "></a>"))))

(defn- row [rec]
  (let [links (:links rec {})]
    {"Name"        (str "<a href=\"" (:website rec) "\">" (:name rec) "</a>")
     "Description" (:description rec "")
     "Jobs"        (apply str (map-indexed
                               (fn [i url] (str "<a href=\"" url "\">[" (inc i) "]</a>"))
                               (:careers-urls rec [])))
     "Locations"   (str/join "<br />" (:locations rec []))
     "Remote"      (let [r (:remote rec "")] (if (hide-remote r) "" r))
     "Social"      (icons links i-socials)
     "Business"    (icons links i-business)}))

(defn- table [rows]
  (str/join "\n"
            (concat
             [(str "| " (str/join " | " columns) " |")
              (str "|" (str/join "|" (repeat (count columns) ":---")) "|")]
             (for [r rows]
               (str "| " (str/join " | " (map #(str (get r %)) columns)) " |")))))

(defn run [_]
  (let [recs (->> (db/load-all)
                  (map second)
                  (filter :listed)
                  (sort-by #(str/lower-case (:name %))))
        out  (str (slurp "intro.md") (table (map row recs)) "\n")]
    (spit "README.md" out)
    (println "Wrote README.md (" (count recs) "companies)")))
