;; schemas_spec.fnl -- the schema table is data; these tests keep it honest.
;;
;; Pure data module, so the meaningful checks are structural:
;;   - every declared schema is a non-empty record table
;;   - every [:ref :Name] points at a schema that actually exists
;;   - every enum lists at least two options
;; A dangling ref or a typo'd enum is the kind of bug validate.fnl would only
;; surface at a call site; catching it here keeps schemas trustworthy.

(local schemas (require :src.domain.schemas))
(local validate (require :src.domain.validate))

(fn op? [ftype]
  (and (= (type ftype) :table) (not= nil (. ftype 1))))

(fn walk [ftype visit]
  "Depth-first visit of every node in a field-type tree."
  (visit ftype)
  (when (= (type ftype) :table)
    (if (op? ftype)
        (case (. ftype 1)
          :list (walk (. ftype 2) visit)
          :map (do
                 (walk (. ftype 2) visit)
                 (walk (. ftype 3) visit))
          :optional (walk (. ftype 2) visit)
          _ nil)
        (each [_ child (pairs ftype)]
          (walk child visit)))))

(describe :schemas
          (fn []
            (it "declares each schema as a non-empty record table"
                (fn []
                  (each [name schema (pairs schemas)]
                    (assert.are.equal :table (type schema)
                                      (.. name " must be a table"))
                    (assert.is_nil (. schema 1)
                                   (.. name " must be a record, not a vector"))
                    (assert.is_true (not= nil (next schema))
                                    (.. name " must not be empty")))))
            (it "resolves every [:ref :Name] to a declared schema"
                (fn []
                  (each [name schema (pairs schemas)]
                    (walk schema
                          (fn [node]
                            (when (and (op? node) (= (. node 1) :ref))
                              (let [target (. node 2)]
                                (assert.is_true (not= nil (. schemas target))
                                                (.. name
                                                    " refs unknown schema :"
                                                    (tostring target))))))))))
            (it "gives every [:enum ...] at least two options"
                (fn []
                  (each [_ schema (pairs schemas)]
                    (walk schema
                          (fn [node]
                            (when (and (op? node) (= (. node 1) :enum))
                              (assert.is_true (>= (length node) 3))))))))
            (it "exposes the shapes the planner and BiS layers depend on"
                (fn []
                  (each [_ name (ipairs [:Item
                                         :Encounter
                                         :Lockout
                                         :LockoutView
                                         :TargetItem
                                         :Activity
                                         :Player
                                         :ActivityDef
                                         :ActivityRequirements
                                         :RepRequirement
                                         :BisItem
                                         :DropEntry
                                         :RouteContext
                                         :ChainStep
                                         :ChainDef
                                         :ChainProgress])]
                    (assert.is_true (not= nil (. schemas name))
                                    (.. "missing schema :" name)))))
            (it "accepts a hand-built ChainDef fixture through validate.check"
                (fn []
                  (let [chain {:id :kara-key
                               :name "The Master's Key"
                               :kind :attunement
                               :expac "The Burning Crusade"
                               :faction :Both
                               :steps [{:id :1
                                        :type :quest
                                        :label "Arcane Disturbances"
                                        :quest-id 9824
                                        :stage 1
                                        :follows []
                                        :follows-mode :all}
                                       {:id :2
                                        :type :kill
                                        :label "Shadow Labyrinth"
                                        :stage 2
                                        :follows [:1]
                                        :follows-mode :all}]}
                        r (validate.check schemas.ChainDef chain)]
                    (assert.is_true r.ok (table.concat (or r.errors []) "; ")))))))
