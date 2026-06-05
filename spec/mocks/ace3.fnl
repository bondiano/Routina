;; ace3.fnl -- test-only LibStub + Ace3 stubs.
;;
;; Ace3/LibStub are .pkgmeta externals, never committed, so they are absent under
;; busted. src/core/ace.fnl resolves them lazily, but its load-time
;; (AceAddon:NewAddon ...) still needs a LibStub. This mock provides just enough
;; surface to require ace.fnl and run its lifecycle, with sinks so specs can
;; assert what got registered. Installed by spec/helper.lua after the WoW mock.
;;
;; Only mock what the scaffold calls: NewAddon (+AceConsole RegisterChatCommand/
;; Print), AceDB:New, AceEvent:Embed. Extend as later phases use more.

(local M {})

;; --- Sinks (assertable from specs) -----------------------------------------

(local state {:commands {} :printed []})

(fn deep-copy [t]
  (if (= (type t) :table)
      (collect [k v (pairs t)] k (deep-copy v))
      t))

;; --- Lib stubs -------------------------------------------------------------

(local AceConsole
       {:RegisterChatCommand (fn [_self cmd handler]
                               (tset state.commands cmd handler))
        :Print (fn [_self msg]
                 (table.insert state.printed (tostring msg)))})

(local AceAddon {:NewAddon (fn [_self name ...]
                             ;; Real NewAddon embeds the named mixins; we only need
                             ;; AceConsole's chat-command surface for the scaffold.
                             {: name
                              :RegisterChatCommand AceConsole.RegisterChatCommand
                              :Print AceConsole.Print})})

(local AceDB
       {:New (fn [_self _name defaults _default-profile]
               ;; Materialize defaults so migrate/make-logger find real tables.
               {:global (deep-copy (or (?. defaults :global) {}))
                :char (deep-copy (or (?. defaults :char) {}))})})

(local AceEvent {:Embed (fn [_self target]
                          (set target.registered {})
                          (set target.RegisterEvent
                               (fn [self ev handler]
                                 (tset self.registered ev handler)))
                          (set target.UnregisterEvent
                               (fn [self ev] (tset self.registered ev nil)))
                          (set target.UnregisterAllEvents
                               (fn [self] (set self.registered {})))
                          target)})

(local libs {:AceAddon-3.0 AceAddon
             :AceConsole-3.0 AceConsole
             :AceDB-3.0 AceDB
             :AceEvent-3.0 AceEvent})

;; --- Install ---------------------------------------------------------------

(fn M.install! []
  "Install a callable _G.LibStub returning the Ace3 stubs. Call once from
   spec/helper.lua after the WoW-API install."
  (let [lib-stub {}]
    (setmetatable lib-stub {:__call (fn [_self name] (. libs name))})
    (set _G.LibStub lib-stub))
  nil)

;; --- Per-test helpers ------------------------------------------------------

(fn M.reset! []
  "Clear recorded registrations. Call in before_each when asserting sinks."
  (set state.commands {})
  (set state.printed []))

(fn M.registered-commands []
  "Return the {command -> handler} table recorded via RegisterChatCommand."
  state.commands)

(fn M.printed []
  "Return the chat lines recorded via AceConsole Print, oldest first."
  state.printed)

M
