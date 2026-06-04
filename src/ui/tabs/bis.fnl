;; tabs/bis.fnl -- BiS tab content: a best-in-slot checklist for the player's
;; class/spec/phase on AceGUI-3.0, marking which slots are already filled.
;;
;; END-TO-END SLICE: src/core/planner.fnl reads the live client into a route
;; input; its ctx carries class/spec/phase (src/domain/ctx.fnl resolves the spec
;; from talents) and owned-items (the set of item ids the player has). This tab
;; pulls the matching BiS entries from src/domain/bis-catalog.fnl, keeps one row
;; per gear slot, and flags each as owned or still-to-chase.
;;
;; UI.md split: the data->render-spec is PURE (M.list-view-model, busted-tested);
;; building the AceGUI widgets from it is imperative. render! follows the tab
;; contract in src/ui/root.fnl: idempotent populate of the AceGUI container.
;;
;; NOTE: ROADMAP §Phase-3 wanted rows grouped by SOURCE ACTIVITY with a progress
;; band. The imported catalog's :sources only carries an :instance kind
;; (:raid/:unknown), not a real boss/instance (deferred to Phase 4 / OQ-3), so
;; grouping by source would be meaningless today. We group by gear SLOT instead
;; -- the natural BiS checklist shape -- and surface progress as an owned/total
;; header. Source-activity grouping returns once :sources carries real data.

(local Routina (or _G.Routina {}))
(local acegui (or Routina.acegui (require :src.ui.acegui)))
(local bis-catalog (or Routina.bis-catalog (require :src.domain.bis-catalog)))
(local planner (or Routina.planner (require :src.core.planner)))
(local GetItemIcon _G.GetItemIcon)
(local GameTooltip _G.GameTooltip)

(local M {})

;; --- Layout constants ------------------------------------------------------

;; Canonical gear-slot display order (mirrors schemas.BisItem :slot enum). Each
;; pair is [slot-keyword display-label]; a slot absent from the catalog for the
;; current spec/phase is simply skipped.
(local slot-order [[:head :Head]
                   [:neck :Neck]
                   [:shoulder :Shoulder]
                   [:back :Back]
                   [:chest :Chest]
                   [:wrist :Wrist]
                   [:hands :Hands]
                   [:waist :Waist]
                   [:legs :Legs]
                   [:feet :Feet]
                   [:ring1 "Ring 1"]
                   [:ring2 "Ring 2"]
                   [:trinket1 "Trinket 1"]
                   [:trinket2 "Trinket 2"]
                   [:main-hand "Main Hand"]
                   [:off-hand "Off Hand"]
                   [:ranged :Ranged]])

;; How many ranked alternatives to surface under each slot's primary. The
;; catalog keeps every source rank (ROADMAP Phase 4b), but the long Priority tail
;; (BoE / vendor catch-up down to ~rank 30) is noise in a checklist -- cap the
;; display at the primary plus this many alternatives (OQ-9, display side).
(local max-alts 3)

;; --- Pure view-model (UI.md: data->spec is pure, busted-tested) ------------

(fn slot-entries [items slot kind]
  "Kind-matching catalog entries for one slot, sorted best-first
   (phase desc, rank asc, id asc). Missing :kind defaults to :bis and missing
   :rank to 1, so hand-built fixtures stay usable."
  (let [es (icollect [_ e (ipairs items)]
             (when (and (= e.slot slot) (= (or e.kind :bis) kind))
               e))]
    (table.sort es (fn [a b]
                     (let [ra (or a.rank 1)
                           rb (or b.rank 1)]
                       (if (not= a.phase b.phase) (> a.phase b.phase)
                           (not= ra rb) (< ra rb)
                           (< a.item.id b.item.id)))))
    es))

(fn entry-view [owned e]
  "Flatten one BisItem into a render record (primary or alternative)."
  {:name e.item.name
   :item-id e.item.id
   :phase e.phase
   :rank (or e.rank 1)
   :owned? (not (not (. owned e.item.id)))})

