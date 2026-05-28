;; spec/ui/format_spec.fnl -- pure tests for percent / duration / score.

(local format (require :src.ui.format))

(describe :format
          (fn []
            (describe ":percent"
                      (fn []
                        (it "formats 0 as 0%"
                            (fn []
                              (assert.are.equal "0%" (format.percent 0))))
                        (it "formats 0.5 as 50%"
                            (fn []
                              (assert.are.equal "50%" (format.percent 0.5))))
                        (it "formats 1 as 100%"
                            (fn []
                              (assert.are.equal "100%" (format.percent 1))))
                        (it "rounds 0.625 to 63%"
                            (fn []
                              (assert.are.equal "63%" (format.percent 0.625))))
                        (it "rounds 0.624 to 62%"
                            (fn []
                              (assert.are.equal "62%" (format.percent 0.624))))
                        (it "guards against nil"
                            (fn []
                              (assert.are.equal "--" (format.percent nil))))
                        (it "guards against NaN"
                            (fn []
                              (assert.are.equal "--" (format.percent (/ 0 0)))))))
            (describe ":duration-short"
                      (fn []
                        (it "uses d/h for >= 1 day"
                            (fn []
                              (assert.are.equal "2d 4h"
                                                (format.duration-short (+ (* 2
                                                                             86400)
                                                                          (* 4
                                                                             3600))))))
                        (it "uses h/m for >= 1 hour"
                            (fn []
                              (assert.are.equal "8h 21m"
                                                (format.duration-short (+ (* 8
                                                                             3600)
                                                                          (* 21
                                                                             60))))))
                        (it "uses m:ss for sub-hour"
                            (fn []
                              (assert.are.equal "0:42"
                                                (format.duration-short 42))))
                        (it "guards against nil"
                            (fn []
                              (assert.are.equal "--"
                                                (format.duration-short nil))))
                        (it "guards against negative"
                            (fn []
                              (assert.are.equal "--" (format.duration-short -1))))))
            (describe ":score-short"
                      (fn []
                        (it "formats 0.83 as 0.83"
                            (fn []
                              (assert.are.equal :0.83 (format.score-short 0.83))))
                        (it "guards against nil"
                            (fn []
                              (assert.are.equal "--" (format.score-short nil))))))))
