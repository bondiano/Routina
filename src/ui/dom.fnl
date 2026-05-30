;; dom.fnl -- Hiccup-style runtime renderer for Routina's UI.
;;
;; Given a vector spec `[tag attrs & children]`, walks it depth-first and
;; calls CreateFrame / SetPoint / SetText / etc. under the hood. Returns
;; both the root frame and a `refs` table keyed by each node's :id, so
;; callers can mutate specific elements later (e.g. restyle-pills! after
;; a tab switch).
;;
;; Layout is data; state and event handling stay imperative -- see
;; docs/UI.md §15 for the split rule.

(local Routina (or _G.Routina {}))
(local theme (or Routina.theme (require :src.ui.theme)))
(local frames (or Routina.frames (require :src.ui.frames)))
(local CreateFrame _G.CreateFrame)

(local M {})

;; --- Tag dispatch ----------------------------------------------------------
;;
;; Each builder takes (parent attrs) and returns the new WoW object. The
;; renderer never branches on tag elsewhere; new tags only need an entry
;; here. Pixel-correctness is wowUnit territory (docs/TESTING.md).

(local builders {})

;; On modern WoW (retail 9.0+, TBC Classic Anniversary, Wrath Classic),
;; Frame no longer exposes :SetBackdrop unless created with the
;; BackdropTemplate template. Auto-inject it when the spec asks for
;; :backdrop and the caller didn't supply an explicit :template.
(fn resolve-template [attrs]
  (or attrs.template (when attrs.backdrop :BackdropTemplate)))

(set builders.Frame
     (fn [parent attrs]
       (CreateFrame :Frame attrs.name parent (resolve-template attrs))))

(set builders.Button
     (fn [parent attrs]
       (CreateFrame :Button attrs.name parent (resolve-template attrs))))

(set builders.FontString
     (fn [parent attrs]
       (frames.make-font-string! parent (or attrs.layer :OVERLAY)
                                 (or attrs.font :body) (or attrs.size :body)
                                 (or attrs.color :ink))))

(set builders.Texture
     (fn [parent attrs]
       (parent:CreateTexture attrs.name (or attrs.layer :ARTWORK))))

;; --- Anchor resolution -----------------------------------------------------

(fn resolve-ref [ref-key parent refs]
  (if (= ref-key :parent) parent
      (or (. refs ref-key)
          (error (.. "dom: unknown anchor ref :" (tostring ref-key)
                     " (forward refs and unknown ids both throw; "
                     "render order is top-down DFS, see docs/UI.md §15)")))))

(fn apply-anchor! [frame anchor parent refs]
  (let [[point ref-key ref-point x y] anchor
        target (resolve-ref ref-key parent refs)]
    (frame:SetPoint point target ref-point (or x 0) (or y 0))))

(fn apply-anchors! [frame anchors parent refs]
  (each [_ a (ipairs anchors)]
    (apply-anchor! frame a parent refs)))

;; --- Attribute application -------------------------------------------------
;;
;; Order matters: build -> size -> backdrop -> text/texture ->
;; strata/movable/drag -> anchors -> handlers. Anchors come last among
;; the structural attrs so a node can refer to its own id (already in
;; refs) when needed, and so the frame is fully shaped before WoW lays
;; it out.

(fn apply-size! [frame attrs]
  ;; :size is overloaded: a [w h] tuple on Frame/Button, a font-size
  ;; kind keyword (:title :section :body :caption) on FontString. The
  ;; FontString builder consumes the keyword form before we get here,
  ;; so apply only the tuple form -- a keyword/string is for someone
  ;; else.
  (when (and attrs.size (= :table (type attrs.size)))
    (let [[w h] attrs.size]
      (frame:SetSize w h)))
  (when attrs.width (frame:SetWidth attrs.width))
  (when attrs.height (frame:SetHeight attrs.height)))

(fn apply-backdrop! [frame attrs]
  (case attrs.backdrop
    nil nil
    :parchment (frames.apply-parchment-backdrop! frame
                                                 (not= attrs.border? false))
    token (frames.apply-inset-backdrop! frame token)))

