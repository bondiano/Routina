;; chance-meter.fnl -- atomic probability bar (UI.md §6.3).
;;
;; A small custom CreateFrame widget -- the one sanctioned exception to the
;; AceGUI-only rule (CLAUDE.md UI conventions): AceGUI has no proportional
;; fill. Fixed 80x6 px so it does NOT depend on the card's deferred layout
;; width (that dependency is exactly why the meter was deferred from the
;; first AceGUI pass); a fixed-width bar anchored RIGHT resolves at draw time
;; regardless of DoLayout, so it composes cleanly inside an AceGUI row.
;;
;; UI.md split (mirrors example 08 + why-drawer): M.view-model is a PURE
;; data->spec (busted-tested); the pool + set! are the imperative shell.
;; Fill is a warm-to-cool gradient driven by p -- confidence, not pass/fail
;; (no green/red traffic light; colour-blind safe, UI.md §11). No OnUpdate:
;; the meter repaints only when a caller hands it a new spec (UI.md §13 bans
;; OnUpdate on anything but lockout-timer + why-drawer).

(local Routina (or _G.Routina {}))
(local CreateFrame _G.CreateFrame)
(local theme (or Routina.theme (require :src.ui.theme)))
(local format (or Routina.format (require :src.ui.format)))

(local M {})

;; --- Constants (named bindings, not magic numbers) -------------------------

(local meter-width 80)
(local meter-height 6)
(local track-alpha 0.3)
(local tick-alpha 0.5)
(local tick-fractions [0.25 0.5 0.75])

;; --- Pure view-model (UI.md: data->spec is pure, busted-tested) ------------

(fn gradient-tint [p]
  "Map p to a palette token. Warm-to-cool gradient: confidence, not pass/fail."
  (if (< p 0.25) theme.palette.warn
      (< p 0.5) theme.palette.gold
      (< p 0.75) theme.palette.gold-bright
      theme.palette.ok))

(lambda M.view-model [p ?hint]
  "Build a render-spec for a single probability.
   Domain:  p     : number in [0, 1]
            ?hint : string or nil (e.g. \"per run\", \"P50\")
   Returns: {:fill-fraction number :tint string(hex) :label string :hint string}
   Errors:  if p is outside [0, 1]."
  (assert (and (= (type p) :number) (>= p 0) (<= p 1)) "p out of range [0,1]")
  {:fill-fraction p
   :tint (gradient-tint p)
   :label (format.percent p)
   :hint (or ?hint "")})

;; --- Frame construction (private; one call per pool slot) ------------------
;;
;; WoW has no DestroyFrame, so released frames park on a hidden lot until
;; re-acquired. Built once, reused indefinitely.

(local pool [])
(local parking-lot (CreateFrame :Frame :RoutinaChanceMeterParkingLot
                                _G.UIParent))

(parking-lot:Hide)

(fn build-ticks [parent]
  "The 25 / 50 / 75 % tick marks over the track."
  (icollect [_ pct (ipairs tick-fractions)]
    (let [t (parent:CreateTexture nil :OVERLAY)]
      (t:SetSize 1 meter-height)
      (t:SetPoint :LEFT parent :LEFT (* meter-width pct) 0)
      (t:SetColorTexture (theme.rgba theme.palette.ink tick-alpha))
      t)))

(fn build-frame [parent]
  "Build one chance-meter: track texture + fill texture + tick marks."
  (let [f (CreateFrame :Frame nil parent)]
    (f:SetSize meter-width meter-height)
    (let [track (f:CreateTexture nil :BACKGROUND)]
      (track:SetAllPoints f)
      (track:SetColorTexture (theme.rgba theme.palette.ink-faint track-alpha))
      (set f.track track))
    (let [fill (f:CreateTexture nil :ARTWORK)]
      (fill:SetPoint :TOPLEFT f :TOPLEFT 0 0)
      (fill:SetPoint :BOTTOMLEFT f :BOTTOMLEFT 0 0)
      (set f.fill fill))
    (set f.ticks (build-ticks f))
    f))

;; --- Acquire / release -----------------------------------------------------

(lambda M.acquire! [parent]
  "Take a frame from the pool, or build one when empty. No-op (nil) headless
   (no CreateFrame).
   Domain:  parent : WoW Frame
   Returns: WoW Frame ready to position + populate | nil.
   See:     M.release!"
  (when CreateFrame
    (let [f (or (table.remove pool) (build-frame parent))]
      (f:SetParent parent)
      (f:ClearAllPoints)
      (f:Show)
      f)))

(lambda M.release! [f]
  "Return a frame to the pool. Caller must not touch it after release.
   Domain:  f : WoW Frame from M.acquire! | nil
   Returns: nil."
  (when f
    (f:Hide)
    (f:SetParent parking-lot)
    (f:ClearAllPoints)
    (table.insert pool f))
  nil)

;; --- Apply render-spec to a frame ------------------------------------------

(lambda M.set! [f spec]
  "Paint a render-spec onto a chance-meter frame. The label/hint live in the
   surrounding row (single-concern widget); the meter only draws the bar.
   Re-tints the pooled track + ticks too, so a frame re-acquired after a
   theme switch (Phase 5) never shows the previous palette.
   Domain:  f    : WoW Frame from M.acquire!
            spec : M.view-model result
   Returns: nil."
  (when (and f f.fill)
    (when f.track
      (f.track:SetColorTexture (theme.rgba theme.palette.ink-faint track-alpha)))
    (each [_ t (ipairs (or f.ticks []))]
      (t:SetColorTexture (theme.rgba theme.palette.ink tick-alpha)))
    ;; SetWidth needs a positive number; clamp so a 0% bar is invisible, not
    ;; an error.
    (f.fill:SetWidth (math.max 0.1 (* meter-width spec.fill-fraction)))
    (f.fill:SetHeight meter-height)
    (f.fill:SetColorTexture (theme.rgba spec.tint 1.0)))
  nil)

(lambda M.render! [f p ?hint]
  "Convenience: view-model + set! in one call.
   Domain:  f    : WoW Frame from M.acquire!
            p    : number in [0, 1]
            ?hint: string or nil
   Returns: nil."
  (M.set! f (M.view-model p ?hint)))

;; --- Register --------------------------------------------------------------

(set _G.Routina Routina)
(set Routina.chance-meter M)

M
