;; options-custom.fnl -- the Custom activities editor: an AceConfig sub-panel
;; (ROADMAP Phase 8 §1).
;;
;; Split out of src/ui/options.fnl (size rule), the options-goals.fnl contract:
;; M.custom-group is a PURE builder (busted-tested) from a small api to an
;; AceConfig group spec; the :set closures mutate the persisted
;; db.profile.custom-activities list IN PLACE and fire api.on-change to
;; re-plan.
;;
;; The pending new-activity fields live in builder closures, not the DB --
;; nothing persists until Add validates the assembled CustomActivity via
;; custom-activities.normalize, so a half-filled form can never write a
;; corrupt row. Gold is entered in GOLD and stored in copper (the
;; options-goals parse-target convention); blank optional fields stay
;; unauthored (nil), never zero-filled.

(local Routina (or _G.Routina {}))
(local custom-activities
       (or Routina.custom-activities (require :src.domain.custom-activities)))

(local options-goals (or Routina.options-goals (require :src.ui.options-goals)))
(local format (or Routina.format (require :src.ui.format)))

(local M {})

;; --- Static choices (pure) ---------------------------------------------------

(local reset-values {:weekly "Weekly reset"
                     :daily "Daily reset"
                     :none "No reset"})

;; Factions with modelled rep yields (mirrors options-goals faction-values),
;; plus the no-rep sentinel.
(local faction-values {:none "(no reputation)" :ogrila "Ogri'la"})

(local copper-per-gold 10000)

;; --- Pure helpers ------------------------------------------------------------

(fn trim [?s]
  "The string with surrounding whitespace removed (nil -> empty)."
  (string.match (tostring (or ?s "")) "^%s*(.-)%s*$"))

(fn positive-int [?text]
  "A positive integer parsed from form text, or nil."
  (let [n (tonumber ?text)]
    (when (and n (> n 0)) (math.floor n))))

(fn maybe-gold [?text]
  "Copper parsed from a gold-denominated form field; blank/invalid -> nil."
  (let [n (tonumber ?text)]
    (when (and n (>= n 0)) (* n copper-per-gold))))

(lambda M.next-custom-id [customs]
  "A fresh activity id ('custom-<N>', N above every existing one).
   Deterministic -- derived from the list, no clock; never collides with a
   registry id.
   Domain:  customs : [CustomActivity]
   Returns: string."
  (let [top (accumulate [top 0 _ c (ipairs customs)]
              (let [n (tonumber (or (string.match (tostring c.id)
                                                  "^custom%-(%d+)$")
                                    ""))]
                (if (and n (> n top)) n top)))]
    (.. :custom- (+ top 1))))

(lambda M.custom-label [custom]
  "One authored activity as a list line for the editor and the remove picker.
   Domain:  custom : CustomActivity
   Returns: string."
  (let [yields []]
    (when (and custom.badges (> custom.badges 0))
      (table.insert yields (.. custom.badges " badges")))
    (when (and custom.gold-max (> custom.gold-max 0))
      (table.insert yields
                    (.. (format.gold custom.gold-min) "-"
                        (format.gold custom.gold-max))))
    (when custom.rep-faction
      (table.insert yields
                    (.. "+" (tostring custom.rep-amount) " "
                        (tostring custom.rep-faction))))
    (.. (tostring custom.name) " (" custom.est-minutes " min, "
        (tostring custom.reset) ")"
        (if (= 0 (length yields)) ""
            (.. " -- " (table.concat yields ", "))))))

(fn custom-lines [customs]
  "The current-activities description text."
  (if (= 0 (length customs))
      (.. "No custom activities yet -- add your own routine below and the "
          "plan carries it every week.")
      (table.concat (icollect [i c (ipairs customs)]
                      (.. i ". " (M.custom-label c))) "\n")))

(fn goal-values [goal-list]
  "AceConfig select values of the player's goals (id -> label) + no-link."
  (collect [_ g (ipairs goal-list) &into {:none "(no goal link)"}]
    (values (tostring g.id) (options-goals.goal-label g))))

;; --- Public API ----------------------------------------------------------------

