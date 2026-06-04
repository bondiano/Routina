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
;; :global is account-wide, :char is per-character. `version` lives in :global
;; and is what `migrate` fast-forwards. Kept lean for Phase 1 -- options and
;; weekly-state grow as later phases need them.

(local defaults {:global {:version 1 :options {:log-level :info}}
                 :char {:weekly-state {:reset-time 0 :lockouts {}}
                        :history {:runs {} :drops {}}
                        :preferences {}}})

(set M.defaults defaults)

;; --- Migrations ------------------------------------------------------------
;;
;; Each entry is {:to integer :apply (fn [db] db)} and runs only when
;; :to is newer than the stored version. Empty until the first schema change;
;; `:to` must match the `:global.version` you bump `defaults` to.

(local migrations [])

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
