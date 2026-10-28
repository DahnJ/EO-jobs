(ns eojobs.flags
  "Prepend a flag emoji (or globe) to a location string. Flags are derived from
  ISO-3166 alpha-2 codes via regional-indicator code points, so adding a country
  is one map entry."
  (:require [clojure.string :as str]))

(defn iso->flag
  "Two-letter ISO code -> flag emoji. Regional indicators live in the
  supplementary plane (> 0xFFFF), so we build via code points, not chars."
  [iso2]
  (let [sb (StringBuilder.)]
    (doseq [c (str/upper-case iso2)]
      (.appendCodePoint sb (+ 0x1F1E6 (- (int c) (int \A)))))
    (.toString sb)))

(def country
  {"united states" "US" "usa" "US" "u.s." "US" "u.s.a" "US" "us" "US"
   "united kingdom" "GB" "uk" "GB" "u.k." "GB" "england" "GB"
   "scotland" "GB" "wales" "GB" "northern ireland" "GB" "britain" "GB"
   "france" "FR" "germany" "DE" "netherlands" "NL" "the netherlands" "NL"
   "spain" "ES" "italy" "IT" "portugal" "PT" "belgium" "BE"
   "luxembourg" "LU" "switzerland" "CH" "austria" "AT" "ireland" "IE"
   "sweden" "SE" "norway" "NO" "denmark" "DK" "finland" "FI"
   "iceland" "IS" "poland" "PL" "czech republic" "CZ" "czechia" "CZ"
   "slovakia" "SK" "slovenia" "SI" "hungary" "HU" "romania" "RO"
   "bulgaria" "BG" "greece" "GR" "croatia" "HR" "serbia" "RS"
   "ukraine" "UA" "belarus" "BY" "estonia" "EE" "latvia" "LV"
   "lithuania" "LT" "russia" "RU" "turkey" "TR" "türkiye" "TR"
   "cyprus" "CY" "malta" "MT" "uzbekistan" "UZ" "kazakhstan" "KZ"
   "canada" "CA" "mexico" "MX" "brazil" "BR" "argentina" "AR"
   "chile" "CL" "colombia" "CO" "peru" "PE" "uruguay" "UY"
   "ecuador" "EC" "bolivia" "BO" "china" "CN" "japan" "JP"
   "south korea" "KR" "korea" "KR" "india" "IN" "singapore" "SG"
   "taiwan" "TW" "hong kong" "HK" "indonesia" "ID" "malaysia" "MY"
   "thailand" "TH" "vietnam" "VN" "philippines" "PH" "pakistan" "PK"
   "bangladesh" "BD" "sri lanka" "LK" "australia" "AU"
   "new zealand" "NZ" "israel" "IL" "uae" "AE"
   "united arab emirates" "AE" "saudi arabia" "SA" "qatar" "QA"
   "kuwait" "KW" "bahrain" "BH" "oman" "OM" "jordan" "JO"
   "lebanon" "LB" "egypt" "EG" "south africa" "ZA" "kenya" "KE"
   "nigeria" "NG" "ghana" "GH" "tanzania" "TZ" "uganda" "UG"
   "rwanda" "RW" "ethiopia" "ET" "morocco" "MA" "tunisia" "TN"
   "senegal" "SN" "azerbaijan" "AZ" "georgia" "GE" "armenia" "AM"
   "iraq" "IQ" "iran" "IR"})

