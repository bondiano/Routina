;; acegui.fnl -- thin, headless-safe facade over AceGUI-3.0 for Routina's
;; main panel. The ONE place that resolves AceGUI via LibStub and bridges
;; theme tokens (theme.fnl) into AceGUI's SetColor / SetFont / SetBackdropColor.
;;
;; Why a facade: every UI module would otherwise repeat the
;; `(and LibStub (LibStub :AceGUI-3.0 true))` guard (mirrors src/ui/options.fnl
;; for AceConfig). Centralising it keeps each tab a no-op under busted (no
;; AceGUI loaded) instead of throwing -- the same degrade-gracefully contract
;; options.fnl uses. No widget logic lives here; tabs compose these helpers.
;;
;; All method names verified against the vendored source in
;; Libs/Ace3/AceGUI-3.0/ (Create, GetWidgetVersion, Label:SetColor/:SetFont,
;; Frame.frame BackdropTemplate). See docs/UI.md §2.

(local Routina (or _G.Routina {}))
(local theme (or Routina.theme (require :src.ui.theme)))
(local LibStub _G.LibStub)

(local M {})

(lambda M.gui []
  "Resolve the AceGUI-3.0 library, or nil when it isn't loaded (headless
   busted runs). Callers treat nil as 'degrade to no-op'.
   Returns: the AceGUI-3.0 object | nil."
  (and LibStub (LibStub :AceGUI-3.0 true)))

(lambda M.registered? [kind]
  "True when widget type `kind` is registered with AceGUI. Lets callers fall
   back to a built-in widget when an optional lib (SFX-Widgets) is absent.
   Domain:  kind : widget type string (e.g. :SFX-Info :Frame)
   Returns: boolean."
  (let [gui (M.gui)]
    (if (and gui (gui:GetWidgetVersion kind)) true false)))

(lambda M.create! [kind]
  "AceGUI:Create(kind), guarded for headless. `kind` must be a registered
   type (built-ins always are once Ace3 is loaded).
   Domain:  kind : widget type string
   Returns: the new widget | nil when AceGUI is unavailable."
  (let [gui (M.gui)]
    (when gui (gui:Create kind))))

(lambda M.create-or! [kind fallback]
  "Create `kind` if it's registered, else `fallback`. For optional SFX widgets
   that may not be loaded.
   Domain:  kind fallback : widget type strings
   Returns: the new widget | nil when AceGUI is unavailable."
  (let [gui (M.gui)]
    (when gui
      (if (gui:GetWidgetVersion kind) (gui:Create kind) (gui:Create fallback)))))

(lambda M.release! [widget]
  "AceGUI:Release(widget), guarded. Returns the widget to its pool.
   Domain:  widget : an AceGUI widget | nil
   Returns: nil."
  (let [gui (M.gui)]
    (when (and gui widget) (gui:Release widget)))
  nil)

(lambda M.themed-label! [label ?color-token ?font-kind ?size-kind]
  "Apply theme colour + font tokens to an AceGUI Label / InteractiveLabel.
   No-op on nil (headless). Defaults: :ink colour, :body font, :body size.
   Domain:  label        : AceGUI Label-family widget | nil
            ?color-token : palette key, default :ink
            ?font-kind   : :title | :body, default :body
            ?size-kind   : :title :section :body :caption, default :body
   Returns: label."
  (when label
    (label:SetColor (theme.color (or ?color-token :ink)))
    (label:SetFont (. theme.fonts (or ?font-kind :body))
                   (. theme.sizes (or ?size-kind :body)) ""))
  label)

(lambda M.tint-frame! [widget ?color-token ?alpha]
  "Give an AceGUI Frame a solid, opaque themed fill. The default AceGUI dialog
   backdrop is largely see-through (the game world bleeds through an otherwise
   empty panel), so besides tinting the backdrop we lay a full-cover solid colour
   texture in the BACKGROUND layer (created once, RE-TINTED on every call --
   idempotent, so a theme switch just calls this again; Phase 5). No-op when
   the widget or its frame is absent.
   Domain:  widget       : AceGUI Frame widget (has .frame) | nil
            ?color-token : palette key, default :panel
            ?alpha       : number in [0, 1], default 0.96
   Returns: widget."
  (let [frame (and widget widget.frame)
        token (or ?color-token :panel)
        alpha (or ?alpha 0.96)]
    (when (and frame frame.SetBackdropColor)
      (frame:SetBackdropColor (theme.color token alpha)))
    (when (and frame frame.CreateTexture)
      (when (not frame.routina-bg)
        (let [bg (frame:CreateTexture nil :BACKGROUND)]
          (bg:SetAllPoints frame)
          (set frame.routina-bg bg)))
      (frame.routina-bg:SetColorTexture (theme.color token alpha))))
  widget)

;; --- Register --------------------------------------------------------------

(set _G.Routina Routina)
(set Routina.acegui M)

M
