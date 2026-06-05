;; competition_spec.fnl -- tests for the by-role loot-competition model.
;;
;; The item -> contending-roles index is derived from the generated BiS
;; catalog, so most assertions are structural: the spec->role table covers
;; every catalog pair (drift guard against a growing manifest), the index
;; agrees with a per-test recount, and competitors-for-item respects its
;; >= 1 contract under generated compositions. No WoW API, no clock.

(local competition (require :src.domain.competition))
(local catalog (require :src.domain.bis-catalog))
(local gen (require :spec.helpers.gen))

;; A caster cloak from bis/mage-fire.fnl -- a stable catalog fixture.
(local ruby-drape 28766)
(local off-catalog-id 1)

(fn recount-roles [item-id]
  "Independent oracle: fold the raw catalog for one item's roles."
  (let [found {}]
    (each [_ e (ipairs (catalog.all))]
      (when (= e.item.id item-id)
        (case (competition.role-for-spec e.class e.spec)
          role (tset found role true))))
    found))

(fn roles-of [role-set]
  (icollect [r _ (pairs role-set)] r))

(fn composition-of [rng]
  (collect [_ r (ipairs competition.roles)]
    (values r (gen.int-in rng 0 10))))

(describe :competition
          (fn []
            (describe :role-for-spec
                      (fn []
                        (it "maps every catalog (class, spec) pair to a role (drift guard)"
                            (fn []
                              (each [_ e (ipairs (catalog.all))]
                                (assert.is_not_nil (competition.role-for-spec e.class
                                                                              e.spec)
                                                   (.. "unmapped spec "
                                                       (tostring e.class) "-"
                                                       (tostring e.spec))))))
                        (it "returns nil for a pair outside the taxonomy"
                            (fn []
                              (assert.is_nil (competition.role-for-spec :mage
                                                                        :unholy))))))
            (describe :contending-roles
                      (fn []
                        (it "marks a known caster cloak as caster-contended"
                            (fn []
                              (assert.is_true (. (competition.contending-roles ruby-drape)
                                                 :caster))))
                        (it "agrees with a raw catalog recount, including shared items"
                            (fn []
                              ;; Find an item contended by >= 2 roles so the union path is
                              ;; exercised, then assert the index matches the oracle.
                              (var shared nil)
                              (each [_ e (ipairs (catalog.all)) &until shared]
                                (when (> (length (roles-of (recount-roles e.item.id)))
                                         1)
                                  (set shared e.item.id)))
                              (assert.is_not_nil shared
                                                 "no cross-role item in the catalog?")
                              (assert.are.same (recount-roles shared)
                                               (competition.contending-roles shared))))
                        (it "returns {} for an off-catalog item"
                            (fn []
                              (assert.are.same {}
                                               (competition.contending-roles off-catalog-id))))
                        (it "returns a fresh table the caller may mutate safely"
                            (fn []
                              (let [first (competition.contending-roles ruby-drape)]
                                (tset first :sentinel true)
                                (assert.is_nil (. (competition.contending-roles ruby-drape)
                                                  :sentinel)))))))
            (describe :competitors-for-item
                      (fn []
                        (it "sums the contending roles' headcounts"
                            (fn []
                              (let [composition {:tank 3
                                                 :healer 6
                                                 :melee 7
                                                 :ranged 4
                                                 :caster 5}
                                    expected (accumulate [sum 0 r _ (pairs (competition.contending-roles ruby-drape))]
                                               (+ sum (. composition r)))]
                                (assert.are.equal expected
                                                  (competition.competitors-for-item ruby-drape
                                                                                    composition)))))
                        (it "floors at 1 for an off-catalog item"
                            (fn []
                              (assert.are.equal 1
                                                (competition.competitors-for-item off-catalog-id
                                                                                  {:caster 25}))))
                        (it "floors at 1 under an all-zero composition"
                            (fn []
                              (assert.are.equal 1
                                                (competition.competitors-for-item ruby-drape
                                                                                  {:tank 0
                                                                                   :healer 0
                                                                                   :melee 0
                                                                                   :ranged 0
                                                                                   :caster 0}))))
                        (it "passes fractional (group-size-scaled) headcounts through"
                            (fn []
                              (let [pool (competition.competitors-for-item ruby-drape
                                                                           {:caster 2.5})]
                                (assert.is_true (>= pool 2.5)))))
                        (it "property: always >= 1 for random items and compositions"
                            (fn []
                              (let [rng (gen.make-rng 1337)
                                    items (icollect [_ e (ipairs (catalog.all))]
                                            e.item.id)]
                                (for [_ 1 200]
                                  (let [item-id (gen.sample rng items)
                                        pool (competition.competitors-for-item item-id
                                                                               (composition-of rng))]
                                    (assert.is_true (>= pool 1)))))))
                        (it "property: raising a contending role never lowers the pool;
             raising a non-contending role never changes it"
                            (fn []
                              (let [rng (gen.make-rng 4711)
                                    items (icollect [_ e (ipairs (catalog.all))]
                                            e.item.id)]
                                (for [_ 1 200]
                                  (let [item-id (gen.sample rng items)
                                        contending (competition.contending-roles item-id)
                                        composition (composition-of rng)
                                        role (gen.sample rng competition.roles)
                                        base (competition.competitors-for-item item-id
                                                                               composition)
                                        bumped (collect [r n (pairs composition)]
                                                 (values r
                                                         (if (= r role) (+ n 3)
                                                             n)))
                                        after (competition.competitors-for-item item-id
                                                                                bumped)]
                                    (if (. contending role)
                                        (assert.is_true (>= after base))
                                        (assert.are.equal base after)))))))))
            (describe "data exports"
                      (fn []
                        (it "exposes the five roles in display order"
                            (fn []
                              (assert.are.same [:tank
                                                :healer
                                                :melee
                                                :ranged
                                                :caster]
                                               competition.roles)))
                        (it "ships a default composition covering every role, summing to 25"
                            (fn []
                              (var sum 0)
                              (each [_ r (ipairs competition.roles)]
                                (let [n (. competition.default-composition r)]
                                  (assert.is_not_nil n
                                                     (.. "missing role "
                                                         (tostring r)))
                                  (set sum (+ sum n))))
                              (assert.are.equal 25 sum)))))))
