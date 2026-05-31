;; validate.fnl -- pure runtime validation over declarative schemas.
;;
;; PURE domain module: no WoW API, no I/O, no mutation of inputs. Walks a value
;; against a schema (from src/domain/schemas.fnl) and reports every mismatch
;; with a dotted path, so callers get one actionable error string.
;;
;; Use at MODULE BOUNDARIES only -- WoW API -> domain, SavedVariables load,
;; user input. Never inside hot loops (validate once at entry). See
;; .claude/examples/07-type-contracts.fnl PART 4.

(local Routina (or _G.Routina {}))
(local default-registry (or Routina.schemas (require :src.domain.schemas)))

(local M {})

;; --- Field-type predicates (private) ---------------------------------------

(fn op? [ftype]
  "True if ftype is an [op ...] vector (e.g. [:enum ...]) vs a record table.
   Record schemas are string-keyed, so index 1 is nil; ops put the op there."
  (and (= (type ftype) :table) (not= nil (. ftype 1))))

(fn optional? [ftype]
  "True if ftype is an [:optional ...] wrapper."
  (and (op? ftype) (= (. ftype 1) :optional)))

(fn resolve [registry name]
  "Look a schema up by name, erroring on a dangling [:ref ...]."
  (or (. registry name) (error (.. "validate: unknown schema ref :"
                                   (tostring name)))))

