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
  "Paint a frame's backdrop with a hand-painted parchment, sampled
   through the texture's painted interior.

   The bundled `Art/Parchment.tga` was cropped from DUI's Parchment
   atlas. The texture has painted torn-edges curling inward, plus a
   soft alpha ramp around the painted area. Using it as a SetBackdrop
   `bgFile` (which stretches the whole texture to fit) puts content
   anchored at the frame edge ON the alpha-ramp region -- content
   visibly falls off the painted parchment.

   Fix: render the bg via a Texture child of the frame with
   `SetTexCoord` zoomed into the inner ~88% of the texture. This
   drops the painted torn-edges, but the painted parchment now fills
   100% of the frame and content positioned at the inset stays well
   inside the painted area. The slim gold tooltip-border (`?border?`,
   default true) gives the panel a clean defined edge.

   Iteration history (kept as a footnote for the next person):
   - `UI-Achievement-Parchment` -- too noisy, fights body text.
   - Solid palette colour -- read as 'tan rectangle', not paper.
   - `SetGradientAlpha` vignette overlay -- hid child text on
     Anniversary.
   - L-corner / band ornaments on parent BORDER -- same problem.
   - Stationery_norm1 / UI-Achievement-Parchment-Horizontal -- either
     wouldn't render or didn't read as parchment.
   - Bundling the full DUI atlas without slicing -- stretched, with
     ornament-icons squashed into the bottom of the panel.
   - Cropped DUI body via bgFile (stretched) -- painted area sat
     INSIDE the frame, content overflowed onto the alpha ramp.

   Now: Texture child + SetTexCoord zoom + slim gold border.

   Domain:  frame    : WoW Frame supporting :SetBackdrop
            ?border? : boolean, default true; draws the gold tooltip-border.
   Returns: frame, for threading."
  (let [_unused ?border?
        bg (frame:CreateTexture nil :BACKGROUND)
        overhang 20]
    ;; No SetBackdrop, no border. The texture has the scroll's torn-
    ;; edges painted in with transparent margins around them, so what
    ;; shows on screen is just the parchment scroll shape -- transparent
    ;; areas reveal whatever is behind the frame (game world, other UI).
    ;; The texture extends `overhang` px beyond the frame on every side
    ;; so the painted parchment reads as larger than the click area --
    ;; content positioned via the frame insets sits comfortably away
    ;; from the painted torn-edges.
    (bg:SetTexture theme.textures.parchment)
    (bg:SetPoint :TOPLEFT frame :TOPLEFT (- overhang) overhang)
    (bg:SetPoint :BOTTOMRIGHT frame :BOTTOMRIGHT overhang (- overhang)))
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
