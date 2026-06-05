;; prices.fnl -- read-only item valuation over OPTIONAL price addons.
;;
;; Soft-dep facade in the src/ui/acegui.fnl pattern (ROADMAP guiding principle
;; 6): present -> richer prices, absent -> vendor value, never a hard
;; requirement, never a Lua error. Globals are resolved at CALL time (an
;; OptionalDeps addon may load after us) and every external call sits behind
;; pcall + a type check, so API drift in either addon degrades to the next
;; source instead of erroring. Strictly read-only -- no scanning, posting or
;; flips; AH economy play stays a non-goal (PRD §5).
;;
;; Precedence: TSM (dbmarket via TSM_API.GetCustomPriceValue, the public API
;; surface verified against published TSM_API consumers) > Auctionator
;; (Auctionator.API.v1.GetAuctionPriceByItemID, per the Auctionator API wiki)
;; > GetItemInfo sellPrice (11th return, wiki-verified; nil until the client
;; has the item cached).

(local Routina (or _G.Routina {}))

(local M {})

;; TSM price source consulted via GetCustomPriceValue. dbmarket = the region
;; market value TSM tracks by default; a named binding so a future option can
;; expose it.
(local tsm-price-source :dbmarket)

;; --- Helpers (private) -----------------------------------------------------

(fn positive-number [v]
  "The value when it is a positive number, else nil -- price APIs hand back
   nil / 0 / garbage for unknown items."
  (when (and (= (type v) :number) (> v 0))
    v))

(fn tsm-value [item-id]
  "Item value from TSM's dbmarket, or nil when TSM is absent / has no price."
  (let [api _G.TSM_API]
    (when (and api api.GetCustomPriceValue api.ToItemString)
      (let [(ok v) (pcall (fn []
                            (let [s (api.ToItemString (.. "i:" item-id))]
                              (and s
                                   (api.GetCustomPriceValue tsm-price-source s)))))]
        (when ok (positive-number v))))))

(fn auctionator-value [item-id]
  "Item value from Auctionator's last scan, or nil when absent / unscanned."
  (let [api (?. _G.Auctionator :API :v1)]
    (when (and api api.GetAuctionPriceByItemID)
      (let [(ok v) (pcall api.GetAuctionPriceByItemID :Routina item-id)]
        (when ok (positive-number v))))))

(fn vendor-value [item-id]
  "The item's vendor sell price (GetItemInfo 11th return), or nil while the
   client has not cached the item."
  (let [get-item-info _G.GetItemInfo]
    (when get-item-info
      (let [(ok v) (pcall (fn [] (select 11 (get-item-info item-id))))]
        (when ok (positive-number v))))))

;; --- Public API ------------------------------------------------------------

(lambda M.source []
  "Which price source item-value would consult first, for /rt debug.
   Domain:  (none)
   Returns: :tsm | :auctionator | :vendor."
  (if (and _G.TSM_API _G.TSM_API.GetCustomPriceValue) :tsm
      (?. _G.Auctionator :API :v1 :GetAuctionPriceByItemID) :auctionator
      :vendor))

(lambda M.item-value [item-id]
  "One item's value in copper, from the best available source: TSM dbmarket,
   then Auctionator's last scan, then the vendor sell price. Headless-safe --
   with no price addon and no item cache it returns nil, never errors.
   Domain:  item-id : integer
   Returns: integer copper > 0 | nil."
  (or (tsm-value item-id) (auctionator-value item-id) (vendor-value item-id)))

;; --- Register into the addon namespace -------------------------------------

(set _G.Routina Routina)
(set Routina.prices M)

M
