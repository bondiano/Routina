;; spec/ui/theme_spec.fnl -- pure tests for the theme tokens + rgba.

(local theme (require :src.ui.theme))

(local tokens [:parchment
               :parchment-2
               :panel
               :ink
               :ink-faint
               :gold
               :gold-bright
               :warn
               :ok
               :shadow])

(fn lum-of [palette tok]
  (let [(r g b) (theme.rgba (. palette tok))]
    (+ r g b)))

(describe :theme
          (fn []
            (after_each (fn [] (theme.set-mode! :dark)))
            (describe ":palettes"
                      (fn []
                        (it "both variants carry every token the widgets read"
                            (fn []
                              (each [_ variant (ipairs [:dark :light])]
                                (each [_ k (ipairs tokens)]
                                  (assert.is_not_nil (. theme.palettes variant
                                                        k)
                                                     (.. (tostring variant)
                                                         " missing palette token: "
                                                         k))))))
                        (it "stores tokens as 6-char hex strings in both"
                            (fn []
                              (each [_ variant (ipairs [:dark :light])]
                                (each [_ hex (pairs (. theme.palettes variant))]
                                  (assert.are.equal 6 (length hex))))))
                        (it "dark: light ranked ink on a dark panel"
                            (fn []
                              (let [p theme.palettes.dark]
                                (assert.is_true (> (lum-of p :ink) 2.4))
                                (assert.is_true (> (lum-of p :ink)
                                                   (lum-of p :ink-faint)))
                                (assert.is_true (< (lum-of p :panel) 0.6))
                                (assert.is_true (> (lum-of p :ink)
                                                   (lum-of p :panel))))))
                        (it "light: dark ranked ink on a light panel (mirror)"
                            (fn []
                              (let [p theme.palettes.light]
                                (assert.is_true (< (lum-of p :ink) 0.9))
                                (assert.is_true (< (lum-of p :ink)
                                                   (lum-of p :ink-faint)))
                                (assert.is_true (> (lum-of p :panel) 2.0))
                                (assert.is_true (< (lum-of p :ink)
                                                   (lum-of p :panel))))))
                        (it "accents keep their internal ranking in both modes"
                            (fn []
                              (each [_ variant (ipairs [:dark :light])]
                                (let [p (. theme.palettes variant)]
                                  ;; gold-bright stays the brighter gold
                                  (assert.is_true (> (lum-of p :gold-bright)
                                                     (lum-of p :gold)))))))))
            (describe ":set-mode!"
                      (fn []
                        (it "defaults to dark and reports the active mode"
                            (fn []
                              (assert.are.equal :dark (theme.mode))
                              (assert.are.equal theme.palettes.dark
                                                theme.palette)))
                        (it "swaps the live palette so color follows the mode"
                            (fn []
                              (let [dark-lum (let [(r g b) (theme.color :panel)]
                                               (+ r g b))]
                                (theme.set-mode! :light)
                                (assert.are.equal :light (theme.mode))
                                (assert.are.equal theme.palettes.light
                                                  theme.palette)
                                (let [(r g b) (theme.color :panel)]
                                  (assert.is_true (> (+ r g b) dark-lum))))))
                        (it "reads anything but :light as :dark (corrupt persist)"
                            (fn []
                              (theme.set-mode! :light)
                              (assert.are.equal :dark (theme.set-mode! :junk))
                              (assert.are.equal :dark (theme.set-mode! nil))
                              (assert.are.equal theme.palettes.dark
                                                theme.palette)))))
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
                              (assert.has_error (fn [] (theme.rgba :FFF)))))))
            (describe ":color"
                      (fn []
                        (it "resolves a palette token to four floats"
                            (fn []
                              (let [(r g b a) (theme.color :ink)]
                                (assert.are.equal :number (type r))
                                (assert.are.equal :number (type g))
                                (assert.are.equal :number (type b))
                                (assert.are.equal 1 a))))
                        (it "honours explicit alpha"
                            (fn []
                              (let [(_ _ _ a) (theme.color :gold 0.5)]
                                (assert.are.equal 0.5 a))))
                        (it "rejects an unknown token"
                            (fn []
                              (assert.has_error (fn [] (theme.color :nope)))))))))
