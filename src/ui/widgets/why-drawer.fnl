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

(lambda M.view-model [step ?ctx]
  "Pure explainer spec for one plan step (UI.md §6.6 inputs).
   Domain:  step : a route step {:name :id :score :attunement?
                   :items [{:label :slot :chance :runs} ...]}
            ?ctx : the RouteContext (for slot weights + competitors), optional
   Returns: {:title string
             :score-breakdown [{:label :slot :weight :chance :contribution} ...]
                              -- contribution desc (weight · chance)
             :weight-explanation string|nil
             :competition-note string|nil}"
  (let [rows (icollect [_ it (ipairs (or step.items []))]
               (let [w (weight-of ?ctx it.slot)]
                 {:label it.label
                  :slot it.slot
                  :weight w
                  :chance it.chance
                  :contribution (* w it.chance)}))
        weighted (icollect [_ r (ipairs rows)] (when (not= r.weight 1) r))
        competitors (competitors-of ?ctx step.id)]
    (table.sort rows by-contribution-desc)
    {:title (tostring step.name)
     :score-breakdown rows
     :weight-explanation (when (> (length weighted) 0)
                           (.. (length weighted)
                               " slot(s) weighted above default"))
     :competition-note (when (> competitors 1)
                         (.. "Drop chance split among " competitors
                             " in the loot pool"))}))

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

(fn build! []
  (let [f (acegui.create! :Frame)]
    (when f
      (f:SetLayout :List)
      (f:SetWidth drawer-width)
      (f:SetHeight 400)
      (f:SetStatusText "")
      (f:SetCallback :OnClose (fn [] (M.close!)))
      (acegui.tint-frame! f :parchment)
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

(lambda M.open! [parent step ?ctx]
  "Open (or re-open) the drawer for a plan step, popping up to the right of
   `parent` (the panel's WoW frame). Builds the singleton on first call. No-op
   headless (no AceGUI).
   Domain:  parent : WoW Frame (panel) | nil; step : a route step;
            ?ctx : RouteContext
   Returns: nil."
  (when (acegui.gui)
    (when (not frame) (build!))
    (when frame
      (frame:ReleaseChildren)
      (let [vm (M.view-model step ?ctx)]
        (frame:SetTitle vm.title)
        (add-header! "Score breakdown")
        (each [_ r (ipairs vm.score-breakdown)] (add-row! r))
        (add-notes! vm))
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
