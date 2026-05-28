;; spec/ui/theme_spec.fnl -- pure tests for the theme tokens + rgba.

(local theme (require :src.ui.theme))

(describe :theme
          (fn []
            (describe ":palette"
                      (fn []
                        (it "carries every token the widgets read"
                            (fn []
                              (each [_ k (ipairs [:parchment
                                                  :parchment-2
                                                  :ink
                                                  :ink-faint
                                                  :gold
                                                  :gold-bright
                                                  :warn
                                                  :ok
                                                  :shadow])]
                                (assert.is_not_nil (. theme.palette k)
                                                   (.. "missing palette token: "
                                                       k)))))
                        (it "stores tokens as 6-char hex strings"
                            (fn []
                              (each [_ hex (pairs theme.palette)]
                                (assert.are.equal 6 (length hex)))))))
            (describe ":fonts"
                      (fn []
                        (it "has title and body paths"
                            (fn []
                              (assert.is_not_nil theme.fonts.title)
                              (assert.is_not_nil theme.fonts.body)))))
            (describe ":sizes"
                      (fn []
                        (it "covers title/section/body/caption"
                            (fn []
                              (each [_ k (ipairs [:title
                                                  :section
                                                  :body
                                                  :caption])]
                                (assert.is_not_nil (. theme.sizes k)))))))
            (describe ":rgba"
                      (fn []
                        (it "converts pure white"
                            (fn []
                              (let [(r g b a) (theme.rgba :FFFFFF)]
                                (assert.are.equal 1 r)
                                (assert.are.equal 1 g)
                                (assert.are.equal 1 b)
                                (assert.are.equal 1 a))))
                        (it "converts pure black"
                            (fn []
                              (let [(r g b) (theme.rgba :000000)]
                                (assert.are.equal 0 r)
                                (assert.are.equal 0 g)
                                (assert.are.equal 0 b))))
                        (it "decodes mid-channel byte 0x80 to ~0.5"
                            (fn []
                              (let [(r _ _) (theme.rgba :808080)]
                                (assert.is_true (and (> r 0.5) (< r 0.51))))))
                        (it "honours explicit alpha"
                            (fn []
                              (let [(_ _ _ a) (theme.rgba :FFFFFF 0.25)]
                                (assert.are.equal 0.25 a))))
                        (it "rejects wrong-length hex"
                            (fn []
                              (assert.has_error (fn [] (theme.rgba :FFF)))))))))
