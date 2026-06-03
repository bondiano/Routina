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

(describe :options-table
          (fn []
            (it "exposes spec, phase, competitors, weights and attunement groups"
                (fn []
                  (let [t (build {} (fn []))]
                    (assert.are.equal :select (. t.args.spec :type))
                    (assert.are.equal :range (. t.args.phase :type))
                    (assert.are.equal 1 (. t.args.phase :min))
                    (assert.are.equal 5 (. t.args.phase :max))
                    (assert.are.equal :range (. t.args.competitors :type))
                    (assert.are.equal :group (. t.args.weights :type))
                    (assert.are.equal :group (. t.args.attune :type)))))
            (it "offers an auto sentinel plus each class spec in the dropdown"
                (fn []
                  (let [t (build {} (fn []))
                        vals (. t.args.spec :values)]
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
                  (let [t (build {:phase 4 :default-competitors 3} (fn []))]
                    (assert.are.equal 4 ((. t.args.phase :get) nil))
                    (assert.are.equal 3 ((. t.args.competitors :get) nil)))))
            (it "writes phase and fires on-change via :set"
                (fn []
                  (let [db {}
                        hits {:n 0}
                        t (build db (fn [] (set hits.n (+ hits.n 1))))]
                    ((. t.args.phase :set) nil 2)
                    (assert.are.equal 2 db.phase)
                    (assert.are.equal 1 hits.n))))
            (it "stores a spec override, and :auto clears it"
                (fn []
                  (let [db {}
                        t (build db (fn []))]
                    ((. t.args.spec :set) nil :feral-dps)
                    (assert.are.equal :feral-dps db.spec)
                    ((. t.args.spec :set) nil :auto)
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
                    (assert.is_true (. db.attune :kara-key :gate?)))))))
