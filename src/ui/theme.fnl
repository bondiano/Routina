;; theme.fnl -- pure visual tokens for Routina's UI.
;;
;; The ONLY place in src/ui/* that holds hex literals, font paths, or
;; numeric font sizes. Widgets and frames read these tokens; reviewers
;; reject any other module that re-hardcodes them.
;;
;; Pure data + one rgba helper. Busted-testable in isolation.
;; See docs/UI.md §4.

(local M {})

;; --- Palette (warm parchment + gold + ink) ---------------------------------

(set M.palette {:parchment :C4A370
                :parchment-2 :A88752
                :ink :312B22
                :ink-faint :4A3820
                :gold :C9A24A
                :gold-bright :F0CC6E
                :warn :A93F2D
                :ok :5C7A4A
                :shadow :000000})

;; --- Fonts (TBC client built-ins, no LibSharedMedia) -----------------------

(set M.fonts {:title "Fonts\\FRIZQT__.TTF" :body "Fonts\\ARIALN.TTF"})

(set M.sizes {:title 16 :section 13 :body 12 :caption 10})

(set M.spacing {:gutter 12 :inset 16 :rhythm 8})

(set M.radius {:card 4 :pill 12})

(set M.motion {:fade-ms 160 :slide-ms 200})

;; --- Textures (WoW client built-ins) ---------------------------------------

;; Parchment is bundled at Art/Parchment.tga (1024x2048, 32-bit RGBA,
;; top-left origin, UNCOMPRESSED -- WoW Classic refuses RLE-compressed
;; TGA, hence the explicit conversion from the source PNG via
;; `magick ... -compress none`). Sourced from Peterodox's YUI-Dialogue
;; (Art/Theme_Brown/Parchment.png); see CREDITS.md. WoW auto-resolves
;; the extension; omitting it lets us swap formats later.
(set M.textures
     {:parchment "Interface\\AddOns\\Routina\\Art\\Parchment"
      :gold-border "Interface\\Tooltips\\UI-Tooltip-Border"
      :gear-icon "Interface\\Buttons\\UI-OptionsButton"
      :solid "Interface\\Buttons\\WHITE8X8"
      ;; Standard Blizzard mouse-over highlight (the warm bar used
      ;; on quest-log titles); drawn ADD so it reads as the same
      ;; gold glow players see hovering item links in chat.
      :row-highlight "Interface\\QuestFrame\\UI-QuestTitleHighlight"
      ;; Hand-painted hollow parchment cell-border from YUI-Dialogue
      ;; (Theme_Brown/OptionBackground-Hollow), bundled as TGA; see
      ;; CREDITS.md. Wraps each plan item row in a soft DUI-style frame.
      :row-cell "Interface\\AddOns\\Routina\\Art\\OptionBackground-Hollow"})

;; --- Helpers ---------------------------------------------------------------

(lambda M.rgba [hex ?alpha]
  "Convert a 6-char hex string to four floats in [0, 1] for SetColorTexture.
   Domain:  hex    : string of exactly 6 hex digits (no leading '#')
            ?alpha : number in [0, 1] (defaults to 1.0)
   Returns: r, g, b, a as four floats."
  (assert (= 6 (length hex)) (.. "rgba: hex must be 6 chars, got "
                                 (tostring hex)))
  (let [r (/ (tonumber (hex:sub 1 2) 16) 255)
        g (/ (tonumber (hex:sub 3 4) 16) 255)
        b (/ (tonumber (hex:sub 5 6) 16) 255)
        a (or ?alpha 1)]
    (values r g b a)))

;; --- Register into the addon namespace -------------------------------------
;;
;; Dual-mode: in-game, the .toc load order populates `_G.Routina.theme`
;; before any consumer runs. In tests, consumers fall through to
;; `(require :src.ui.theme)` which returns the same M.

(local Routina (or _G.Routina {}))
(set _G.Routina Routina)
(set Routina.theme M)

M
