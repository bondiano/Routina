;; lockout_timer_spec.fnl -- the lockout-timer's PURE view-model (+ pool smoke).
;;
;; The urgency model is the interesting part: the bar fills only over the last
;; 24h and the tint bands ink-faint -> gold -> warn (UI.md §6.4). The pulse and
;; the throttled OnUpdate are imperative shell, smoke-tested against the mock.

(local timer (require :src.ui.widgets.lockout-timer))
(local theme (require :src.ui.theme))

(local now 1000000)
(local day 86400)
(local half 43200)

(fn at [secs-left]
  "view-model for a lockout `secs-left` seconds from resetting."
  (timer.view-model (+ now secs-left) now))

(describe :lockout-timer-view-model
          (fn []
            (it "beyond 24h is calm: ink-faint, empty bar"
                (fn []
                  (let [vm (at (* 3 day))]
                    (assert.are.equal :calm vm.band)
                    (assert.are.equal theme.palette.ink-faint vm.tint)
                    (assert.are.equal 0 vm.fill-fraction)
                    (assert.is_false vm.expired?))))
            (it "at exactly 24h the bar is still empty (calm boundary)"
                (fn []
                  (let [vm (at day)]
                    (assert.are.equal :calm vm.band)
                    (assert.are.equal 0 vm.fill-fraction))))
            (it "12-24h is soon: gold, bar half full at the midpoint"
                (fn []
                  (let [vm (at half)]
                    (assert.are.equal :soon vm.band)
                    (assert.are.equal theme.palette.gold vm.tint)
                    (assert.are.equal 0.5 vm.fill-fraction))))
            (it "under 12h is urgent: warn, bar past half"
                (fn []
                  (let [vm (at (/ day 4))]
                    (assert.are.equal :urgent vm.band)
                    (assert.are.equal theme.palette.warn vm.tint)
                    (assert.is_true (> vm.fill-fraction 0.5)))))
            (it "at/after reset is expired: full bar, clamped secs"
                (fn []
                  (let [vm (at 0)]
                    (assert.are.equal 0 vm.secs)
                    (assert.are.equal 1 vm.fill-fraction)
                    (assert.is_true vm.expired?))
                  (let [past (timer.view-model (- now 500) now)]
                    (assert.are.equal 0 past.secs)
                    (assert.is_true past.expired?))))
            (it "prefixes the label when given"
                (fn []
                  (let [vm (timer.view-model (+ now day) now "Resets in")]
                    (assert.are.equal "Resets in" vm.label))))
            (it "rejects non-number inputs"
                (fn []
                  (assert.has_error #(timer.view-model :soon now))
                  (assert.has_error #(timer.view-model now :now))))))

(describe :lockout-timer-pool-smoke
          (fn []
            (it "acquire! -> start! -> stop! -> release! does not raise"
                (fn []
                  (let [f (timer.acquire! _G.UIParent)
                        now-fn (fn [] now)]
                    (assert.is_truthy f)
                    (timer.start! f (+ now day) now-fn "Resets in")
                    (timer.stop! f)
                    (assert.is_nil (timer.release! f)))))))
