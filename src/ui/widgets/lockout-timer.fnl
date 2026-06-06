;; lockout-timer.fnl -- live "time until reset" countdown (UI.md §6.4).
;;
;; The panel's ONE OnUpdate widget (UI.md §13), and a sanctioned custom
;; CreateFrame: AceGUI has no ticking countdown. Throttled hard -- 1 Hz idle,
;; 4 Hz under the final minute -- because a planner ticking at 60 Hz is wasteful
;; and shows up in profilers (UI.md §10).
;;
;; UI.md split: M.view-model is a PURE data->spec (busted-tested); the pool,
;; set!, and the throttled OnUpdate driver are the imperative shell. The widget
;; never reads a clock itself -- start! takes a `now-fn` the caller injects
;; (the tab passes core/wow.now), keeping the widget free of WoW-time coupling
;; (§13: a widget touches no WoW API beyond CreateFrame + frame methods) and the
;; view-model deterministic.
;;
;; Urgency reads over the last 24h: the bar fills as reset approaches and the
;; tint shifts ink-faint -> gold -> warn. A single gold pulse fires once when a
;; live tick crosses into the 24h window (not on first paint). No sound, no flash
;; (UI.md §1).

(local Routina (or _G.Routina {}))
(local CreateFrame _G.CreateFrame)
(local theme (or Routina.theme (require :src.ui.theme)))
(local format (or Routina.format (require :src.ui.format)))

(local M {})

;; --- Constants (named bindings, not magic numbers) -------------------------

(local urgency-window 86400)

; last 24h: bar fills, tint warms
(local urgency-half 43200)

; 12h: gold -> warn handoff
(local fast-threshold 60)

; under a minute -> 4 Hz
(local idle-interval 1.0)

; 1 Hz idle tick
(local fast-interval 0.25)

; 4 Hz final-minute tick
(local pulse-duration (/ theme.motion.fade-ms 1000))

; gold pulse fade (seconds)

(local frame-width 140)
(local frame-height 24)
(local bar-width 120)
(local bar-height 4)
(local track-alpha 0.3)
(local pulse-alpha 0.8)

;; --- Pure view-model (UI.md: data->spec is pure, busted-tested) ------------

(fn band-of [secs]
  "Urgency band from seconds-until-reset: calm (>24h), soon (12-24h),
   urgent (<12h)."
  (if (>= secs urgency-window) :calm
      (>= secs urgency-half) :soon
      :urgent))

(fn tint-of [urgency-band]
  "Palette token for an urgency band (ink-faint -> gold -> warn)."
  (case urgency-band
    :calm theme.palette.ink-faint
    :soon theme.palette.gold
    _ theme.palette.warn))

