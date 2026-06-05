;; prices_spec.fnl -- the soft-dep price facade degrades, never errors.
;;
;; The Phase 7 exit criterion in busted form: with neither TSM nor Auctionator
;; installed the facade falls back to the vendor price (or nil), and a present
;; addon is consulted in precedence order. Fake addon globals are installed
;; per-test and always cleared.

(local prices (require :src.core.prices))

(fn with-globals [globals body]
  "Run body with _G temporarily extended; always restores, even on error."
  (let [saved (collect [k _ (pairs globals)] k (. _G k))]
    (each [k v (pairs globals)]
      (tset _G k v))
    (let [(ok err) (pcall body)]
      (each [k _ (pairs globals)]
        (tset _G k (. saved k)))
      (assert ok err))))

(describe :prices
          (fn []
            (describe "no price addon installed"
                      (fn []
                        (it "reports the vendor source"
                            (fn []
                              (assert.are.equal :vendor (prices.source))))
                        (it "returns nil cleanly when the item is uncached"
                            (fn []
                              ;; the mock GetItemInfo returns no 11th value
                              (assert.is_nil (prices.item-value 29434))))
                        (it "survives GetItemInfo being absent entirely"
                            (fn []
                              (with-globals {:GetItemInfo false}
                                (fn []
                                  (set _G.GetItemInfo nil)
                                  (assert.has_no.errors #(prices.item-value 29434))
                                  (assert.is_nil (prices.item-value 29434))))))))
            (describe "vendor fallback"
                      (fn []
                        (it "reads sellPrice, GetItemInfo's 11th return"
                            (fn []
                              (with-globals {:GetItemInfo (fn [_id]
                                                            (values :n :l 4 70
                                                                    nil nil nil
                                                                    nil nil nil
                                                                    1234))}
                                (fn []
                                  (assert.are.equal 1234 (prices.item-value 1))))))))
            (describe :Auctionator
                      (fn []
                        (it "is consulted before the vendor price"
                            (fn []
                              (with-globals {:Auctionator {:API {:v1 {:GetAuctionPriceByItemID (fn [_caller
                                                                                                    id]
                                                                                                 (* id
                                                                                                    10))}}}}
                                (fn []
                                  (assert.are.equal :auctionator
                                                    (prices.source))
                                  (assert.are.equal 50 (prices.item-value 5))))))
                        (it "degrades past a throwing or priceless API"
                            (fn []
                              (with-globals {:Auctionator {:API {:v1 {:GetAuctionPriceByItemID (fn []
                                                                                                 (error :boom))}}}}
                                (fn []
                                  (assert.is_nil (prices.item-value 5))))))))
            (describe :TSM
                      (fn []
                        (local fake-tsm
                               {:ToItemString (fn [s] s)
                                :GetCustomPriceValue (fn [_source _item] 777)})
                        (it "wins the precedence when present"
                            (fn []
                              (with-globals {:TSM_API fake-tsm
                                             :Auctionator {:API {:v1 {:GetAuctionPriceByItemID (fn []
                                                                                                 111)}}}}
                                (fn []
                                  (assert.are.equal :tsm (prices.source))
                                  (assert.are.equal 777 (prices.item-value 5))))))
                        (it "falls through when TSM has no price for the item"
                            (fn []
                              (with-globals {:TSM_API {:ToItemString (fn [s] s)
                                                       :GetCustomPriceValue (fn []
                                                                              nil)}
                                             :Auctionator {:API {:v1 {:GetAuctionPriceByItemID (fn []
                                                                                                 111)}}}}
                                (fn []
                                  (assert.are.equal 111 (prices.item-value 5))))))))))
