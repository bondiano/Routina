;; custom-chains.fnl -- player-authored chains: the route constructor
;; (ROADMAP Phase 8 §3).
;;
;; "One mechanism, two authors": the importer generates ChainDefs from the
;; Attune dataset; the player authors them as an ordered checklist in the
;; Chains tab. This module owns the persisted authoring shape
;; (schemas.CustomChain, stored at db.profile.custom-chains) and its pure
;; projection to-chain-def into a plain schemas.ChainDef (:kind :custom,
;; linear :manual steps) -- chain queries, ChainProgress transforms and
;; persistence (db.char.chains) then treat both provenances identically.
;; :manual steps carry no quest-id, so seed-from-completed never lights them:
;; a custom chain advances ONLY through the checklist
;; (chains.mark-step / unmark-step via events.mark-chain-step!).
;;
;; PURE domain module: no WoW API, no I/O, no time; inputs never mutated.
;; Being user-authored data, invalid persisted entries are DROPPED on load
;; (the goals.normalize pattern), never an error.

(local Routina (or _G.Routina {}))
(local schemas (or Routina.schemas (require :src.domain.schemas)))
(local validate (or Routina.validate (require :src.domain.validate)))

(local M {})

;; The expansion tag the generated registry uses; authored chains share it so
;; any expac-keyed grouping treats both alike.
(local custom-expac "The Burning Crusade")

;; --- Helpers (private) -------------------------------------------------------

(fn trim [?s]
  "The string with surrounding whitespace removed (nil -> empty)."
  (string.match (tostring (or ?s "")) "^%s*(.-)%s*$"))

(fn copy-step [s]
  {:label s.label
   :coord (when s.coord
            {:map-id s.coord.map-id :x s.coord.x :y s.coord.y})})

(fn copy-custom [c]
  "A fresh copy of one CustomChain (steps deep enough for SavedVariables)."
  {:id c.id
   :name c.name
   :created c.created
   :steps (icollect [_ s (ipairs c.steps)] (copy-step s))})

(fn invariants-ok? [c]
  "Cross-field invariants the field schema cannot express: a non-blank name,
   at least one step, and no blank step labels."
  (and (not= "" (trim c.name)) (> (length c.steps) 0)
       (accumulate [ok true _ s (ipairs c.steps) &until (not ok)]
         (and ok (not= "" (trim s.label))))))

;; --- Public API --------------------------------------------------------------

(lambda M.normalize [?persisted]
  "Coerce a possibly-nil / possibly-corrupt persisted list into valid
   CustomChain records. User-authored data: invalid entries are DROPPED,
   never an error (the goals.normalize pattern).
   Domain:  ?persisted : table | nil -- db.profile.custom-chains
   Returns: [CustomChain] -- fresh, possibly empty."
  (if (not= (type ?persisted) :table) []
      (icollect [_ c (ipairs ?persisted)]
        (when (and (= (type c) :table)
                   (let [r (validate.check schemas.CustomChain c)] r.ok)
                   (invariants-ok? c))
          (copy-custom c)))))

(lambda M.to-db [customs]
  "A fresh plain copy of the custom-chain list for SavedVariables, so the
   persisted table never aliases the live session copy.
   Domain:  customs : [CustomChain]
   Returns: [CustomChain] (plain data)"
  (icollect [_ c (ipairs customs)] (copy-custom c)))

(lambda M.parse-steps [?text]
  "Steps parsed from constructor-editor text: one step per non-blank line,
   labels trimmed. Pure -- the Chains-tab editor calls this, busted tests it.
   Domain:  ?text : string | nil -- the MultiLineEditBox contents
   Returns: [CustomChainStep] -- possibly empty."
  (let [steps []]
    (each [line (string.gmatch (tostring (or ?text "")) "[^\n]+")]
      (let [label (trim line)]
        (when (not= label "")
          (table.insert steps {: label}))))
    steps))

(lambda M.next-id [customs]
  "A fresh chain id ('chain-<N>', N above every existing one). Deterministic
   -- derived from the list, no clock; never collides with the registry's
   word slugs.
   Domain:  customs : [CustomChain]
   Returns: string."
  (let [top (accumulate [top 0 _ c (ipairs customs)]
              (let [n (tonumber (or (string.match (tostring c.id)
                                                  "^chain%-(%d+)$")
                                    ""))]
                (if (and n (> n top)) n top)))]
    (.. :chain- (+ top 1))))

(lambda M.to-chain-def [custom]
  "Project one authored chain into the planner's registry shape: a linear
   ChainDef (:kind :custom) of :manual steps -- step i follows step i-1
   (:follows-mode :all), :stage i preserves the authored order, no quest-ids
   so the quest log never seeds it.
   Domain:  custom : CustomChain (already normalized)
   Returns: schemas.ChainDef with :kind :custom."
  {:id custom.id
   :name custom.name
   :kind :custom
   :expac custom-expac
   :steps (icollect [i s (ipairs custom.steps)]
            {:id (.. :s i)
             :type :manual
             :label s.label
             :stage i
             :follows (if (> i 1) [(.. :s (- i 1))] [])
             :follows-mode :all
             :coord (when s.coord
                      {:map-id s.coord.map-id :x s.coord.x :y s.coord.y})})})

;; --- Register into the addon namespace ---------------------------------------
;;
;; Dual-mode: in-game, .toc load order populates `_G.Routina.custom-chains`
;; after chains. In tests, consumers fall through to
;; `(require :src.domain.custom-chains)` -> the same M.

(set _G.Routina Routina)
(set Routina.custom-chains M)

M