(lambda M.view-model [reset-at now ?label]
  "Pure render-spec for a lockout countdown.
   Domain:  reset-at : integer -- server-time seconds the lockout ID resets
            now      : integer -- current server time in seconds
            ?label   : string or nil -- prefix (e.g. \"Resets in\")
   Returns: {:secs integer>=0 :fill-fraction number[0,1] :tint string(hex)
             :band :calm|:soon|:urgent :label string :reset-text string
             :expired? boolean}
   Errors:  if reset-at or now is not a number."
  (assert (= (type reset-at) :number) "reset-at must be a number")
  (assert (= (type now) :number) "now must be a number")
  (let [secs (math.max 0 (- reset-at now))
        urgency-band (band-of secs)
        ;; empty until inside the 24h window, then fills 0 -> 1 as secs -> 0
        fill (math.max 0 (math.min 1 (- 1 (/ secs urgency-window))))]
    {: secs
     :fill-fraction fill
     :tint (tint-of urgency-band)
     :band urgency-band
     :label (or ?label "")
     :reset-text (format.duration-short secs)
     :expired? (<= secs 0)}))

;; --- Frame construction (private; one call per pool slot) ------------------

(local pool [])
(local parking-lot (CreateFrame :Frame :RoutinaLockoutTimerParkingLot
                                _G.UIParent))

(parking-lot:Hide)

(fn build-frame [parent]
  "Build one lockout-timer: serif countdown line + urgency bar (track/fill) +
   a gold pulse overlay."
  (let [f (CreateFrame :Frame nil parent)]
    (f:SetSize frame-width frame-height)
    (let [text (f:CreateFontString nil :OVERLAY)]
      (text:SetFont theme.fonts.title theme.sizes.body "")
      (text:SetPoint :TOPLEFT f :TOPLEFT 0 0)
      (set f.text text))
    (let [track (f:CreateTexture nil :BACKGROUND)]
      (track:SetSize bar-width bar-height)
      (track:SetPoint :BOTTOMLEFT f :BOTTOMLEFT 0 0)
      (track:SetColorTexture (theme.rgba theme.palette.ink-faint track-alpha))
      (set f.track track))
    (let [fill (f:CreateTexture nil :ARTWORK)]
      (fill:SetPoint :TOPLEFT f.track :TOPLEFT 0 0)
      (fill:SetPoint :BOTTOMLEFT f.track :BOTTOMLEFT 0 0)
      (set f.fill fill))
    (let [pulse (f:CreateTexture nil :OVERLAY)]
      (pulse:SetAllPoints f.track)
      (pulse:SetColorTexture (theme.rgba theme.palette.gold-bright 1.0))
      (pulse:SetAlpha 0)
      (pulse:Hide)
      (set f.pulse pulse))
    f))

;; --- Pulse (imperative; self-disabling fade) -------------------------------

(fn start-pulse! [f]
  "Begin the single gold pulse (alpha fades over pulse-duration)."
  (set f.pulse-remaining pulse-duration)
  (when f.pulse
    (f.pulse:SetAlpha pulse-alpha)
    (f.pulse:Show)))

(fn step-pulse! [f dt]
  "Advance the pulse fade by dt; hide once it has run out."
  (when (and f.pulse-remaining (> f.pulse-remaining 0))
    (set f.pulse-remaining (- f.pulse-remaining dt))
    (let [a (math.max 0 (* pulse-alpha (/ f.pulse-remaining pulse-duration)))]
      (when f.pulse (f.pulse:SetAlpha a))
      (when (<= f.pulse-remaining 0)
        (when f.pulse (f.pulse:Hide))
        (set f.pulse-remaining 0)))))

;; --- Apply render-spec to a frame ------------------------------------------

(lambda M.set! [f spec]
  "Paint a render-spec onto a timer frame. Detects a live calm->soon crossing
   (entering the 24h window) and fires the one-shot gold pulse; first paint
   (no prior band) never pulses.
   Domain:  f    : WoW Frame from M.acquire!
            spec : M.view-model result
   Returns: nil."
  (when f
    (when f.text
      (let [line (if (= spec.label "") spec.reset-text
                     (.. spec.label " " spec.reset-text))]
        (f.text:SetText line)
        (f.text:SetTextColor (theme.rgba spec.tint 1.0))))
    (when f.fill
      (f.fill:SetWidth (math.max 0.1 (* bar-width spec.fill-fraction)))
      (f.fill:SetHeight bar-height)
      (f.fill:SetColorTexture (theme.rgba spec.tint 1.0)))
    ;; calm -> soon == crossing into the 24h window on a live tick.
    (when (and f.last-band (= f.last-band :calm) (= spec.band :soon))
      (start-pulse! f))
    (set f.last-band spec.band))
  nil)

;; --- Throttled OnUpdate driver (imperative shell) --------------------------

(fn tick-interval [f]
  "Throttle: 4 Hz in the final minute, 1 Hz otherwise."
  (if (and f.last-secs (< f.last-secs fast-threshold)) fast-interval
      idle-interval))

(fn make-on-update [now-fn]
  "OnUpdate handler closure. Accumulates dt and recomputes on the throttle
   boundary; advances the pulse fade every frame so it stays smooth."
  (fn [self dt]
    (step-pulse! self dt)
    (set self.acc (+ (or self.acc 0) dt))
    (when (>= self.acc (tick-interval self))
      (set self.acc 0)
      (let [spec (M.view-model self.reset-at (now-fn) self.label)]
        (set self.last-secs spec.secs)
        (M.set! self spec)
        ;; Reset done -- stop ticking; the tab re-renders on the lockout event.
        (when spec.expired? (M.stop! self))))))

;; --- Acquire / start / stop / release --------------------------------------

(lambda M.acquire! [parent]
  "Take a frame from the pool, or build one when empty. No-op (nil) headless.
   Domain:  parent : WoW Frame
   Returns: WoW Frame ready to position + start | nil.
   See:     M.start! M.release!"
  (when CreateFrame
    (let [f (or (table.remove pool) (build-frame parent))]
      (f:SetParent parent)
      (f:ClearAllPoints)
      (f:Show)
      f)))

(lambda M.start! [f reset-at now-fn ?label]
  "Begin the live countdown: paint once, then wire the throttled OnUpdate.
   `now-fn` is a 0-arg fn returning server-time seconds (the tab injects
   core/wow.now). No-op on nil.
   Domain:  f        : WoW Frame from M.acquire!
            reset-at : integer -- server-time seconds of reset
            now-fn   : (fn [] -> integer)
            ?label   : string or nil
   Returns: nil."
  (when f
    (set f.reset-at reset-at)
    (set f.label (or ?label ""))
    (set f.acc 0)
    (set f.last-band nil)
    ;; re-tint the pooled static textures: a frame re-acquired after a theme
    ;; switch (Phase 5) must follow the active palette
    (when f.track
      (f.track:SetColorTexture (theme.rgba theme.palette.ink-faint track-alpha)))
    (when f.pulse
      (f.pulse:SetColorTexture (theme.rgba theme.palette.gold-bright 1.0)))
    (let [spec (M.view-model reset-at (now-fn) f.label)]
      (set f.last-secs spec.secs)
      (M.set! f spec)
      (when (not spec.expired?)
        (f:SetScript :OnUpdate (make-on-update now-fn)))))
  nil)

(lambda M.stop! [f]
  "Stop the OnUpdate tick (the countdown freezes; pulse, if mid-fade, ends).
   Domain:  f : WoW Frame from M.acquire! | nil
   Returns: nil."
  (when f
    (f:SetScript :OnUpdate nil)
    (set f.pulse-remaining 0)
    (when f.pulse (f.pulse:Hide)))
  nil)

(lambda M.release! [f]
  "Stop the timer and return its frame to the pool. Caller must not touch it
   after release.
   Domain:  f : WoW Frame from M.acquire! | nil
   Returns: nil."
  (when f
    (M.stop! f)
    (f:Hide)
    (f:SetParent parking-lot)
    (f:ClearAllPoints)
    (table.insert pool f))
  nil)

;; --- Register --------------------------------------------------------------

(set _G.Routina Routina)
(set Routina.lockout-timer M)

M
