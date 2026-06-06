;; ace.fnl -- AceAddon entry point. Owns the lifecycle, the DB, slash commands
;; and event wiring. Replaces the pre-Ace3 src/core/main.fnl.
;;
;; Loaded last (.toc), after Libs and every build/* module. Only AceAddon is
;; resolved at load time (NewAddon must run to register the addon); AceDB,
;; AceEvent and AceConsole are resolved lazily inside the lifecycle methods so
;; the pure modules stay free of LibStub. See .claude/examples/04-ace-addon-module.fnl.
;;
;; OnInitialize: SavedVariables + migrations + logger + slash commands.
;; OnEnable:     event dispatcher (frames stay lazy until first /routina).
;; OnDisable:    tear down events.

(local addon-name :Routina)
(local LibStub _G.LibStub)

(local Routina (or _G.Routina {}))
(local events (or Routina.events (require :src.core.events)))
(local saved-vars (or Routina.saved-vars (require :src.core.saved-vars)))
(local planner (or Routina.planner (require :src.core.planner)))
(local route (or Routina.route (require :src.domain.route)))
(local format (or Routina.format (require :src.ui.format)))
(local root (or Routina.root (require :src.ui.root)))
(local options (or Routina.options (require :src.ui.options)))
(local theme (or Routina.theme (require :src.ui.theme)))

(local log-levels {:debug 1 :info 2 :warn 3 :error 4})

;; --- Logger factory (pure; exported for test) ------------------------------

(fn make-logger [level-getter]
  "Build a logger whose debug/info/warn/error calls are gated by the current
   log level (read fresh each call via level-getter, so option changes apply
   immediately). Routes to the WoW chat frame via print."
  (let [emit (fn [tag msg]
               (let [current (or (. log-levels (level-getter)) 2)]
                 (when (>= (. log-levels tag) current)
                   (print (.. "|cFF00FFFF[Routina " tag "]|r " msg)))))]
    {:debug (fn [_ msg] (emit :debug msg))
     :info (fn [_ msg] (emit :info msg))
     :warn (fn [_ msg] (emit :warn msg))
     :error (fn [_ msg] (emit :error msg))}))

;; --- AceAddon registration (load-time) -------------------------------------

(local AceAddon (LibStub :AceAddon-3.0))
(local addon (AceAddon:NewAddon addon-name :AceConsole-3.0 :AceTimer-3.0))

;; Debounce: gear swaps and bag updates fire in bursts, so coalesce refresh
;; requests into one repaint ~0.2s later. Falls back to an immediate refresh if
;; AceTimer is unavailable (e.g. the test mock embeds no ScheduleTimer).
(var refresh-scheduled? false)

(fn debounced-refresh [self]
  (fn []
    (if self.ScheduleTimer
        (when (not refresh-scheduled?)
          (set refresh-scheduled? true)
          (self:ScheduleTimer (fn []
                                (set refresh-scheduled? false)
                                (root.refresh!))
                              0.2))
        (root.refresh!))
    nil))

;; --- Slash subcommands (/rt plan | reset | debug; PRD §6.6) -----------------

(fn print-lines! [self lines]
  "Print each chat line through AceConsole (prefixed, local-only output)."
  (each [_ line (ipairs lines)]
    (self:Print line))
  nil)

(fn cmd-plan [self]
  "Print this week's plan to chat. Reads the live client through the planner
   shell; degrades to the input error during loading screens."
  (let [input (planner.route-input)]
    (print-lines! self
                  (if input.ok
                      (format.plan-lines (route.plan-week input.player
                                                          input.ctx))
                      [(.. "Routina: no plan -- " (tostring input.err))]))))

(fn cmd-reset [self]
  "Reset the cumulative luck history: live session + persisted record."
  (events.reset-history!)
  (self:Print "Routina: luck history reset."))

(fn count-total [counts]
  "Sum of a string->integer count map (luck-history totals for /rt debug)."
  (accumulate [sum 0 _ n (pairs (or counts {}))]
    (+ sum n)))

(fn cmd-debug [self]
  "Dump diagnostic state to chat: DB version, log level, luck tracking, and the
   current plan aggregates (or why the route input is unavailable)."
  (let [input (planner.route-input)
        plan (when input.ok (route.plan-week input.player input.ctx))
        hist (?. self :db :char :history)]
    (print-lines! self
                  (format.debug-lines {:version (?. self :db :global :version)
                                       :log-level (?. self :db :global :options
                                                      :log-level)
                                       :tracking? (?. self :db :char
                                                      :preferences :route
                                                      :track-luck?)
                                       :runs (count-total (?. hist :runs))
                                       :drops (count-total (?. hist :drops))
                                       :err (when (not input.ok) input.err)
                                       :steps (when plan (length plan.steps))
                                       :score (?. plan :score)
                                       :est-minutes (?. plan :est-minutes)}))))

(fn handle-command [self input]
  "Route one /routina | /rt invocation by its first word; bare toggles the
   panel. Unknown words print a usage line instead of failing silently."
  (case (string.lower (or (and input (input:match "%S+")) ""))
    "" (root.toggle!)
    :options (options.open!)
    :plan (cmd-plan self)
    :reset (cmd-reset self)
    :debug (cmd-debug self)
    _ (self:Print "Routina: usage -- /rt [plan | reset | debug | options]")))

(fn addon.OnInitialize [self]
  ;; SavedVariables first -- frames and events can't read the DB before this.
  (let [AceDB (LibStub :AceDB-3.0)]
    (set self.db (AceDB:New :RoutinaDB saved-vars.defaults true))
    (set self.db.global
         (saved-vars.migrate self.db.global saved-vars.migrations))
    (set self.log (make-logger #(or self.db.global.options.log-level :info)))
    ;; Restore the persisted theme BEFORE any frame is built, so /reload comes
    ;; back in the chosen palette (anything but :light reads as :dark).
    (theme.set-mode! (?. self :db :char :preferences :route :theme))
    ;; Bind the AceConfig options panel to the DB (no-op without the config libs).
    (options.register! self)
    (self.log:info "OnInitialize complete")
    ;; Slash commands registered here so /routina works even if enable fails.
    ;; /routina is canonical; /rt is the short alias. Subcommands: plan / reset
    ;; / debug / options (PRD §6.6); bare toggles the panel.
    (let [handler (fn [input] (handle-command self input))]
      (self:RegisterChatCommand :routina handler)
      (self:RegisterChatCommand :rt handler))))

(fn addon.OnEnable [self]
  (self.log:info :OnEnable)
  (let [AceEvent (LibStub :AceEvent-3.0)]
    (set self.event-frame (events.init! AceEvent self.log)))
  ;; Plan inputs change at runtime (gear, talents, lockouts) -> repaint live.
  (events.set-refresh! (debounced-refresh self))
  ;; Give the dispatcher the per-character DB slot so it can seed + flush the
  ;; weekly-state across the session (RAID_INSTANCE_WELCOME -> PLAYER_LOGOUT).
  (events.set-store! (fn [] (and self.db self.db.char)))
  ;; Apply the persisted tracking opt-ins (experimental; off unless set).
  (events.set-history-tracking! (?. self :db :char :preferences :route
                                    :track-luck?))
  (events.set-yields-tracking! (?. self :db :char :preferences :route
                                   :track-yields?)))

(fn addon.OnDisable [self]
  (self.log:info :OnDisable)
  (events.cleanup! self.event-frame))

;; --- Register into the addon namespace -------------------------------------
;;
;; The entry module returns the AceAddon object (per example 04) rather than a
;; bare M; make-logger is attached so specs can exercise level gating without
;; standing up the whole addon.

(set addon.make-logger make-logger)
(set _G.Routina Routina)
(set Routina.addon addon)

addon
