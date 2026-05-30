;; spec/ui/dom_spec.fnl -- tests for the Hiccup renderer.
;;
;; All asserts work against the stub CreateFrame in spec/mocks/wow-api.fnl.
;; Pixel layout stays wowUnit territory (docs/TESTING.md).

(local dom (require :src.ui.dom))

(describe :dom
          (fn []
            (describe ":render!"
                      (fn []
                        (it "returns a table with :root and :refs"
                            (fn []
                              (let [parent (_G.CreateFrame :Frame)
                                    result (dom.render! parent [:Frame {}])]
                                (assert.is_not_nil result.root)
                                (assert.are.equal :table (type result.refs)))))
                        (it "stores :id-tagged frames in refs"
                            (fn []
                              (let [parent (_G.CreateFrame :Frame)
                                    result (dom.render! parent
                                                        [:Frame
                                                         {:id :outer}
                                                         [:FontString
                                                          {:id :inner
                                                           :text :hi}]])]
                                (assert.is_not_nil (. result.refs :outer))
                                (assert.is_not_nil (. result.refs :inner)))))
                        (it "wires :on-click handlers retrievable via GetScript"
                            (fn []
                              (var clicked? false)
                              (let [parent (_G.CreateFrame :Frame)
                                    result (dom.render! parent
                                                        [:Button
                                                         {:id :btn
                                                          :on-click (fn []
                                                                      (set clicked?
                                                                           true))}])
                                    btn (. result.refs :btn)
                                    handler (btn:GetScript :OnClick)]
                                (assert.are.equal :function (type handler))
                                (handler)
                                (assert.is_true clicked?))))
                        (it "throws on unknown tag"
                            (fn []
                              (let [parent (_G.CreateFrame :Frame)]
                                (assert.has_error (fn []
                                                    (dom.render! parent
                                                                 [:UnknownTag
                                                                  {}]))))))
                        (it "throws on unknown anchor ref"
                            (fn []
                              (let [parent (_G.CreateFrame :Frame)]
                                (assert.has_error (fn []
                                                    (dom.render! parent
                                                                 [:Frame
                                                                  {:anchors [[:TOPLEFT
                                                                              :nope
                                                                              :TOPLEFT
                                                                              0
                                                                              0]]}]))))))
                        (it ":parent reserved keyword resolves to caller parent"
                            (fn []
                              (let [parent (_G.CreateFrame :Frame)
                                    result (dom.render! parent
                                                        [:Frame
                                                         {:id :child
                                                          :anchors [[:TOPLEFT
                                                                     :parent
                                                                     :TOPLEFT
                                                                     0
                                                                     0]]}])]
                                (assert.is_not_nil (. result.refs :child)))))
                        (it "sibling-by-id anchors work in DFS order"
                            (fn []
                              (let [parent (_G.CreateFrame :Frame)
                                    result (dom.render! parent
                                                        [:Frame
                                                         {:id :wrap}
                                                         [:FontString
                                                          {:id :first
                                                           :text :a
                                                           :anchors [[:TOPLEFT
                                                                      :parent
                                                                      :TOPLEFT
                                                                      0
                                                                      0]]}]
                                                         [:FontString
                                                          {:id :second
                                                           :text :b
                                                           :anchors [[:TOPLEFT
                                                                      :first
                                                                      :BOTTOMLEFT
                                                                      0
                                                                      0]]}]])]
                                (assert.is_not_nil (. result.refs :first))
                                (assert.is_not_nil (. result.refs :second)))))
                        (it "forward sibling refs throw"
                            (fn []
                              (let [parent (_G.CreateFrame :Frame)]
                                (assert.has_error (fn []
                                                    (dom.render! parent
                                                                 [:Frame
                                                                  {}
                                                                  [:FontString
                                                                   {:id :first
                                                                    :text :a
                                                                    :anchors [[:TOPLEFT
                                                                               :second
                                                                               :BOTTOMLEFT
                                                                               0
                                                                               0]]}]
                                                                  [:FontString
                                                                   {:id :second
                                                                    :text :b}]]))))))
                        (it ":fill sugar does not raise"
                            (fn []
                              (let [parent (_G.CreateFrame :Frame)]
                                (dom.render! parent
                                             [:Frame
                                              {:fill true}
                                              [:FontString {:text :hi}]]))))
                        (it "supports nested specs as children of children"
                            (fn []
                              (let [parent (_G.CreateFrame :Frame)
                                    result (dom.render! parent
                                                        [:Frame
                                                         {:id :outer}
                                                         [:Frame
                                                          {:id :mid}
                                                          [:FontString
                                                           {:id :inner
                                                            :text :x}]]])]
                                (assert.is_not_nil (. result.refs :outer))
                                (assert.is_not_nil (. result.refs :mid))
                                (assert.is_not_nil (. result.refs :inner)))))
                        (it ":size on FontString is a font-kind keyword, not a [w h] tuple"
                            (fn []
                              ;; Regression: dom.fnl previously destructured
                              ;; attrs.size unconditionally, so SetSize(nil,nil)
                              ;; fired on every FontString. The mock now asserts
                              ;; SetSize args are numbers (mirrors real WoW),
                              ;; so this test would have caught it.
                              (let [parent (_G.CreateFrame :Frame)]
                                (dom.render! parent
                                             [:FontString
                                              {:font :title
                                               :size :title
                                               :color :ink
                                               :text :ok}]))))
                        (it ":size [w h] on Frame still calls SetSize"
                            (fn []
                              (let [parent (_G.CreateFrame :Frame)]
                                (dom.render! parent [:Frame {:size [560 480]}]))))
                        (it ":fill-color on Texture resolves a palette token"
                            (fn []
                              (let [parent (_G.CreateFrame :Frame)]
                                (dom.render! parent
                                             [:Frame
                                              {:id :wrap}
                                              [:Texture
                                               {:id :sep
                                                :layer :ARTWORK
                                                :fill-color :ink
                                                :alpha 0.3
                                                :height 1}]]))))
                        (it ":fill-color throws on unknown palette token"
                            (fn []
                              (let [parent (_G.CreateFrame :Frame)]
                                (assert.has_error (fn []
                                                    (dom.render! parent
                                                                 [:Texture
                                                                  {:fill-color :nope}]))))))
                        (it ":height on a Texture calls SetHeight"
                            (fn []
                              (let [parent (_G.CreateFrame :Frame)]
                                (dom.render! parent
                                             [:Texture
                                              {:fill-color :gold :height 1}]))))))))
