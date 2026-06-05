;; tabs/weekly-actions.fnl -- the Plan tab's pin/skip/move affordances
;; (Phase 8 §2/§4), split out of tabs/weekly.fnl (size rule).
;;
;; The card buttons mutate db.char.plan-edits through the PURE plan-edits
;; transforms (the options.fnl precedent: UI :set closures may write the DB
;; directly), then repaint via root.refresh!. The route re-reads the edits on
;; the next plan, so the reorder is the planner's own deterministic output --
;; the tab never shuffles cards by hand. Imperative AceGUI building only; the
;; skipped-row data shaping is the pure weekly-vm.skipped-view-model.

(local Routina (or _G.Routina {}))
(local acegui (or Routina.acegui (require :src.ui.acegui)))
(local vm (or Routina.tab-weekly-vm (require :src.ui.tabs.weekly-vm)))
(local plan-edits (or Routina.plan-edits (require :src.domain.plan-edits)))
(local activities (or Routina.activities (require :src.domain.activities)))
(local tomtom (or Routina.tomtom (require :src.core.tomtom)))

(local M {})

(fn apply-edit! [transform id]
  "Normalize the persisted edits, apply one pure transform, persist the fresh
   copy, and repaint."
  (let [char (?. Routina :addon :db :char)]
    (when char
      (let [next (transform (plan-edits.normalize char.plan-edits) id)]
        (set char.plan-edits (plan-edits.to-db next)))
      (when Routina.root (Routina.root.refresh!)))))

(fn add-action! [bar text width handler]
  "One small action button on a card's action bar."
  (let [btn (acegui.create! :Button)]
    (when btn
      (btn:SetText text)
      (btn:SetWidth width)
      (btn:SetCallback :OnClick handler)
      (bar:AddChild btn))
    btn))

(fn resolve-skip-name [ctx id]
  "Display name for a skipped activity id: the registry first, then the
   player's custom entries, else the raw id."
  (or (?. (activities.by-id id) :name)
      (accumulate [found nil _ adef (ipairs (or (?. ctx :custom-activities) []))
                   &until found]
        (when (= (tostring adef.id) (tostring id)) adef.name))
      (tostring id)))

(lambda M.build-actions! [card step pinned?]
  "Append the pin/skip/move action bar to one plan card (SimpleGroup in Flow
   layout): Pin or Unpin + ^ / v reorder while pinned, Skip, and -- only with
   TomTom loaded and a curated entrance for this activity -- a Map waypoint
   button (Phase 9; the affordance is HIDDEN without TomTom, never disabled).
   Domain:  card : an AceGUI container ; step : a plan step (has :id :name)
            pinned? : boolean -- the card view-model's :pinned?
   Returns: the bar widget | nil (headless)."
  (let [bar (acegui.create! :SimpleGroup)]
    (when bar
      (bar:SetFullWidth true)
      (bar:SetLayout :Flow)
      (if pinned?
          (do
            (add-action! bar :Unpin 80 #(apply-edit! plan-edits.unpin step.id))
            (add-action! bar "^" 44
                         #(apply-edit! (fn [e id] (plan-edits.move-pin e id -1))
                                       step.id))
            (add-action! bar :v 44
                         #(apply-edit! (fn [e id] (plan-edits.move-pin e id 1))
                                       step.id)))
          (add-action! bar :Pin 80 #(apply-edit! plan-edits.pin step.id)))
      (add-action! bar :Skip 80 #(apply-edit! plan-edits.skip step.id))
      (let [entrance (?. (activities.by-id step.id) :entrance)]
        (when (and (tomtom.available?) entrance)
          (add-action! bar :Map 60 #(tomtom.set-waypoint! entrance step.name))))
      (card:AddChild bar))
    bar))

(lambda M.build-skipped! [container ctx]
  "Append the skipped-activities tail card, one Restore button each. Quiet
   when nothing is skipped (the view-model is nil).
   Domain:  container : an AceGUI container ; ctx : RouteContext
   Returns: the card widget | nil."
  (let [skips (or (?. ctx :plan-edits :skips) {})
        rows (icollect [id v (pairs skips)]
               (when (= v true) {: id :name (resolve-skip-name ctx id)}))
        svm (vm.skipped-view-model rows)]
    (when svm
      (let [card (acegui.create! :InlineGroup)]
        (when card
          (card:SetTitle svm.headline)
          (card:SetFullWidth true)
          (card:SetLayout :List)
          (each [_ row (ipairs svm.rows)]
            (let [btn (acegui.create! :Button)]
              (when btn
                (btn:SetText row.label)
                (btn:SetWidth 240)
                (btn:SetCallback :OnClick
                                 #(apply-edit! plan-edits.unskip row.id))
                (card:AddChild btn))))
          (container:AddChild card))
        card))))

;; --- Register into the addon namespace ---------------------------------------

(set _G.Routina Routina)
(set Routina.tab-weekly-actions M)

M
