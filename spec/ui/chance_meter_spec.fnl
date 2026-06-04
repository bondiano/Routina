;; chance_meter_spec.fnl -- the chance-meter's PURE view-model (+ a pool smoke).
;;
;; The gradient is the interesting part: a warm-to-cool confidence ramp, not a
;; pass/fail traffic light (UI.md §6.3/§11). The acquire!/set!/release! cycle is
;; only smoke-tested against the mock CreateFrame -- pixel output is wowUnit-tier.

(local meter (require :src.ui.widgets.chance-meter))
(local theme (require :src.ui.theme))

(describe :chance-meter-view-model
          (fn []
            (it "fill-fraction is p, label is the percent"
                (fn []
                  (let [vm (meter.view-model 0.62)]
                    (assert.are.equal 0.62 vm.fill-fraction)
                    (assert.are.equal "62%" vm.label))))
            (it "low p tints warn (warm end of the ramp)"
                (fn []
                  (assert.are.equal theme.palette.warn
                                    (. (meter.view-model 0.1) :tint))))
            (it "lower-mid p tints gold"
                (fn []
                  (assert.are.equal theme.palette.gold
                                    (. (meter.view-model 0.4) :tint))))
            (it "upper-mid p tints gold-bright"
                (fn []
                  (assert.are.equal theme.palette.gold-bright
                                    (. (meter.view-model 0.6) :tint))))
            (it "high p tints ok (cool end of the ramp)"
                (fn []
                  (assert.are.equal theme.palette.ok
                                    (. (meter.view-model 0.9) :tint))))
            (it "carries an optional hint, defaulting to empty"
                (fn []
                  (assert.are.equal "" (. (meter.view-model 0.5) :hint))
                  (assert.are.equal "per run"
                                    (. (meter.view-model 0.5 "per run") :hint))))
            (it "rejects p outside [0,1]"
                (fn []
                  (assert.has_error #(meter.view-model 1.5))
                  (assert.has_error #(meter.view-model -0.1))))))

(describe :chance-meter-pool-smoke
          (fn []
            (it "acquire! -> set! -> release! does not raise"
                (fn []
                  (let [f (meter.acquire! _G.UIParent)]
                    (assert.is_truthy f)
                    (meter.set! f (meter.view-model 0.5))
                    (meter.render! f 0.0)
                    (meter.render! f 1.0)
                    (assert.is_nil (meter.release! f)))))))
