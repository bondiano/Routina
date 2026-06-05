;; tabs/chains-editor.fnl -- the Chains tab's route constructor (Phase 8
;; §3/§4), split out of tabs/chains.fnl (size rule).
;;
;; Owns the persisted db.profile.custom-chains list (created on first
;; access, mutated in place -- the options.fnl accessor precedent) and the
;; inline New-chain editor. Editor state lives in module closures (the
;; why-drawer singleton pattern): nothing persists until Add validates the
;; assembled CustomChain via custom-chains.normalize, so a half-filled form
;; can never write a corrupt row. Steps are authored as text, one step per
;; line (the pure custom-chains.parse-steps). All AceGUI through the facade,
;; headless-safe.

(local Routina (or _G.Routina {}))
(local acegui (or Routina.acegui (require :src.ui.acegui)))
(local custom-chains
       (or Routina.custom-chains (require :src.domain.custom-chains)))

(local M {})

(fn refresh! []
  (when Routina.root (Routina.root.refresh!)))

(lambda M.custom-db []
  "addon.db.profile.custom-chains -- the persisted CustomChain list the
   constructor mutates in place; created empty on first access, nil headless.
   Domain:  (none)
   Returns: the live list | nil."
  (let [profile (?. Routina :addon :db :profile)]
    (when profile
      (when (= nil profile.custom-chains)
        (set profile.custom-chains []))
      profile.custom-chains)))

(lambda M.delete-custom! [chain-id]
  "Remove one authored chain from the persisted list and repaint.
   Domain:  chain-id : string|keyword
   Returns: nil."
  (let [persisted (M.custom-db)]
    (when persisted
      (let [idx (accumulate [found nil i c (ipairs persisted) &until found]
                  (when (= (tostring c.id) (tostring chain-id)) i))]
        (when idx (table.remove persisted idx))
        (refresh!))))
  nil)

;; --- Inline editor -----------------------------------------------------------

(var editor-open? false)
(var draft-name "")
(var draft-steps "")

(fn add-custom! []
  "Validate the draft and persist it; keep the form on a validation miss so
   the player can fix it in place."
  (let [persisted (M.custom-db)]
    (when persisted
      (let [draft {:id (custom-chains.next-id persisted)
                   :name draft-name
                   :steps (custom-chains.parse-steps draft-steps)}
            valid (custom-chains.normalize [draft])]
        (when (= 1 (length valid))
          (table.insert persisted (. valid 1))
          (set editor-open? false)
          (set draft-name "")
          (set draft-steps "")
          (refresh!))))))

(lambda M.build-editor! [container]
  "Append the New-chain affordance: the opener button while closed, the
   inline editor card (name + one-step-per-line text + Add/Cancel) while open.
   Domain:  container : an AceGUI container widget
   Returns: nil."
  (if (not editor-open?)
      (let [open (acegui.create! :Button)]
        (when open
          (open:SetText "New chain")
          (open:SetWidth 160)
          (open:SetCallback :OnClick
                            (fn []
                              (set editor-open? true)
                              (refresh!)))
          (container:AddChild open)))
      (let [card (acegui.create! :InlineGroup)]
        (when card
          (card:SetTitle "New chain")
          (card:SetFullWidth true)
          (card:SetLayout :List)
          (let [name-box (acegui.create! :EditBox)]
            (when name-box
              (name-box:SetLabel :Name)
              (name-box:SetText draft-name)
              (name-box:SetFullWidth true)
              ;; verified: AceGUIWidget-EditBox fires OnTextChanged with the
              ;; current value
              (name-box:SetCallback :OnTextChanged
                                    (fn [_ _ text] (set draft-name text)))
              (name-box:SetCallback :OnEnterPressed
                                    (fn [_ _ text] (set draft-name text)))
              (card:AddChild name-box)))
          (let [steps-box (acegui.create! :MultiLineEditBox)]
            (when steps-box
              (steps-box:SetLabel "Steps (one per line)")
              (steps-box:SetText draft-steps)
              (steps-box:SetFullWidth true)
              (steps-box:SetNumLines 6)
              (steps-box:SetCallback :OnTextChanged
                                     (fn [_ _ text] (set draft-steps text)))
              (steps-box:SetCallback :OnEnterPressed
                                     (fn [_ _ text] (set draft-steps text)))
              (card:AddChild steps-box)))
          (let [add (acegui.create! :Button)]
            (when add
              (add:SetText "Add chain")
              (add:SetWidth 140)
              (add:SetCallback :OnClick add-custom!)
              (card:AddChild add)))
          (let [cancel (acegui.create! :Button)]
            (when cancel
              (cancel:SetText :Cancel)
              (cancel:SetWidth 140)
              (cancel:SetCallback :OnClick
                                  (fn []
                                    (set editor-open? false)
                                    (refresh!)))
              (card:AddChild cancel)))
          (container:AddChild card))))
  nil)

;; --- Register into the addon namespace ---------------------------------------

(set _G.Routina Routina)
(set Routina.tab-chains-editor M)

M