(lambda M.list-view-model [items ?owned-set ?kind]
  "Pure render spec for the BiS checklist: one row per gear slot, in slot-order,
   each row a primary (best) target plus its top ranked alternatives.
   Domain:  items      : [BisItem] -- catalog entries already scoped to the
                         player's class/spec and phase <= current
            ?owned-set : {item-id true} | nil -- the player's owned item ids
            ?kind      : :pre-raid | :bis -- provenance to show (default :bis)
   Returns: {:summary string :owned integer :total integer :kind keyword
             :rows [{:slot-label string :name string :item-id integer
                     :phase integer :rank integer :owned? boolean
                     :alts [{:name :item-id :phase :rank :owned?} ...]} ...]}"
  (let [owned (or ?owned-set {})
        kind (or ?kind :bis)
        rows (icollect [_ [slot label] (ipairs slot-order)]
               (let [es (slot-entries items slot kind)
                     primary (. es 1)]
                 (when primary
                   (let [view (entry-view owned primary)]
                     (doto view
                       (tset :slot-label label)
                       (tset :alts
                             (icollect [i e (ipairs es)]
                               (when (and (> i 1) (<= i (+ 1 max-alts)))
                                 (entry-view owned e)))))))))
        total (length rows)
        owned-n (accumulate [n 0 _ r (ipairs rows)]
                  (if r.owned? (+ n 1) n))
        kind-label (if (= kind :pre-raid) :pre-raid :best-in-slot)]
    {:summary (.. owned-n "/" total " " kind-label " items owned")
     :owned owned-n
     : total
     : kind
     : rows}))

;; --- Item-row widgets (imperative, WoW API) --------------------------------

;; UI state for the tab. `selected-kind` is the Best-in-slot / Road-to-BiS
;; toggle; `active-container` is the AceGUI container last rendered into, so the
;; toggle can repaint in place (AceGUI owns pooling -- ReleaseChildren + rebuild).
(var selected-kind :bis)
(var active-container nil)

(fn make-tooltip-enter [item-id]
  "OnEnter handler closing over the item id. AceGUI passes the widget; the WoW
   frame is widget.frame (AceGUIWidget-InteractiveLabel.lua)."
  (fn [widget]
    (when (and item-id GameTooltip)
      (GameTooltip:SetOwner widget.frame :ANCHOR_RIGHT)
      (GameTooltip:SetItemByID item-id)
      (GameTooltip:Show))))

(fn on-row-leave []
  (when GameTooltip (GameTooltip:Hide)))

(fn build-row! [row]
  "One checklist row: '[x] Slot:  Item Name' as a hoverable InteractiveLabel.
   Owned slots recede (dim); still-to-chase slots stay prominent."
  (let [w (acegui.create! :InteractiveLabel)]
    (when w
      (w:SetFullWidth true)
      (w:SetText (.. (if row.owned? "[x] " "[ ] ") row.slot-label ":  "
                     row.name))
      (acegui.themed-label! w (if row.owned? :ink-faint :ink) :body :body)
      (when (and GetItemIcon row.item-id)
        (let [icon (GetItemIcon row.item-id)]
          (when icon
            (w:SetImage icon)
            (w:SetImageSize 18 18))))
      (w:SetCallback :OnEnter (make-tooltip-enter row.item-id))
      (w:SetCallback :OnLeave on-row-leave))
    w))

(fn build-alt-row! [alt]
  "A subordinate, indented alternative listed under a primary slot row. Always
   dim -- it's a fallback, not the target -- and a notch smaller."
  (let [w (acegui.create! :InteractiveLabel)]
    (when w
      (w:SetFullWidth true)
      (w:SetText (.. "        " (if alt.owned? "[x] " "[ ] ") alt.name))
      (acegui.themed-label! w :ink-faint :body :caption)
      (when (and GetItemIcon alt.item-id)
        (let [icon (GetItemIcon alt.item-id)]
          (when icon
            (w:SetImage icon)
            (w:SetImageSize 14 14))))
      (w:SetCallback :OnEnter (make-tooltip-enter alt.item-id))
      (w:SetCallback :OnLeave on-row-leave))
    w))