(fn apply-highlight! [frame attrs]
  ;; Buttons only: the standard Blizzard mouse-over highlight, drawn ADD so
  ;; it matches the gold glow on chat item links. WoW shows/hides it on
  ;; hover automatically once the texture is set.
  (when attrs.highlight
    (let [path (. theme.textures attrs.highlight)]
      (assert path (.. "dom: unknown :highlight texture token :"
                       (tostring attrs.highlight)))
      (frame:SetHighlightTexture path :ADD))))

(fn apply-text! [frame attrs]
  (when attrs.text (frame:SetText attrs.text)))

(fn apply-texture! [frame attrs parent]
  (when attrs.texture-token
    (frame:SetTexture (. theme.textures attrs.texture-token)))
  (when attrs.fill-color
    ;; Solid-coloured Texture (no image). Used for dividers, separators,
    ;; future tinted overlays. :alpha defaults to 1.
    (let [hex (. theme.palette attrs.fill-color)]
      (assert hex (.. "dom: unknown :fill-color palette token :"
                      (tostring attrs.fill-color)))
      (frame:SetColorTexture (theme.rgba hex (or attrs.alpha 1)))))
  (when attrs.fill-parent? (frame:SetAllPoints parent)))

(fn apply-frame-traits! [frame attrs]
  (when attrs.strata (frame:SetFrameStrata attrs.strata))
  (when attrs.movable? (frame:SetMovable true))
  (when attrs.mouse? (frame:EnableMouse true))
  (when attrs.drag-with
    (frame:RegisterForDrag attrs.drag-with)
    (frame:SetScript :OnDragStart frame.StartMoving)
    (frame:SetScript :OnDragStop frame.StopMovingOrSizing)))

(local fill-anchors
       [[:TOPLEFT :parent :TOPLEFT 0 0]
        [:BOTTOMRIGHT :parent :BOTTOMRIGHT 0 0]])

(fn apply-layout! [frame attrs parent refs]
  (when attrs.fill (apply-anchors! frame fill-anchors parent refs))
  (when attrs.anchors (apply-anchors! frame attrs.anchors parent refs)))

(fn apply-handlers! [frame attrs]
  (when attrs.on-click (frame:SetScript :OnClick attrs.on-click))
  (when attrs.on-enter (frame:SetScript :OnEnter attrs.on-enter))
  (when attrs.on-leave (frame:SetScript :OnLeave attrs.on-leave)))

(fn apply-attrs! [frame attrs parent refs]
  (apply-size! frame attrs)
  (apply-backdrop! frame attrs)
  (apply-text! frame attrs)
  (apply-texture! frame attrs parent)
  (apply-frame-traits! frame attrs)
  (apply-highlight! frame attrs)
  (apply-layout! frame attrs parent refs)
  (apply-handlers! frame attrs))

;; --- Render walk -----------------------------------------------------------

(fn render-node! [node parent refs]
  (let [[tag attrs & children] node
        attrs (or attrs {})
        build (. builders tag)]
    (assert build (.. "dom: unknown tag :" (tostring tag)))
    (let [frame (build parent attrs)]
      (when attrs.id (tset refs attrs.id frame))
      (apply-attrs! frame attrs parent refs)
      (each [_ child (ipairs children)]
        (when child (render-node! child frame refs)))
      frame)))

(lambda M.render! [parent spec]
  "Render a Hiccup-style spec under parent.
   Domain:  parent : WoW Frame
            spec   : sequential table [tag attrs & children]
                     where tag is a keyword (:Frame :Button :FontString :Texture),
                     attrs is a flat map (see docs/UI.md §15),
                     children are nested specs.
   Returns: {:root frame :refs {id -> frame}}
   Errors:  unknown tag, unknown anchor ref (forward or absent)."
  (let [refs {}
        root (render-node! spec parent refs)]
    {: root : refs}))

;; --- Register --------------------------------------------------------------

(set _G.Routina Routina)
(set Routina.dom M)

M