(lambda M.custom-group [api]
  "Build the Custom activities AceConfig group: current list, add form
   (name / length / reset / optional yields / goal link) and remove picker.
   Domain:  api : {:custom-activities the persisted [CustomActivity] list
                                      (db.profile), mutated in place
                   :goals ?[GoalDef]  -- for the goal-link choices
                   :on-change (fn []) | nil  -- fired after any mutation
                   :notify (fn []) | nil} -- AceConfigRegistry refresh
   Returns: an AceConfig group table."
  (var pending-name "")
  (var pending-minutes "")
  (var pending-reset :weekly)
  (var pending-badges "")
  (var pending-gold-min "")
  (var pending-gold-max "")
  (var pending-faction :none)
  (var pending-rep "")
  (var pending-goal :none)
  (var pending-remove nil)
  (let [customs api.custom-activities
        goal-list (or api.goals [])
        changed (fn []
                  (when api.on-change (api.on-change))
                  (when api.notify (api.notify)))
        add! (fn []
               (let [name (trim pending-name)
                     rep? (not= pending-faction :none)
                     draft {:id (M.next-custom-id customs)
                            : name
                            :est-minutes (positive-int pending-minutes)
                            :reset pending-reset
                            :badges (positive-int pending-badges)
                            :gold-min (maybe-gold pending-gold-min)
                            :gold-max (maybe-gold pending-gold-max)
                            :rep-faction (when rep?
                                           (tostring pending-faction))
                            :rep-amount (when rep?
                                          (positive-int pending-rep))
                            :goal-id (when (not= pending-goal :none)
                                       (tostring pending-goal))}
                     valid (custom-activities.normalize [draft])]
                 (when (and (not= name "") (= 1 (length valid)))
                   (table.insert customs (. valid 1))
                   (set pending-name "")
                   (set pending-minutes "")
                   (set pending-badges "")
                   (set pending-gold-min "")
                   (set pending-gold-max "")
                   (set pending-rep "")
                   (changed))))
        remove! (fn []
                  (let [idx (tonumber pending-remove)]
                    (when (and idx (. customs idx))
                      (table.remove customs idx)
                      (set pending-remove nil)
                      (changed))))]
    {:type :group
     :name "Custom activities"
     :order 6
     :args {:about {:type :description
                    :order 0
                    :name (.. "Add what the catalog doesn't know -- a farm "
                              "lap, a daily errand, a fishing hour. It joins "
                              "the weekly plan as an equal: authored yields "
                              "pay toward your goals; with none it sits at "
                              "the tail as a reminder.")}
            :current {:type :description
                      :order 1
                      :name (fn [] (custom-lines customs))}
            :name {:type :input
                   :name :Name
                   :order 2
                   :get (fn [_] pending-name)
                   :set (fn [_ v] (set pending-name v))}
            :minutes {:type :input
                      :name "Length (minutes)"
                      :order 3
                      :get (fn [_] pending-minutes)
                      :set (fn [_ v] (set pending-minutes v))}
            :reset {:type :select
                    :name :Reset
                    :order 4
                    :values reset-values
                    :get (fn [_] pending-reset)
                    :set (fn [_ v] (set pending-reset v))}
            :badges {:type :input
                     :name "Badges per clear (optional)"
                     :order 5
                     :get (fn [_] pending-badges)
                     :set (fn [_ v] (set pending-badges v))}
            :gold-min {:type :input
                       :name "Gold per clear, low (optional)"
                       :desc "An honest band, entered in gold. Set both ends or neither."
                       :order 6
                       :get (fn [_] pending-gold-min)
                       :set (fn [_ v] (set pending-gold-min v))}
            :gold-max {:type :input
                       :name "Gold per clear, high (optional)"
                       :order 7
                       :get (fn [_] pending-gold-max)
                       :set (fn [_ v] (set pending-gold-max v))}
            :rep-faction {:type :select
                          :name "Reputation faction (optional)"
                          :order 8
                          :values faction-values
                          :get (fn [_] pending-faction)
                          :set (fn [_ v] (set pending-faction v))}
            :rep-amount {:type :input
                         :name "Reputation per clear"
                         :order 9
                         :hidden (fn [] (= pending-faction :none))
                         :get (fn [_] pending-rep)
                         :set (fn [_ v] (set pending-rep v))}
            :goal-link {:type :select
                        :name "Linked goal (optional)"
                        :order 10
                        :values (fn [] (goal-values goal-list))
                        :get (fn [_] pending-goal)
                        :set (fn [_ v] (set pending-goal v))}
            :add {:type :execute :name "Add activity" :order 11 :func add!}
            :remove-pick {:type :select
                          :name "Activity to remove"
                          :order 12
                          :values (fn []
                                    (collect [i c (ipairs customs)]
                                      (values (tostring i) (M.custom-label c))))
                          :get (fn [_] pending-remove)
                          :set (fn [_ v] (set pending-remove v))}
            :remove {:type :execute
                     :name "Remove selected"
                     :order 13
                     :func remove!}}}))

;; --- Register into the addon namespace ---------------------------------------

(set _G.Routina Routina)
(set Routina.options-custom M)

M
