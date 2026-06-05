;; saved-vars.fnl -- AceDB defaults and the pure schema-migration runner.
;;
;; The DB shape is declared once here as `defaults`; AceDB:New (the only impure
;; part) lives in src/core/ace.fnl and merges these on load. Migrations are a
;; pure reduction so they are busted-testable without touching AceDB:
;; given a `:global` table and an ordered migration list, fast-forward it to the
;; latest version. Bump `:global.version` and append a migration for EVERY schema
;; change (CLAUDE.md: SavedVariables migration is mandatory).

(local Routina (or _G.Routina {}))

(local M {})

;; --- DB defaults -----------------------------------------------------------
;;
;; :global is account-wide, :char is per-character, :profile follows the
;; player's AceDB profile (the Profiles options sub-panel). `version` lives in
;; :global and is what `migrate` fast-forwards. Kept lean for Phase 1 --
;; options and weekly-state grow as later phases need them.

(local defaults {:global {:version 6 :options {:log-level :info}}
                 :profile {:custom-activities [] :custom-chains []}
                 :char {:weekly-state {:reset-time 0 :lockouts {}}
                        :history {:runs {} :drops {} :yields {}}
                        :chains {}
                        :goals {}
                        :plan-edits {:pins [] :skips {}}
                        :preferences {}}})

(set M.defaults defaults)

;; --- Migrations ------------------------------------------------------------
;;
;; Each entry is {:to integer :apply (fn [db] db)} and runs only when
;; :to is newer than the stored version. `:to` must match the
;; `:global.version` you bump `defaults` to.

(local migrations [;; v2 (Phase 6): db.char gains :chains ({chain-id ->
                   ;; ChainProgress}). AceDB merges the new :char default on
                   ;; load, and chains.normalize is defensive about whatever
                   ;; it finds, so no :global data moves -- the entry anchors
                   ;; the mandatory version bump for the schema change.
                   {:to 2 :apply (fn [db] db)}
                   ;; v3 (Phase 7): db.char gains :goals ([GoalDef]) and
                   ;; history gains :yields ({activity-id -> tally}). AceDB
                   ;; merges the new defaults; goals.normalize and
                   ;; history.normalize defensively coerce whatever a v2 DB
                   ;; holds, so again no data moves -- the entry anchors the
                   ;; version bump.
                   {:to 3 :apply (fn [db] db)}
                   ;; v4 (Phase 8): db.profile gains :custom-activities
                   ;; ([CustomActivity]). AceDB merges the new :profile
                   ;; default; custom-activities.normalize defensively coerces
                   ;; whatever a v3 DB holds, so no data moves -- the entry
                   ;; anchors the version bump.
                   {:to 4 :apply (fn [db] db)}
                   ;; v5 (Phase 8 §2): db.char gains :plan-edits (PlanEdits --
                   ;; pins/skips). AceDB merges the new :char default;
                   ;; plan-edits.normalize defensively coerces whatever a v4
                   ;; DB holds, so no data moves -- the entry anchors the
                   ;; version bump.
                   {:to 5 :apply (fn [db] db)}
                   ;; v6 (Phase 8 §3): db.profile gains :custom-chains
                   ;; ([CustomChain]). AceDB merges the new :profile default;
                   ;; custom-chains.normalize defensively coerces whatever a
                   ;; v5 DB holds, so no data moves -- the entry anchors the
                   ;; version bump.
                   {:to 6 :apply (fn [db] db)}])

(set M.migrations migrations)

;; --- Pure migration runner -------------------------------------------------

(lambda M.migrate [db migration-list]
  "Fast-forward a :global DB table through any newer migrations.
   Pure and idempotent -- re-running with the same list is a no-op once the
   stored version has caught up.
   Domain:  db             : the AceDB :global table (has :version integer)
            migration-list : [{:to integer :apply (fn [db] db)}],
                             ordered ascending by :to
   Returns: the migrated :global table with :version set to the highest :to
            applied (unchanged when nothing newer exists)."
  (accumulate [acc db _ m (ipairs migration-list)]
    (if (> m.to (or acc.version 0))
        (let [migrated (m.apply acc)]
          (set migrated.version m.to)
          migrated)
        acc)))

;; --- Register into the addon namespace -------------------------------------

(set _G.Routina Routina)
(set Routina.saved-vars M)

M
