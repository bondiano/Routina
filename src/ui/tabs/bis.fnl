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

;; --- Pure view-model (UI.md: data->spec is pure, busted-tested) ------------

(fn best-in [items slot]
  "The best BiS entry for a slot: the one at the highest phase (the latest
   upgrade), ties resolving to the earliest in catalog/priority order. nil when
   the slot has no entry."
  (accumulate [best nil _ e (ipairs items)]
    (if (and (= e.slot slot) (or (not best) (> e.phase best.phase))) e best)))

(lambda M.list-view-model [items ?owned-set]
  "Pure render spec for the BiS checklist: one row per gear slot, in slot-order.
   Domain:  items      : [BisItem] -- catalog entries already scoped to the
                         player's class/spec and phase <= current
            ?owned-set : {item-id true} | nil -- the player's owned item ids
   Returns: {:summary string :owned integer :total integer
             :rows [{:slot-label string :name string :item-id integer
                     :phase integer :owned? boolean} ...]}"
  (let [owned (or ?owned-set {})
        rows (icollect [_ [slot label] (ipairs slot-order)]
               (let [it (best-in items slot)]
                 (when it
                   {:slot-label label
                    :name it.item.name
                    :item-id it.item.id
                    :phase it.phase
                    :owned? (not (not (. owned it.item.id)))})))
        total (length rows)
        owned-n (accumulate [n 0 _ r (ipairs rows)]
                  (if r.owned? (+ n 1) n))]
    {:summary (.. owned-n "/" total " best-in-slot items owned")
     :owned owned-n
     : total
     : rows}))

;; --- Item-row widgets (imperative, WoW API) --------------------------------

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
   client's class/spec/phase + owned items and adds a ScrollFrame: a progress
   header then one checklist row per gear slot. Idempotent -- the caller
   (src/ui/root.fnl) ReleaseChildren's the container first. No-op headless.
   Domain:  container : an AceGUI container widget
   Returns: nil."
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
                  vm (M.list-view-model items ctx.owned-items)]
              (if (= 0 vm.total)
                  (add-empty! scroll
                              (.. "No best-in-slot data for " (tostring spec)
                                  " at phase " (tostring ctx.phase) "."))
                  (do
                    (add-header! scroll vm.summary)
                    (each [_ row (ipairs vm.rows)]
                      (let [w (build-row! row)]
                        (when w (scroll:AddChild w)))))))))))
  nil)

(set _G.Routina Routina)
(set Routina.tab-bis M)

M
