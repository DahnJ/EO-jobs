(ns eojobs.export
  "Build the compact inputs the classification and dedup agents read."
  (:require [cheshire.core :as json]
            [clojure.string :as str]
            [clojure.tools.cli :as cli]
            [eojobs.db :as db]
            [eojobs.net :as net]))

(defn class-input
  "JSONL of {slug,name,desc,body} — one company per line."
  [args]
  (let [{:keys [options]}
        (cli/parse-opts args [[nil "--out PATH" :default "/tmp/class_in.jsonl"]])
        out  (:out options)
        rows (for [[slug rec] (db/load-all)]
               {:slug slug
                :name (:name rec)
                :desc (:description rec "")
                :body (subs (str/replace (:body rec "") "\n" " ")
                            0 (min 300 (count (:body rec ""))))})]
    (spit out (str (str/join "\n" (map #(json/generate-string %) rows)) "\n"))
    (println (count rows) "companies ->" out)))

(defn dedup-index
  "TSV of slug<TAB>name<TAB>domain."
  [args]
  (let [{:keys [options]}
        (cli/parse-opts args [[nil "--out PATH" :default "/tmp/company_index.tsv"]])
        out  (:out options)
        rows (for [[slug rec] (db/load-all)]
               (str slug "\t" (:name rec) "\t"
                    (if (str/blank? (:website rec)) "" (net/reg-domain (:website rec)))))]
    (spit out (str (str/join "\n" rows) "\n"))
    (println (count rows) "companies ->" out)))
