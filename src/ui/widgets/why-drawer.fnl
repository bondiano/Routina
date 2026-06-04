;; why-drawer.fnl -- the "Why is this here?" explainer (UI.md §6.6), on AceGUI.
;;
;; A singleton AceGUI Frame that pops up to the right of the main panel and
;; lists the score breakdown as SFX-Info rows (label -> "×weight · chance%"),
;; falling back to plain Labels when SFX-Widgets isn't loaded.
;;
;; UI.md split: M.view-model is a PURE explainer spec (busted-tested); the
;; singleton frame and open!/close! are imperative shell.
;;
;; NOTE: the old slide-in animation is gone -- the drawer now pops (AceGUI
;; frames don't tween). If the slide is wanted back it returns as a small
;; custom touch, not by fighting AceGUI's layout.

(local Routina (or _G.Routina {}))
(local acegui (or Routina.acegui (require :src.ui.acegui)))
(local format (or Routina.format (require :src.ui.format)))

(local M {})

;; --- Constants -------------------------------------------------------------

(local drawer-width 280)

;; --- Pure view-model (UI.md: data->spec is pure, busted-tested) ------------

(fn weight-of [ctx slot]
  (or (and ctx ctx.weights slot (. ctx.weights slot)) 1))

(fn competitors-of [ctx id]
  (or (and ctx ctx.competitors id (. ctx.competitors id))
      (and ctx ctx.default-competitors) 1))

(fn by-contribution-desc [a b]
  (> a.contribution b.contribution))

(fn breakdown [step ?ctx]
  "Per-item score rows for a step, contribution desc (weight · chance)."
  (let [rows (icollect [_ it (ipairs (or step.items []))]
               (let [w (weight-of ?ctx it.slot)]
                 {:label it.label
                  :slot it.slot
                  :weight w
                  :chance it.chance
                  :contribution (* w it.chance)}))]
    (table.sort rows by-contribution-desc)
    rows))

(fn diff-of [step compare rows]
  "Pure 'why this step out-scores the next alternative' spec, or nil without a
   comparison step. `rows` is step's contribution-sorted breakdown.
   Returns: {:vs string :delta number :leads? boolean
             :top-items [{:label :contribution} ...<=3] :reasons [string ...]}"
  (when compare
    (let [delta (- (or step.score 0) (or compare.score 0))
          top (fcollect [i 1 (math.min 3 (length rows))]
                (let [r (. rows i)]
                  {:label r.label :contribution r.contribution}))
          weighted-top (accumulate [found nil _ r (ipairs rows)]
                         (or found (and (> r.weight 1) r)))
          reasons [(.. "Scores " (format.score-short (or step.score 0)) " vs "
                       (format.score-short (or compare.score 0)) " ("
                       (if (>= delta 0) "+" "") (format.score-short delta)
                       " expected upgrades)")]]
      (when (> (length rows) 0)
        (let [t (. rows 1)]
          (table.insert reasons
                        (.. "Most of the edge: " t.label " ("
                            (format.percent t.chance) " this week)"))))
      (when weighted-top
        (table.insert reasons
                      (.. (tostring weighted-top.slot) " is weighted ×"
                          weighted-top.weight)))
      (when (and step.minutes compare.minutes (< step.minutes compare.minutes))
        (table.insert reasons (.. "~" (- compare.minutes step.minutes)
                                  " min shorter")))
      {:vs (tostring compare.name)
       : delta
       :leads? (>= delta 0)
       :top-items top
       : reasons})))

(lambda M.view-model [step ?ctx ?compare]
  "Pure explainer spec for one plan step (UI.md §6.6 inputs), optionally diffed
   against the next-best alternative it out-scores (ROADMAP Phase 4 §4).
   Domain:  step : a route step {:name :id :score :minutes? :attunement?
                   :items [{:label :slot :chance :runs} ...]}
            ?ctx : the RouteContext (for slot weights + competitors), optional
            ?compare : the alternative step this one out-scores, or nil
   Returns: {:title string
             :score-breakdown [{:label :slot :weight :chance :contribution} ...]
                              -- contribution desc (weight · chance)
             :weight-explanation string|nil
             :competition-note string|nil
             :diff {:vs :delta :leads? :top-items :reasons} | nil}"
  (let [rows (breakdown step ?ctx)
        weighted (icollect [_ r (ipairs rows)] (when (not= r.weight 1) r))
        competitors (competitors-of ?ctx step.id)]
    {:title (tostring step.name)
     :score-breakdown rows
     :weight-explanation (when (> (length weighted) 0)
                           (.. (length weighted)
                               " slot(s) weighted above default"))
     :competition-note (when (> competitors 1)
                         (.. "Drop chance split among " competitors
                             " in the loot pool"))
     :diff (diff-of step ?compare rows)}))

;; --- Singleton frame (imperative; built once, repopulated per open) --------

(var frame nil)

(fn row-line [r]
  (.. r.label "   ×" r.weight "   " (format.percent r.chance)))

(fn row-value [r]
  (.. "×" r.weight "  ·  " (format.percent r.chance)))

(fn add-row! [r]
  "Add one breakdown row: an SFX-Info (label -> value) when available, else a
   plain themed Label."
  (if (acegui.registered? :SFX-Info)
      (let [info (acegui.create! :SFX-Info)]
        (when info
          (info:SetLabel r.label)
          (info:SetText (row-value r))
          (info:SetFullWidth true)
          (frame:AddChild info)))
      (let [lbl (acegui.create! :Label)]
        (when lbl
          (lbl:SetText (row-line r))
          (lbl:SetFullWidth true)
          (acegui.themed-label! lbl :ink :body :body)
          (frame:AddChild lbl)))))

(fn add-header! [text]
  (if (acegui.registered? :SFX-Header)
      (let [h (acegui.create! :SFX-Header)]
        (when h (h:SetText text) (h:SetFullWidth true) (frame:AddChild h)))
      (let [h (acegui.create! :Heading)]
        (when h (h:SetText text) (h:SetFullWidth true) (frame:AddChild h)))))

(fn add-notes! [vm]
  (let [both (if (and vm.weight-explanation vm.competition-note)
                 (.. vm.weight-explanation " · " vm.competition-note)
                 (or vm.weight-explanation vm.competition-note))]
    (when both
      (let [lbl (acegui.create! :Label)]
        (when lbl
          (lbl:SetText both)
          (lbl:SetFullWidth true)
          (acegui.themed-label! lbl :ink-faint :body :caption)
          (frame:AddChild lbl))))))

(fn add-diff! [vm]
  "Render the recommendation-diff section: a header naming the beaten alternative
   and one themed Label per reason. No-op when there's no comparison."
  (when vm.diff
    (add-header! (.. "Why over " vm.diff.vs))
    (each [_ reason (ipairs vm.diff.reasons)]
      (let [lbl (acegui.create! :Label)]
        (when lbl
          (lbl:SetText (.. "• " reason))
          (lbl:SetFullWidth true)
          (acegui.themed-label! lbl :ink :body :body)
          (frame:AddChild lbl))))))

(fn build! []
  (let [f (acegui.create! :Frame)]
    (when f
      (f:SetLayout :List)
      (f:SetWidth drawer-width)
      (f:SetHeight 400)
      (f:SetStatusText "")
      (f:SetCallback :OnClose (fn [] (M.close!)))
      (acegui.tint-frame! f)
      (set frame f))
    f))

(fn position! [parent]
  "Pin the drawer to the right edge of the panel (parent WoW frame), or centre
   it when there's no parent."
  (when (and frame frame.frame)
    (let [wf frame.frame]
      (wf:ClearAllPoints)
      (if parent
          (wf:SetPoint :TOPLEFT parent :TOPRIGHT 8 0)
          (wf:SetPoint :CENTER _G.UIParent :CENTER 0 0)))))

;; --- Public API ------------------------------------------------------------

(lambda M.open! [parent step ?ctx ?compare]
  "Open (or re-open) the drawer for a plan step, popping up to the right of
   `parent` (the panel's WoW frame). Builds the singleton on first call. No-op
   headless (no AceGUI).
   Domain:  parent : WoW Frame (panel) | nil; step : a route step;
            ?ctx : RouteContext; ?compare : the alternative step out-scored, or nil
   Returns: nil."
  (when (acegui.gui)
    (when (not frame) (build!))
    (when frame
      (frame:ReleaseChildren)
      (let [vm (M.view-model step ?ctx ?compare)]
        (frame:SetTitle vm.title)
        (add-header! "Score breakdown")
        (each [_ r (ipairs vm.score-breakdown)] (add-row! r))
        (add-notes! vm)
        (add-diff! vm))
      (frame:Show)
      (position! parent)))
  nil)

(lambda M.close! []
  "Hide the drawer if it exists (kept as a singleton, never released).
   Returns: nil."
  (when frame (frame:Hide))
  nil)

;; --- Register --------------------------------------------------------------

(set _G.Routina Routina)
(set Routina.why-drawer M)

M
