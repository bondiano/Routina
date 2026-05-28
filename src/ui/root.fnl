;; root.fnl -- Routina main panel: parchment journal frame with header,
;; three tab pills, and a content area. Singleton (no pool).
;;
;; Layout is data: a single `root-spec` vector is fed to `dom.render!`.
;; State (active-tab), event handlers, pool-less singleton lifecycle, and
;; the restyle-on-state-change loop stay imperative -- see docs/UI.md §15.

(local Routina (or _G.Routina {}))
(local theme (or Routina.theme (require :src.ui.theme)))
(local frames (or Routina.frames (require :src.ui.frames)))
(local dom (or Routina.dom (require :src.ui.dom)))
(local tab-weekly (or Routina.tab-weekly (require :src.ui.tabs.weekly)))
(local tab-lockouts (or Routina.tab-lockouts (require :src.ui.tabs.lockouts)))
(local tab-bis (or Routina.tab-bis (require :src.ui.tabs.bis)))
(local UnitName _G.UnitName)
(local UnitClass _G.UnitClass)

(local M {})

(var root nil)

(local pills {})

(local tab-contents {})

(var active-tab :weekly)

;; --- Event handlers (imperative, per UI.md §15) ----------------------------

(fn gear-on-enter [self]
  (_G.GameTooltip:SetOwner self :ANCHOR_LEFT)
  (_G.GameTooltip:SetText "Options coming soon" 1 1 1)
  (_G.GameTooltip:Show))

(fn gear-on-leave []
  (_G.GameTooltip:Hide))

(fn gear-on-click []
  (_G.DEFAULT_CHAT_FRAME:AddMessage "|cffC9A24A[Routina]|r Options panel not yet implemented."))

(fn click-pill [key]
  (fn [] (M.show-tab! key)))

(fn restyle-pills! []
  (each [key pill (pairs pills)]
    (let [active? (= key active-tab)
          bg-token (if active? :gold-bright :parchment-2)
          text-token (if active? :ink :ink-faint)]
      (frames.apply-inset-backdrop! pill.button bg-token)
      (pill.text:SetTextColor (theme.rgba (. theme.palette text-token) 1)))))

;; --- Layout spec -----------------------------------------------------------

(fn player-display []
  ;; UnitName / UnitClass return localized values; UnitClass also
  ;; returns the english uppercase form as a 2nd return we ignore for
  ;; now. Spec (talent-based) detection arrives with AceEvent.
  (let [name (or (UnitName :player) :Player)
        class (or (UnitClass :player) :Adventurer)]
    (.. name " · " class)))

(fn header-spec []
  (let [inset theme.spacing.inset
        rhythm theme.spacing.rhythm]
    [:Frame
     {:id :header
      :height 48
      :anchors [[:TOPLEFT :parent :TOPLEFT inset (- inset)]
                [:TOPRIGHT :parent :TOPRIGHT (- inset) (- inset)]]}
     [:FontString
      {:id :char-line
       :font :title
       :size :title
       :color :ink
       :text (player-display)
       :anchors [[:TOPLEFT :header :TOPLEFT 0 0]]}]
     [:FontString
      {:font :body
       :size :body
       :color :ink-faint
       :text "Week 47 · resets in 2d 4h"
       :anchors [[:TOPLEFT :char-line :BOTTOMLEFT 0 (- rhythm)]]}]
     [:Button
      {:id :gear
       :size [22 22]
       :anchors [[:TOPRIGHT :header :TOPRIGHT 0 0]]
       :on-enter gear-on-enter
       :on-leave gear-on-leave
       :on-click gear-on-click}
      [:Texture {:layer :ARTWORK :fill-parent? true :texture-token :gear-icon}]]]))

(fn pill-spec [btn-id text-id label tab-key anchor]
  [:Button
   {:id btn-id
    :size [120 28]
    :backdrop :parchment-2
    :anchors [anchor]
    :on-click (click-pill tab-key)}
   [:FontString
    {:id text-id
     :font :title
     :size :section
     :color :ink-faint
     :text label
     :anchors [[:CENTER :parent :CENTER 0 0]]}]])

(fn pill-row-spec []
  (let [inset theme.spacing.inset
        rhythm theme.spacing.rhythm]
    [:Frame
     {:id :pill-row
      :height 28
      :anchors [[:TOPLEFT :parent :TOPLEFT inset -72]
                [:TOPRIGHT :parent :TOPRIGHT (- inset) -72]]}
     (pill-spec :pill-weekly :pill-weekly-text :Plan :weekly
                [:LEFT :pill-row :LEFT 0 0])
     (pill-spec :pill-lockouts :pill-lockouts-text :Lockouts :lockouts
                [:LEFT :pill-weekly :RIGHT rhythm 0])
     (pill-spec :pill-bis :pill-bis-text :BiS :bis
                [:LEFT :pill-lockouts :RIGHT rhythm 0])]))

(fn root-spec []
  (let [inset theme.spacing.inset]
    [:Frame
     {:id :root
      :name :RoutinaRoot
      :size [560 480]
      :strata :HIGH
      :movable? true
      :mouse? true
      :drag-with :LeftButton
      :backdrop :parchment
      :border? true
      :anchors [[:CENTER :parent :CENTER 0 80]]}
     (header-spec)
     (pill-row-spec)
     [:Frame
      {:id :content-area
       :anchors [[:TOPLEFT :parent :TOPLEFT inset -116]
                 [:BOTTOMRIGHT :parent :BOTTOMRIGHT (- inset) inset]]}]]))

;; --- Construction (imperative singleton, lazy on first toggle!) ------------

(fn build-root! []
  (let [{: root : refs} (dom.render! _G.UIParent (root-spec))]
    (frames.apply-page-ornaments! root)
    (set pills.weekly {:button (. refs :pill-weekly)
                       :text (. refs :pill-weekly-text)})
    (set pills.lockouts
         {:button (. refs :pill-lockouts) :text (. refs :pill-lockouts-text)})
    (set pills.bis {:button (. refs :pill-bis) :text (. refs :pill-bis-text)})
    (let [area (. refs :content-area)]
      (set tab-contents.weekly (tab-weekly.build! area))
      (set tab-contents.lockouts (tab-lockouts.build! area))
      (set tab-contents.bis (tab-bis.build! area)))
    (when _G.UISpecialFrames
      (table.insert _G.UISpecialFrames :RoutinaRoot))
    root))

(fn ensure-root! []
  (when (not root)
    (set root (build-root!))
    (M.show-tab! active-tab))
  root)

;; --- Public API ------------------------------------------------------------

(lambda M.show! []
  "Show the root panel, constructing it on first call.
   Returns: nil."
  (let [r (ensure-root!)]
    (r:Show))
  nil)

(lambda M.hide! []
  "Hide the root panel if it was already constructed.
   Returns: nil."
  (when root (root:Hide))
  nil)

(lambda M.toggle! []
  "Toggle root panel visibility (constructs on first show).
   Returns: nil."
  (if (and root (root:IsShown)) (M.hide!) (M.show!))
  nil)

(lambda M.show-tab! [key]
  "Show the named tab, hide the others, restyle the pill row.
   Domain:  key : one of :weekly :lockouts :bis
   Returns: nil."
  (assert (. tab-contents key) (.. "unknown tab key: " (tostring key)))
  (each [k content (pairs tab-contents)]
    (if (= k key) (content:Show) (content:Hide)))
  (set active-tab key)
  (restyle-pills!)
  nil)

;; --- Register --------------------------------------------------------------

(set _G.Routina Routina)
(set Routina.root M)

M