(local scalar-checkers
       {:string #(= (type $) :string)
        :number #(= (type $) :number)
        :boolean #(= (type $) :boolean)
        :integer #(and (= (type $) :number) (= $ (math.floor $)))})

;; --- Recursive checker (private) -------------------------------------------
;;
;; Each checker appends to a shared local `errors` accumulator (a fresh table
;; per top-level call -- inputs are never mutated) and returns it. `check-into`
;; is forward-declared so the sub-checkers can recurse through it.

(var check-into nil)

(fn check-enum [ftype value path errors]
  (var found? false)
  (for [i 2 (length ftype)]
    (when (= value (. ftype i)) (set found? true)))
  (when (not found?)
    (let [opts (fcollect [i 2 (length ftype)] (tostring (. ftype i)))]
      (table.insert errors
                    (.. path ": " (tostring value) " not in enum {"
                        (table.concat opts ", ") "}"))))
  errors)

(fn check-list [ftype value registry path errors]
  (if (not= (type value) :table)
      (table.insert errors (.. path ": expected list, got " (type value)))
      (each [i v (ipairs value)]
        (check-into (. ftype 2) v registry (.. path "[" i "]") errors)))
  errors)

(fn check-map [ftype value registry path errors]
  (if (not= (type value) :table)
      (table.insert errors (.. path ": expected map, got " (type value)))
      (each [k v (pairs value)]
        (check-into (. ftype 2) k registry (.. path ".<key " (tostring k) ">")
                    errors)
        (check-into (. ftype 3) v registry (.. path "." (tostring k)) errors)))
  errors)

(fn check-record [schema value registry path errors]
  (if (not= (type value) :table)
      (table.insert errors (.. path ": expected table, got " (type value)))
      (each [field ftype (pairs schema)]
        (let [fv (. value field)
              fpath (if (= path "") field (.. path "." field))]
          (if (and (= fv nil) (not (optional? ftype)))
              (table.insert errors (.. fpath ": missing required field"))
              (check-into ftype fv registry fpath errors)))))
  errors)

(set check-into (fn [ftype value registry path errors]
                  "Dispatch one (ftype value) pair, appending mismatches to errors."
                  (if (= (type ftype) :string)
                      (let [ok? (. scalar-checkers ftype)]
                        (if (not ok?)
                            (table.insert errors
                                          (.. path ": unknown scalar type :"
                                              ftype))
                            (when (not (ok? value))
                              (table.insert errors
                                            (.. path ": expected " ftype
                                                ", got " (type value))))))
                      (op? ftype)
                      (case (. ftype 1)
                        :enum (check-enum ftype value path errors)
                        :list (check-list ftype value registry path errors)
                        :map (check-map ftype value registry path errors)
                        :ref (check-into (resolve registry (. ftype 2)) value
                                         registry path errors)
                        :optional (when (not= value nil)
                                    (check-into (. ftype 2) value registry path
                                                errors))
                        other (table.insert errors
                                            (.. path ": unknown schema op :"
                                                (tostring other))))
                      (= (type ftype) :table)
                      (check-record ftype value registry path errors)
                      (table.insert errors (.. path ": malformed schema node")))
                  errors))

;; --- Best-effort coercion (private) ----------------------------------------

(var coerce-into nil)

(fn coerce-scalar [ftype value]
  "Nudge a scalar toward its declared type without inventing data.
   Numeric strings -> numbers; non-integral numbers -> floored for :integer.
   Anything that cannot be coerced is returned unchanged for `check` to flag."
  (case ftype
    :integer (let [n (tonumber value)] (if n (math.floor n) value))
    :number (or (tonumber value) value)
    _ value))

(set coerce-into (fn [ftype value registry]
                   (if (= (type ftype) :string)
                       (coerce-scalar ftype value)
                       (op? ftype)
                       (case (. ftype 1)
                         :ref (coerce-into (resolve registry (. ftype 2)) value
                                           registry)
                         :optional (if (= value nil) nil
                                       (coerce-into (. ftype 2) value registry))
                         :list (if (= (type value) :table)
                                   (icollect [_ v (ipairs value)]
                                     (coerce-into (. ftype 2) v registry))
                                   value)
                         :map (if (= (type value) :table)
                                  (collect [k v (pairs value)]
                                    k
                                    (coerce-into (. ftype 3) v registry))
                                  value)
                         _ value)
                       (= (type ftype) :table)
                       (if (= (type value) :table)
                           (collect [field ftype* (pairs ftype)]
                             field
                             (coerce-into ftype* (. value field) registry))
                           value)
                       value)))

;; --- Public API ------------------------------------------------------------

(lambda M.check [schema value ?registry]
  "Validate value against schema, collecting every mismatch.
   Domain:  schema   : a schema node (record table or [op ...] vector)
            value    : any -- the value to check
            ?registry: schema table for resolving [:ref ...] (default: schemas)
   Returns: {:ok boolean :errors [string]} -- :ok true iff :errors is empty,
            each error a dotted-path message (e.g. \"encounters[2].name: ...\")."
  (let [registry (or ?registry default-registry)
        errors (check-into schema value registry "" [])]
    {:ok (= (length errors) 0) : errors}))

(lambda M.assert! [schema value ?label ?registry]
  "Validate value, throwing a single joined error if invalid.
   Domain:  schema   : a schema node
            value    : any
            ?label   : prefix for the error message (default \"validation failed\")
            ?registry: schema table for [:ref ...] resolution
   Returns: value unchanged when valid.
   Errors:  raises with \"<label>: <err>; <err>; ...\" when invalid."
  (let [result (M.check schema value ?registry)]
    (when (not result.ok)
      (error (.. (or ?label "validation failed") ": "
                 (table.concat result.errors "; "))))
    value))

(lambda M.coerce [schema value ?registry]
  "Best-effort coerce value to satisfy schema, then validate the result.
   Only widens scalars (numeric string -> number, float -> int for :integer);
   never fabricates missing fields. Pure -- returns a fresh value, input intact.
   Domain:  schema   : a schema node
            value    : any
            ?registry: schema table for [:ref ...] resolution
   Returns: {:ok boolean :value any :errors [string]} -- :value is the coerced
            result whether or not it ultimately validates."
  (let [registry (or ?registry default-registry)
        coerced (coerce-into schema value registry)
        result (M.check schema coerced registry)]
    {:ok result.ok :value coerced :errors result.errors}))

;; --- Register into the addon namespace -------------------------------------
;;
;; Dual-mode: in-game, .toc load order populates `_G.Routina.validate` after
;; schemas. In tests, consumers fall through to `(require :src.domain.validate)`.

(set _G.Routina Routina)
(set Routina.validate M)

M
