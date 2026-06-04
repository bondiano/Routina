;; tabs/lockouts.fnl -- Lockouts tab content: active raid lockouts as an
;; urgency-ordered card stack on AceGUI-3.0.
;;
;; END-TO-END SLICE: src/core/planner.fnl reads the live client into a route
;; input; its ctx.lockouts is a {activity-id LockoutView} map (built by
;; src/domain/ctx.fnl from wow.saved-instances). src/domain/lockouts.fnl derives
;; the per-lockout facts (time-until-reset, bosses-remaining, shareable?), and
;; this tab renders the active ones soonest-reset-first.
;;
;; UI.md split: the data->render-spec is PURE (M.lockout-view-model /
;; M.list-view-model, busted-tested); building the AceGUI widgets from it is
;; imperative. render! follows the tab contract in src/ui/root.fnl: idempotent
;; populate of the AceGUI container (the caller ReleaseChildren's it first).
;;
;; NOTE: the static reset line is computed once at render (ctx.now) as a
;; guaranteed-readable fallback; on top of it each card carries a LIVE
;; lockout-timer (src/ui/widgets/lockout-timer.fnl) anchored as a badge to the
;; card frame's top-right corner -- a ticking countdown + urgency bar that fills
;; over the last 24h with a one-shot gold pulse on crossing it. The timer is the
;; panel's one OnUpdate widget (throttled 1/4 Hz). It reads server time through
;; core/wow.now (injected as now-fn -- the widget itself touches no WoW API).
;; Timers are pooled; this tab releases the ones it started at the top of every
;; repaint (release! also stops the OnUpdate), same discipline as the Plan tab's
;; chance-meters.

(local Routina (or _G.Routina {}))
(local acegui (or Routina.acegui (require :src.ui.acegui)))
(local format (or Routina.format (require :src.ui.format)))
(local lockouts (or Routina.lockouts (require :src.domain.lockouts)))
(local activities (or Routina.activities (require :src.domain.activities)))
(local planner (or Routina.planner (require :src.core.planner)))
(local wow (or Routina.wow (require :src.core.wow)))
(local lockout-timer
       (or Routina.lockout-timer (require :src.ui.widgets.lockout-timer)))

(local M {})

;; --- Layout constants ------------------------------------------------------

;; Reset within a day flags the lockout as urgent (warn-coloured). Raids reset
;; weekly, so this only fires in the final stretch before the weekly reset.
(local urgent-window 86400)

;; Inset of the live-timer badge from the card frame's top-right corner.
(local badge-x -12)
(local badge-y -8)

;; Live timers acquired during the current paint, drained on the next one.
(var live-timers [])

(fn release-timers! []
  "Stop and pool every timer from the last paint. Called at the top of render!
   before AceGUI rebuilds the cards the timers were anchored to."
  (each [_ t (ipairs live-timers)] (lockout-timer.release! t))
  (set live-timers []))

;; --- Pure view-model (UI.md: data->spec is pure, busted-tested) ------------

(fn boss-word [n]
  (if (= n 1) " boss" " bosses"))

(lambda M.lockout-view-model [lockout name now]
  "Pure render spec for one lockout row.
   Domain:  lockout : LockoutView (schemas.LockoutView)
            name    : string -- human-readable instance name
            now     : integer -- current server time in seconds
   Returns: {:title string :progress string :status string :reset-text string
             :reset-at integer :urgent? boolean :shareable? boolean}
   Errors:  if the LockoutView shape is invalid, or now is not a number."
  (let [killed lockout.bosses-killed
        total lockout.bosses-total
        remaining (lockouts.bosses-remaining lockout)
        secs (lockouts.time-until-reset lockout now)]
    {:title (tostring name)
     :progress (.. killed "/" total " bosses cleared")
     :status (if (= remaining 0) "Fully cleared"
                 (.. remaining (boss-word remaining) " remaining"))
     :reset-text (.. "Resets in " (format.duration-short secs))
     :reset-at lockout.expiry
     :urgent? (< secs urgent-window)
     :shareable? (lockouts.lockout-shareable? lockout now)}))

(fn by-urgency [a b]
  "Soonest reset first; ties broken by title so the order is deterministic."
  (if (= a.secs b.secs) (< a.title b.title) (< a.secs b.secs)))

(lambda M.list-view-model [lockouts-by-id name-of now]
  "Active lockouts as urgency-ordered view-models (soonest reset first).
   Already-reset lockouts are dropped -- they no longer bind.
   Domain:  lockouts-by-id : {activity-id LockoutView} (ctx.lockouts)
            name-of        : (fn [activity-id] -> string|nil) -- display name;
                             nil falls back to the id
            now            : integer -- current server time in seconds
   Returns: [view-model ...] -- M.lockout-view-model results, urgency-ordered
   Errors:  if any LockoutView shape is invalid, or now is not a number."
  (let [rows (icollect [id lockout (pairs lockouts-by-id)]
               (when (lockouts.lockout-active? lockout now)
                 {:secs (lockouts.time-until-reset lockout now)
                  :title (tostring (or (name-of id) id))
                  :vm (M.lockout-view-model lockout (or (name-of id) id) now)}))]
    (table.sort rows by-urgency)
    (icollect [_ r (ipairs rows)] r.vm)))

;; --- Card (AceGUI InlineGroup) ---------------------------------------------

(fn add-line! [card text ?color ?size]
  "Append one themed, full-width label line to a card."
  (let [label (acegui.create! :Label)]
    (when label
      (label:SetText text)
      (label:SetFullWidth true)
      (acegui.themed-label! label (or ?color :ink) :body (or ?size :body))
      (card:AddChild label))))

(fn attach-timer! [card vm]
  "Anchor a live lockout-timer badge to the card frame's top-right corner and
   remember it for the next release-timers! sweep. The static reset line stays
   as the readable fallback (UI.md §11); the badge adds the live tick + urgency
   bar + 24h pulse."
  (when (and card card.frame vm.reset-at)
    (let [timer (lockout-timer.acquire! card.frame)]
      (when timer
        (timer:ClearAllPoints)
        (timer:SetPoint :TOPRIGHT card.frame :TOPRIGHT badge-x badge-y)
        (lockout-timer.start! timer vm.reset-at wow.now)
        (table.insert live-timers timer)))))

(fn build-card! [vm]
  "Build one lockout card as an InlineGroup from a pure view-model, with a live
   countdown badge anchored to its corner."
  (let [card (acegui.create! :InlineGroup)]
    (when card
      (card:SetTitle vm.title)
      (card:SetFullWidth true)
      (card:SetLayout :List)
      (add-line! card vm.progress :ink :body)
      (add-line! card vm.status :ink-faint :caption)
      (add-line! card vm.reset-text (if vm.urgent? :warn :ink-faint) :caption)
      (when vm.shareable?
        (add-line! card "Shareable -- can extend to group" :gold :caption))
      (attach-timer! card vm))
    card))

;; --- Public API ------------------------------------------------------------

(fn name-of [id]
  "Human-readable instance name for an activity id, or nil to fall back."
  (let [activity (activities.by-id id)]
    (and activity activity.name)))

(fn add-empty! [container message]
  (let [label (acegui.create! :Label)]
    (when label
      (label:SetText message)
      (label:SetFullWidth true)
      (acegui.themed-label! label :ink-faint :body :body)
      (container:AddChild label))))

(lambda M.render! [container]
  "Repaint the Lockouts tab into an AceGUI container (the TabGroup). Reads the
   live client's saved instances and adds a ScrollFrame of urgency-ordered
   lockout cards. Idempotent -- the caller (src/ui/root.fnl) ReleaseChildren's
   the container first. No-op headless (no AceGUI).
   Domain:  container : an AceGUI container widget
   Returns: nil."
  (release-timers!)
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
            vms (if ctx (M.list-view-model ctx.lockouts name-of ctx.now) [])
            n (length vms)]
        (if (= 0 n)
            (add-empty! scroll
                        (if ok?
                            "No active raid lockouts -- every instance is fresh."
                            "Log in to a character to see your lockouts."))
            (each [_ vm (ipairs vms)]
              (let [card (build-card! vm)]
                (when card (scroll:AddChild card))))))))
  nil)

(set _G.Routina Routina)
(set Routina.tab-lockouts M)

M
