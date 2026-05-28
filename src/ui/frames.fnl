;; frames.fnl -- private CreateFrame helpers shared by root, tabs, widgets.
;;
;; Reads theme tokens via _G.Routina.theme. No widget logic; widgets and
;; tabs compose these. WoW API surface limited to SetBackdrop /
;; SetBackdropColor / CreateFontString. No event handling, no OnUpdate.
;; See docs/UI.md §5.

(local Routina (or _G.Routina {}))
(local theme (or Routina.theme (require :src.ui.theme)))

(local M {})

(lambda M.apply-parchment-backdrop! [frame ?border?]
  "Paint a frame's backdrop with uniform aged-parchment tone and an
   optional gold edge.

   The earlier `UI-Achievement-Parchment` texture was too noisy for body
   text and made nested panels look ruptured. A solid warm tan gives the
   Dialogue-UI \"aged page\" feel without competing with the typography.

   A previous revision added an overlay-Texture gradient via
   `SetGradientAlpha` for a vignette. On the TBC Classic Anniversary
   client that overlay rendered as a solid quad on top of child frames,
   hiding the text. Removed; if a vignette is wanted later, do it via two
   stacked half-frame textures with slightly different alphas (no
   gradient API).

   Domain:  frame    : WoW Frame supporting :SetBackdrop
            ?border? : boolean, default true; draws the gold tooltip-border.
   Returns: frame, for threading."
  (let [show-border? (not= ?border? false)]
    (frame:SetBackdrop {:bgFile theme.textures.solid
                        :edgeFile (when show-border? theme.textures.gold-border)
                        :edgeSize 14
                        :tile false
                        :insets {:left 4 :right 4 :top 4 :bottom 4}})
    (frame:SetBackdropColor (theme.rgba theme.palette.parchment 1))
    (when show-border?
      (frame:SetBackdropBorderColor (theme.rgba theme.palette.gold 1))))
  frame)

(fn make-stripe! [frame layer color-token alpha]
  ;; Helper: 1-channel solid-color texture for ornaments. Stays on the
  ;; given layer; caller anchors it. No gradient API -- the previous
  ;; vignette attempt rendered as a solid quad on TBC Classic
  ;; Anniversary and hid the text in child frames.
  (let [t (frame:CreateTexture nil layer)]
    (t:SetColorTexture (theme.rgba (. theme.palette color-token) alpha))
    t))

(fn corner-stripes! [frame anchor dx dy len thick]
  ;; L-shaped gold corner: horizontal stripe + vertical stripe both
  ;; anchored at the corner. SetPoint with a single anchor + SetSize
  ;; makes the texture extend AWAY from the anchor into the frame, so
  ;; the same code works for all four corners by only swapping the
  ;; anchor.
  (let [h (make-stripe! frame :BORDER :gold 0.85)
        v (make-stripe! frame :BORDER :gold 0.85)]
    (h:SetPoint anchor frame anchor dx dy)
    (h:SetSize len thick)
    (v:SetPoint anchor frame anchor dx dy)
    (v:SetSize thick len)))

(lambda M.apply-page-ornaments! [frame ?separator-y]
  "Add aged-page ornaments: thin darker edge bands at the top and
   bottom, a 1-px ink separator under the header, and L-shaped gold
   corner accents. None of the placements overlap header/content text
   regions, so the ornaments are safe regardless of how Anniversary
   resolves layer ordering against child frames.

   Domain:  frame        : WoW Frame with parchment backdrop already applied.
            ?separator-y : optional y-offset from the top for the header
                           separator (negative number; default -66, the
                           gap between header bottom and pill row top).
   Returns: frame."
  ;; Top edge band: 6 px tall, alpha 0.10. Sits at y=-6..-12 from top,
  ;; well above header text which starts at y=-16 (inset).
  (let [top (make-stripe! frame :BORDER :shadow 0.1)]
    (top:SetPoint :TOPLEFT frame :TOPLEFT 6 -6)
    (top:SetPoint :TOPRIGHT frame :TOPRIGHT -6 -6)
    (top:SetHeight 6))
  ;; Bottom edge band: 6 px tall, alpha 0.15 (slightly darker, "page
  ;; weight"). Sits at the bottom edge, outside the content area's
  ;; populated region.
  (let [bot (make-stripe! frame :BORDER :shadow 0.15)]
    (bot:SetPoint :BOTTOMLEFT frame :BOTTOMLEFT 6 6)
    (bot:SetPoint :BOTTOMRIGHT frame :BOTTOMRIGHT -6 6)
    (bot:SetHeight 6))
  ;; Header separator: 1-px ink line in the gap between the header
  ;; (ends ~y=-64) and the pill row (starts at y=-72). Default y=-66
  ;; lands cleanly between them.
  (let [sep (make-stripe! frame :BORDER :ink 0.3)
        inset theme.spacing.inset
        y (or ?separator-y -66)]
    (sep:SetPoint :TOPLEFT frame :TOPLEFT inset y)
    (sep:SetPoint :TOPRIGHT frame :TOPRIGHT (- inset) y)
    (sep:SetHeight 1))
  ;; Four L-shaped gold corners (vintage frame feel). Stripe length 14,
  ;; thickness 1, inset 8 from each edge -- well clear of every text
  ;; region.
  (let [in 8
        len 14
        thick 1]
    (corner-stripes! frame :TOPLEFT in (- in) len thick)
    (corner-stripes! frame :TOPRIGHT (- in) (- in) len thick)
    (corner-stripes! frame :BOTTOMLEFT in in len thick)
    (corner-stripes! frame :BOTTOMRIGHT (- in) in len thick))
  frame)

(lambda M.apply-inset-backdrop! [frame token]
  "Paint a frame with a solid token-coloured backdrop, no border.
   Domain:  frame : WoW Frame supporting :SetBackdrop
            token : string keyword, key of theme.palette
   Returns: frame."
  (let [hex (. theme.palette token)]
    (assert hex (.. "unknown palette token: " (tostring token)))
    (frame:SetBackdrop {:bgFile theme.textures.solid})
    (frame:SetBackdropColor (theme.rgba hex 1)))
  frame)

(lambda M.make-font-string! [parent layer font-kind size-kind ?color-token]
  "Create a font string on parent with theme tokens.
   Domain:  parent       : WoW Frame
            layer        : string draw layer (:ARTWORK :OVERLAY :BACKGROUND)
            font-kind    : :title or :body
            size-kind    : :title :section :body :caption
            ?color-token : palette key, default :ink
   Returns: WoW FontString."
  (let [font (. theme.fonts font-kind)
        size (. theme.sizes size-kind)
        token (or ?color-token :ink)
        hex (. theme.palette token)]
    (assert font (.. "unknown font-kind: " (tostring font-kind)))
    (assert size (.. "unknown size-kind: " (tostring size-kind)))
    (assert hex (.. "unknown color-token: " (tostring token)))
    (let [fs (parent:CreateFontString nil layer)]
      (fs:SetFont font size "")
      (fs:SetTextColor (theme.rgba hex 1))
      fs)))

;; --- Register --------------------------------------------------------------

(set _G.Routina Routina)
(set Routina.frames M)

M