(def city
  {;; UK
   "london" "GB" "edinburgh" "GB" "glasgow" "GB" "bristol" "GB"
   "oxford" "GB" "cambridge" "GB" "reading" "GB" "guildford" "GB"
   "plymouth" "GB" "didcot" "GB" "harwell" "GB" "skipton" "GB"
   "leicester" "GB" "belfast" "GB" "musselburgh" "GB" "sywell" "GB"
   "northamptonshire" "GB"
   ;; US
   "seattle" "US" "boston" "US" "berkeley" "US" "denver" "US"
   "houston" "US" "midland" "US" "austin" "US" "madison" "US"
   "santa fe" "US" "washington" "US" "san mateo" "US" "bozeman" "US"
   "lafayette" "US" "north potomac" "US" "san francisco" "US"
   "new york" "US" "montana" "US" "california" "US" "colorado" "US"
   "texas" "US" "wi" "US" "tx" "US" "ca" "US" "wa" "US" "co" "US"
   "ny" "US" "ma" "US"
   ;; other
   "sydney" "AU" "melbourne" "AU" "seoul" "KR" "tokyo" "JP"
   "singapore" "SG" "amsterdam" "NL" "zwolle" "NL" "hamburg" "DE"
   "munich" "DE" "berlin" "DE" "paris" "FR" "toulouse" "FR"
   "hyderabad" "IN" "bangalore" "IN" "bengaluru" "IN" "changchun" "CN"
   "vancouver" "CA" "halifax" "CA" "calgary" "CA" "toronto" "CA"
   "zurich" "CH" "zürich" "CH" "vienna" "AT" "graz" "AT"
   "warsaw" "PL" "wrocław" "PL" "wroclaw" "PL" "kraków" "PL"
   "krakow" "PL" "gliwice" "PL" "piaseczno" "PL" "brussels" "BE"
   "liege" "BE" "liège" "BE" "mont-saint-guibert" "BE" "athens" "GR"
   "lisbon" "PT" "porto" "PT" "brno" "CZ" "prague" "CZ"
   "sofia" "BG" "ljubljana" "SI" "bratislava" "SK" "tashkent" "UZ"
   "minsk" "BY" "lagos" "NG" "abuja" "NG" "johannesburg" "ZA"
   "nairobi" "KE" "buenos aires" "AR" "ayacucho" "PE"
   "esch-sur-alzette" "LU" "abu dhabi" "AE" "dubai" "AE"})

(def region
  {"remote" "🌐" "global" "🌐" "worldwide" "🌐" "anywhere" "🌐"
   "world" "🌐" "many locations" "🌐" "many countries" "🌐"
   "multiple continents" "🌐" "europe" "🌍" "asia pacific" "🌏"
   "asia" "🌏" "africa" "🌍"})

(defn- flag-cp? [cp]
  (or (<= 0x1F1E6 cp 0x1F1FF)       ; regional indicators A-Z
      (<= 0x1F30D cp 0x1F310)))     ; 🌍 🌎 🌏 🌐

(defn has-flag?
  "True if the location already starts with a flag/globe (add-flag always prepends)."
  [loc]
  (and (seq loc) (flag-cp? (.codePointAt loc 0))))

(defn- detect
  "Best-guess flag for a location string, or nil."
  [loc]
  (let [low    (str/lower-case (str/trim loc))
        tokens (->> (str/split (str/replace low ";" ",") #",")
                    (map str/trim) (remove str/blank?))]
    (or
      ;; last token first — the country is usually rightmost and most reliable
      (some (fn [tok] (cond (country tok) (iso->flag (country tok))
                            (city tok)    (iso->flag (city tok))))
            (reverse tokens))
      ;; a region keyword anywhere
      (some (fn [[kw fl]] (when (str/includes? low kw) fl)) region)
      ;; fallback: any country/city name (len > 3) appearing anywhere
      (some (fn [[name iso]] (when (and (> (count name) 3) (str/includes? low name))
                               (iso->flag iso))) country)
      (some (fn [[name iso]] (when (and (> (count name) 3) (str/includes? low name))
                               (iso->flag iso))) city))))

(defn add-flag
  "loc with a leading flag/globe; unchanged if it has one already or none fits."
  [loc]
  (if (or (str/blank? loc) (has-flag? loc))
    loc
    (if-let [fl (detect loc)] (str fl " " loc) loc)))

(defn flag-all [locations] (mapv add-flag (or locations [])))
