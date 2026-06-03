;; planner_spec.fnl -- the WoW-client -> route-input shell, against the mock.
;;
;; planner.fnl is glue, so these check the observable contract: a ready client
;; yields {:ok true} with a schema-valid (player, ctx) reflecting live reads,
;; and a mid-load client (no level) yields {:ok false} instead of throwing.

(local planner (require :src.core.planner))
(local mock (require :spec.mocks.wow-api))

(describe :planner (fn []
                     (before_each (fn [] (mock.reset!)))
                     (it "builds a valid route input from the live client"
                         (fn []
                           ;; mock defaults: UnitClass -> PRIEST, level 70, no talents
                           (let [r (planner.route-input)]
                             (assert.is_true r.ok)
                             (assert.are.equal :priest r.ctx.class)
                             ;; untalented priest -> tab 1 -> :holy
                             (assert.are.equal :holy r.ctx.spec)
                             ;; options absent -> ctx.fnl default-phase
                             (assert.are.equal 2 r.ctx.phase)
                             (assert.are.equal 70 r.player.level))))
                     (it "reflects equipped gear in owned-items"
                         (fn []
                           (mock.set-equipped! {1 28745})
                           (let [r (planner.route-input)]
                             (assert.is_true (. r.ctx.owned-items 28745)))))
                     (it "detects spec from the dominant talent tree"
                         (fn []
                           ;; priest tab 3 (Shadow) dominant
                           (mock.set-talent-points! [10 0 41])
                           (let [r (planner.route-input)]
                             (assert.are.equal :shadow r.ctx.spec))))
                     (it "returns {:ok false} when identity is unavailable"
                         (fn []
                           (mock.set-player-level! nil)
                           (let [r (planner.route-input)]
                             (assert.is_false r.ok))))))
