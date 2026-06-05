;; options_spec.fnl -- the PURE AceConfig options-table builder.
;;
;; Only M.options-table is exercised (no Ace3 libs needed): structure, ranges,
;; and that the get/set closures read/write the route-options table and fire the
;; on-change hook. register!/open! are impure shell (wowUnit / smoke only).

(local options (require :src.ui.options))

(fn build [db on-change]
  (options.options-table {: db
                          :specs [{:value :feral-dps :text :Feral}
                                  {:value :restoration :text :Resto}]
                          : on-change}))

(fn general [t]
  (. t.args.general :args))

(describe :options-table
          (fn []
            (it "splits into general, weights and attunement sub-groups"
                (fn []
                  (let [t (build {} (fn []))]
                    (assert.are.equal :group (. t.args.general :type))
                    (assert.are.equal :group (. t.args.weights :type))
                    (assert.are.equal :group (. t.args.attune :type))
                    (assert.are.equal :group (. t.args.custom :type)))))
            (it "keeps the sub-groups non-inline so each maps to a Bliz sub-panel"
                (fn []
                  (let [t (build {} (fn []))]
                    (assert.is_nil (. t.args.general :inline))
                    (assert.is_nil (. t.args.weights :inline))
                    (assert.is_nil (. t.args.attune :inline)))))
            (it "exposes spec, phase and competitors in the general group"
                (fn []
                  (let [g (general (build {} (fn [])))]
                    (assert.are.equal :select (. g.spec :type))
                    (assert.are.equal :range (. g.phase :type))
                    (assert.are.equal 1 (. g.phase :min))
                    (assert.are.equal 5 (. g.phase :max))
                    (assert.are.equal :range (. g.competitors :type)))))
            (it "offers an auto sentinel plus each class spec in the dropdown"
                (fn []
                  (let [g (general (build {} (fn [])))
                        vals (. g.spec :values)]
                    (assert.is_truthy (. vals :auto))
                    (assert.is_truthy (. vals :feral-dps))
                    (assert.is_truthy (. vals :restoration)))))
            (it "has one weight slider per gear slot"
                (fn []
                  (let [t (build {} (fn []))
                        n (accumulate [c 0 _ _ (pairs t.args.weights.args)]
                            (+ c 1))]
                    (assert.are.equal 17 n))))
            (it "reads current values back through :get"
                (fn []
                  (let [g (general (build {:phase 4 :default-competitors 3}
                                          (fn [])))]
                    (assert.are.equal 4 ((. g.phase :get) nil))
                    (assert.are.equal 3 ((. g.competitors :get) nil)))))
            (it "exposes a projection seed slider, default 1, written via :set"
                (fn []
                  (let [db {}
                        hits {:n 0}
                        g (general (build db (fn [] (set hits.n (+ hits.n 1)))))]
                    (assert.are.equal :range (. g.seed :type))
                    (assert.are.equal 1 ((. g.seed :get) nil))
                    ((. g.seed :set) nil 4242)
                    (assert.are.equal 4242 db.seed)
                    (assert.are.equal 1 hits.n))))
            (it "exposes an include-classic toggle, off by default, written via :set"
                (fn []
                  (let [db {}
                        g (general (build db (fn [])))]
                    (assert.are.equal :toggle (. g.include-classic :type))
                    (assert.is_false ((. g.include-classic :get) nil))
                    ((. g.include-classic :set) nil true)
                    (assert.is_true db.include-classic?))))
            (it "exposes a luck-tracking toggle, off by default, written via :set"
                (fn []
                  (let [db {}
                        g (general (build db (fn [])))]
                    (assert.are.equal :toggle (. g.track-luck :type))
                    (assert.is_false ((. g.track-luck :get) nil))
                    ((. g.track-luck :set) nil true)
                    (assert.is_true db.track-luck?))))
            (it "writes phase and fires on-change via :set"
                (fn []
                  (let [db {}
                        hits {:n 0}
                        g (general (build db (fn [] (set hits.n (+ hits.n 1)))))]
                    ((. g.phase :set) nil 2)
                    (assert.are.equal 2 db.phase)
                    (assert.are.equal 1 hits.n))))
            (it "stores a spec override, and :auto clears it"
                (fn []
                  (let [db {}
                        g (general (build db (fn [])))]
                    ((. g.spec :set) nil :feral-dps)
                    (assert.are.equal :feral-dps db.spec)
                    ((. g.spec :set) nil :auto)
                    (assert.is_nil db.spec))))
            (it "writes a slot weight into the nested weights table"
                (fn []
                  (let [db {}
                        t (build db (fn []))
                        feet (. t.args.weights.args :feet)]
                    ((. feet :set) nil 5)
                    (assert.are.equal 5 (. db.weights :feet)))))
            (it "writes an attunement advise/gate toggle"
                (fn []
                  (let [db {}
                        t (build db (fn []))
                        advise (. t.args.attune.args :kara-key-advise)
                        gate (. t.args.attune.args :kara-key-gate)]
                    ((. advise :set) nil true)
                    ((. gate :set) nil true)
                    (assert.is_true (. db.attune :kara-key :advise?))
                    (assert.is_true (. db.attune :kara-key :gate?)))))
            (it "gives attunement toggles full width so labels aren't truncated"
                (fn []
                  (let [t (build {} (fn []))]
                    (each [_ toggle (pairs t.args.attune.args)]
                      (assert.are.equal :full (. toggle :width))))))
            (it "exposes a non-inline raid-composition group with a slider per role"
                (fn []
                  (let [t (build {} (fn []))
                        comp (. t.args :composition)]
                    (assert.are.equal :group (. comp :type))
                    (assert.is_nil (. comp :inline))
                    (each [_ role (ipairs [:tank
                                           :healer
                                           :melee
                                           :ranged
                                           :caster])]
                      (assert.are.equal :range
                                        (. comp.args (tostring role) :type))))))
            (it "shows the default composition while nothing is stored"
                (fn []
                  (let [db {}
                        t (build db (fn []))
                        tank (. t.args.composition.args :tank)]
                    (assert.are.equal 3 ((. tank :get) nil))
                    ;; reading must not opt the player in
                    (assert.is_nil db.composition))))
            (it "materializes the full default composition on the first :set"
                (fn []
                  (let [db {}
                        hits {:n 0}
                        t (build db (fn [] (set hits.n (+ hits.n 1))))
                        caster (. t.args.composition.args :caster)]
                    ((. caster :set) nil 9)
                    (assert.are.equal 9 (. db.composition :caster))
                    ;; the untouched roles are stored too, so what the panel
                    ;; shows is exactly what the planner uses
                    (assert.are.equal 3 (. db.composition :tank))
                    (assert.are.equal 6 (. db.composition :healer))
                    (assert.are.equal 1 hits.n))))
            (it "later :sets only update the touched role"
                (fn []
                  (let [db {:composition {:tank 1
                                          :healer 1
                                          :melee 1
                                          :ranged 1
                                          :caster 1}}
                        t (build db (fn []))
                        melee (. t.args.composition.args :melee)]
                    ((. melee :set) nil 7)
                    (assert.are.equal 7 (. db.composition :melee))
                    (assert.are.equal 1 (. db.composition :tank)))))))
