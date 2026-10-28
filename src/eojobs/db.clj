(ns eojobs.db
  "The only namespace that knows the on-disk format. Everywhere else, a company
  is a plain Clojure map with kebab-case keyword keys."
  (:require [cheshire.core :as json]
            [clojure.java.io :as io]
            [clojure.string :as str]))

(def db-dir "companies")
(def inbox-dir "companies/_inbox")

;; --- the boundary: snake_case on disk <-> :kebab-case in memory ---
;; A single total translation, not a hand-maintained table.
(defn- key->kw [k] (keyword (str/replace k "_" "-")))
(defn- kw->key [kw] (str/replace (name kw) "-" "_"))

;; Field order on disk. Unknown extras are appended, sorted, for determinism.
(def field-order
  [:name :status :website :careers-urls :locations :remote :remote-evidence
   :remote-confidence :description :satellites :category :listed :links
   :source :last-checked :type :type-reason])

(defn parse
  "Parse a company file's text into a record map. Each frontmatter line is
  `key: <json>`; the body is the free text after the closing `---`."
  [text]
  (when-not (str/starts-with? text "---")
    (throw (ex-info "missing frontmatter" {})))
  (let [[_ fm body] (str/split text #"---" 3)
        record (into {}
                     (for [line (str/split-lines (str/trim fm))
                           :when (not (str/blank? line))
                           :let [[k v] (str/split line #": " 2)]]
                       ;; values are JSON; :links keeps string keys (no keywordize)
                       [(key->kw k) (json/parse-string v)]))]
    (assoc record :body (str/trim (or body "")))))

(defn dump
  "Serialize a record back to file text (frontmatter values as JSON)."
  [record]
  (let [body  (:body record "")
        known (filter #(contains? record %) field-order)
        extra (sort (remove (set field-order) (remove #{:body} (keys record))))
        lines (concat ["---"]
                      (for [k (concat known extra)]
                        (str (kw->key k) ": " (json/generate-string (get record k))))
                      ["---"])
        text  (str (str/join "\n" lines) "\n")]
    (if (str/blank? body)
      text
      (str text "\n" (str/trim body) "\n"))))

;; --- filesystem helpers ---
(defn ls
  "Sorted seq of File in `dir` whose names match regex `re`."
  [dir re]
  (->> (.listFiles (io/file dir))
       (filter #(re-matches re (.getName %)))
       (sort-by #(.getName %))))

(defn slug [file] (str/replace (.getName file) #"\.md$" ""))
(defn path [s] (io/file db-dir (str s ".md")))

(defn load-all
  "Seq of [slug record] pairs for every company file."
  []
  (for [f (ls db-dir #".*\.md")]
    [(slug f) (parse (slurp f))]))

(defn save [s record] (spit (path s) (dump record)))
