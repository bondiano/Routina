;; planner.fnl -- imperative shell: gather the live client into a route input.
;;
;; The bridge from the WoW client to the pure planner. It reads everything
;; impure (src/core/wow.fnl APIs + SavedVariables options), packs it into the
;; raw snapshot src/domain/ctx.fnl expects, and returns the (player, ctx) pair
;; src/domain/route.fnl scores. All purity lives downstream; this module is the
;; one place that mixes live client reads with the domain.
;;
;; Degrades gracefully: during loading screens the WoW APIs hand back nil, so
;; route-input returns {:ok false} and the caller (src/ui/tabs/weekly.fnl) shows
;; an empty plan rather than erroring. See docs/ROADMAP.md Phase 2 §5.

(local Routina (or _G.Routina {}))
(local wow (or Routina.wow (require :src.core.wow)))
(local ctx (or Routina.ctx (require :src.domain.ctx)))
(local events (or Routina.events (require :src.core.events)))

(local M {})

;; --- Helpers (private) -----------------------------------------------------

(fn route-options []
  "Route tuning from SavedVariables (spec override, phase, weights,
   competitors). Empty until the DB is initialized / the options UI writes it."
  (or (?. Routina :addon :db :char :preferences :route) {}))

(fn char-goals []
  "The player's persisted weekly goals (db.char.goals); ctx.build validates
   and drops corrupt rows. Empty until the goal editor writes them."
  (or (?. Routina :addon :db :char :goals) []))

(fn profile-customs []
  "The player's authored activities (db.profile.custom-activities); ctx.build
   validates and drops corrupt rows. Empty until the editor writes them."
  (or (?. Routina :addon :db :profile :custom-activities) []))

(fn char-plan-edits []
  "The player's persisted pins/skips (db.char.plan-edits); ctx.build
   normalizes and drops corrupt entries. Empty until a card action writes it."
  (or (?. Routina :addon :db :char :plan-edits) {}))

(fn profile-custom-chains []
  "The player's authored chains (db.profile.custom-chains); ctx.build
   validates and drops corrupt rows. Empty until the constructor writes them."
  (or (?. Routina :addon :db :profile :custom-chains) []))

;; --- Public API ------------------------------------------------------------

(lambda M.route-input []
  "Gather the live client snapshot and assemble (player, ctx) for the planner.
   Impure -- reads WoW APIs and SavedVariables; never throws (a mid-load nil or
   a validation miss comes back as {:ok false}).
   Domain:  (none)
   Returns: {:ok true :player schemas.Player :ctx schemas.RouteContext
             :advice {attune-slug advice-text}
             :chain-advice [chain-advice-row ...]} | {:ok false :err string}"
  (let [info (wow.player-info)
        level (wow.player-level)]
    (if (or (not info) (not info.class) (= info.class :unknown) (not level))
        {:ok false :err "player identity unavailable (loading?)"}
        (let [saved (wow.saved-instances)
              snapshot {:class info.class
                        : level
                        :now (wow.now)
                        :talent-points (wow.talent-points)
                        :owned-item-ids (wow.owned-item-ids)
                        :raw-lockouts (if saved.ok saved.lockouts [])
                        :owner (.. (tostring info.name) "-"
                                   (tostring info.realm))
                        :quest-completed? wow.quest-completed?
                        :faction-standing wow.faction-standing
                        :chain-progress (events.chain-progress)
                        :goals (char-goals)
                        :custom-activities (profile-customs)
                        :plan-edits (char-plan-edits)
                        :custom-chains (profile-custom-chains)
                        :money (wow.player-money)
                        :badge-count (wow.badge-count)
                        :reset-at (events.reset-at)
                        :yield-history (events.yield-history)
                        :options (route-options)}
              (ok? built) (pcall ctx.build snapshot)]
          (if ok?
              {:ok true
               :player built.player
               :ctx built.ctx
               :advice built.advice
               :chain-advice built.chain-advice}
              {:ok false :err (tostring built)})))))

;; --- Register into the addon namespace -------------------------------------
;;
;; Dual-mode: in-game, .toc loads build/core/planner.lua after wow + ctx. In
;; tests, consumers fall through to `(require :src.core.planner)`.

(set _G.Routina Routina)
(set Routina.planner M)

M
