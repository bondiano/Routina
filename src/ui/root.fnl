;; root.fnl -- Routina main panel, built on AceGUI-3.0: a tinted Frame with a
;; four-tab TabGroup (Plan / Chains / Lockouts / BiS). Singleton (built once,
;; hidden on close, never released so toggling is cheap).
;;
;; The panel moved off the bespoke parchment/CreateFrame stack onto AceGUI so
;; layout and backdrop are the library's problem, not a pixel-tuning exercise.
;; State (active-tab), the singleton lifecycle, and the per-tab repaint stay
;; imperative -- see docs/UI.md §2.
;;
;; Tab modules expose a single `render! [container]` (idempotent: it
;; ReleaseChildren's the container and repopulates). TabGroup fires
;; OnGroupSelected, where we repaint the selected tab; refresh! repaints the
;; live Plan tab in place.

(local Routina (or _G.Routina {}))
(local acegui (or Routina.acegui (require :src.ui.acegui)))
(local tab-weekly (or Routina.tab-weekly (require :src.ui.tabs.weekly)))
(local tab-chains (or Routina.tab-chains (require :src.ui.tabs.chains)))
(local tab-lockouts (or Routina.tab-lockouts (require :src.ui.tabs.lockouts)))
(local tab-bis (or Routina.tab-bis (require :src.ui.tabs.bis)))
(local why-drawer (or Routina.why-drawer (require :src.ui.widgets.why-drawer)))
(local UnitName _G.UnitName)
(local UnitClass _G.UnitClass)

(local M {})

;; --- State (imperative singleton) ------------------------------------------

(var ui nil)

;; {:frame <AceGUI Frame> :tabs <AceGUI TabGroup>} once built

(var active-tab :weekly)

(local tabs-def [{:text :Plan :value :weekly}
                 {:text :Chains :value :chains}
                 {:text :Lockouts :value :lockouts}
                 {:text :BiS :value :bis}])

(local renderers {:weekly tab-weekly.render!
                  :chains tab-chains.render!
                  :lockouts tab-lockouts.render!
                  :bis tab-bis.render!})

;; --- Header text -----------------------------------------------------------

(fn player-display []
  ;; UnitName / UnitClass return localized values; spec (talent-based)
  ;; detection arrives with AceEvent. Guarded for headless.
  (let [name (or (and UnitName (UnitName :player)) :Player)
        class (or (and UnitClass (UnitClass :player)) :Adventurer)]
    (.. name " · " class)))

(fn status-text []
  ;; Placeholder reset window; a live countdown is a separate feature.
  "Week 47 · resets in 2d 4h")

;; --- Tab repaint -----------------------------------------------------------

(fn render-tab! [container key]
  "ReleaseChildren the TabGroup and repopulate it with `key`'s content."
  (when container
    (container:ReleaseChildren)
    (let [render (. renderers key)]
      (when render (render container)))))

(fn on-tab-selected [container _event key]
  (set active-tab key)
  (render-tab! container key))

;; --- Construction (lazy singleton) -----------------------------------------

(local escape-frame-name :RoutinaRootFrame)

(fn register-escape-close! [wow-frame]
  "Make Escape close the panel the WoW-idiomatic way: expose the underlying
   frame under a global name and add that name to UISpecialFrames (Blizzard then
   hides it on Escape). Also dismiss the why-drawer whenever the frame hides, so
   Escape and the X button behave identically. No-op headless / on a nil frame."
  (when (and wow-frame _G.UISpecialFrames)
    (tset _G escape-frame-name wow-frame)
    (var present? false)
    (each [_ n (ipairs _G.UISpecialFrames)]
      (when (= n escape-frame-name) (set present? true)))
    (when (not present?)
      (table.insert _G.UISpecialFrames escape-frame-name))
    (when wow-frame.HookScript
      (wow-frame:HookScript :OnHide (fn [] (why-drawer.close!)))))
  nil)

(fn build-ui! []
  "Build the AceGUI Frame + TabGroup once. Returns {:frame :tabs} or nil when
   AceGUI is unavailable (headless busted)."
  (when (acegui.gui)
    (let [frame (acegui.create! :Frame)
          tabs (acegui.create! :TabGroup)]
      (frame:SetTitle (player-display))
      (frame:SetStatusText (status-text))
      (frame:SetLayout :Fill)
      (frame:SetWidth 520)
      (frame:SetHeight 640)
      ;; Closing (X button) just hides the singleton and dismisses the drawer;
      ;; we never Release so re-show is instant.
      (frame:SetCallback :OnClose (fn [] (why-drawer.close!)))
      (acegui.tint-frame! frame)
      ;; ESC closes the panel like any WoW window: register the underlying frame
      ;; in UISpecialFrames (by global name) and dismiss the drawer when hidden.
      (register-escape-close! frame.frame)
      (tabs:SetLayout :Flow)
      (tabs:SetTabs tabs-def)
      (tabs:SetCallback :OnGroupSelected on-tab-selected)
      (frame:AddChild tabs)
      (tabs:SelectTab active-tab)
      {: frame : tabs})))

(fn ensure-ui! []
  (when (not ui) (set ui (build-ui!)))
  ui)

;; --- Public API (signatures preserved for core/events + slash commands) ----

(lambda M.show! []
  "Show the root panel, constructing it on first call. No-op headless.
   Returns: nil."
  (let [u (ensure-ui!)]
    (when u (u.frame:Show)))
  nil)

(lambda M.hide! []
  "Hide the root panel (and any open why-drawer) if already constructed.
   Returns: nil."
  (when ui (ui.frame:Hide))
  (why-drawer.close!)
  nil)

(lambda M.toggle! []
  "Toggle root panel visibility (constructs on first show).
   Returns: nil."
  (if (and ui (ui.frame:IsShown)) (M.hide!) (M.show!))
  nil)

(lambda M.show-tab! [key]
  "Select the named tab (TabGroup repaints it via OnGroupSelected).
   Domain:  key : one of :weekly :lockouts :bis
   Returns: nil."
  (assert (. renderers key) (.. "unknown tab key: " (tostring key)))
  (let [u (ensure-ui!)]
    (when u (u.tabs:SelectTab key)))
  nil)

(lambda M.show-why! [step ?ctx ?compare]
  "Open the why-drawer for a plan step, anchored to the right of the panel.
   Domain:  step : a route plan step; ?ctx : the RouteContext (weights/comp);
            ?compare : the next-best alternative step out-scored, or nil
   Returns: nil."
  (when ui (why-drawer.open! (and ui.frame ui.frame.frame) step ?ctx ?compare))
  nil)

(lambda M.refresh! []
  "Repaint the ACTIVE tab in place. No-op until the panel is built. Driven by
   src/core/events.fnl on gear / talent / lockout / quest / options changes
   and by the Phase 8 card/checklist actions, so whatever tab is open reflects
   current state (renders are idempotent ReleaseChildren-then-rebuild).
   Returns: nil."
  (when (and ui active-tab)
    (render-tab! ui.tabs active-tab))
  nil)

;; --- Register --------------------------------------------------------------

(set _G.Routina Routina)
(set Routina.root M)

M