(fn add-kind-toggle! [scroll]
  "A Best-in-slot / Road-to-BiS (pre-raid) selector. AceGUI Dropdown; switching
   sets selected-kind and repaints the active container in place. No-op headless."
  (let [dd (acegui.create! :Dropdown)]
    (when dd
      (dd:SetLabel :Show)
      (dd:SetList {:bis :Best-in-slot :pre-raid "Road to BiS (pre-raid)"})
      (dd:SetValue selected-kind)
      (dd:SetFullWidth true)
      (dd:SetCallback :OnValueChanged
                      (fn [_ _ key]
                        (set selected-kind key)
                        (when active-container
                          (active-container:ReleaseChildren)
                          (M.render! active-container))))
      (scroll:AddChild dd))
    dd))

;; --- Public API ------------------------------------------------------------

(fn add-empty! [container message]
  (let [label (acegui.create! :Label)]
    (when label
      (label:SetText message)
      (label:SetFullWidth true)
      (acegui.themed-label! label :ink-faint :body :body)
      (container:AddChild label))))

(fn add-header! [scroll summary]
  (let [label (acegui.create! :Label)]
    (when label
      (label:SetText summary)
      (label:SetFullWidth true)
      (acegui.themed-label! label :gold :title :section)
      (scroll:AddChild label))))

(fn scoped-items [class spec phase]
  "Catalog entries for (class, spec) with phase <= the player's phase."
  (icollect [_ e (ipairs (bis-catalog.by-class-spec class spec))]
    (when (<= e.phase phase) e)))

(lambda M.render! [container]
  "Repaint the BiS tab into an AceGUI container (the TabGroup). Reads the live
   client's class/spec/phase + owned items and adds a ScrollFrame: a kind toggle
   (Best-in-slot / Road-to-BiS), a progress header, then one checklist row per
   gear slot -- each with its top ranked alternatives indented beneath. The
   toggle repaints in place. Idempotent -- the caller (src/ui/root.fnl) and the
   toggle both ReleaseChildren the container first. No-op headless.
   Domain:  container : an AceGUI container widget
   Returns: nil."
  (set active-container container)
  (let [scroll (acegui.create! :ScrollFrame)]
    (when (and scroll container)
      (container:SetLayout :Fill)
      (scroll:SetLayout :List)
      (scroll:SetFullWidth true)
      (scroll:SetFullHeight true)
      (container:AddChild scroll)
      (let [input (planner.route-input)
            ok? (and input input.ok)
            ctx (and ok? input.ctx)
            spec (and ctx ctx.spec)]
        (if (not spec)
            (add-empty! scroll
                        (if ok? "No best-in-slot data for this spec yet."
                            "Log in to a character to see your BiS list."))
            (let [items (scoped-items ctx.class spec ctx.phase)
                  vm (M.list-view-model items ctx.owned-items selected-kind)
                  kind-label (if (= selected-kind :pre-raid) :pre-raid
                                 :best-in-slot)]
              (add-kind-toggle! scroll)
              (if (= 0 vm.total)
                  (add-empty! scroll
                              (.. "No " kind-label " data for " (tostring spec)
                                  " at phase " (tostring ctx.phase) "."))
                  (do
                    (add-header! scroll vm.summary)
                    (each [_ row (ipairs vm.rows)]
                      (let [w (build-row! row)]
                        (when w (scroll:AddChild w)))
                      (each [_ alt (ipairs row.alts)]
                        (let [w (build-alt-row! alt)]
                          (when w (scroll:AddChild w))))))))))))
  nil)

(set _G.Routina Routina)
(set Routina.tab-bis M)

M
