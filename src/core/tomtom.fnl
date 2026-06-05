;; tomtom.fnl -- waypoint setting over the OPTIONAL TomTom addon.
;;
;; Soft-dep facade in the src/core/prices.fnl pattern (ROADMAP guiding
;; principle 6, Phase 9): TomTom present -> the crazy arrow points the way,
;; absent -> silent no-op, never a hard requirement, never a Lua error. The
;; ONLY module allowed to touch the TomTom API. The global is resolved at
;; CALL time (an OptionalDeps addon may load after us) and every external
;; call sits behind pcall, so API drift degrades to nil instead of erroring.
;;
;; API surface (verified against the TomTom source -- Nevcairiel/TomTom
;; mirror of the CurseForge addon, 2026-06-06; `_G.TomTom` is the global in
;; every client flavor):
;;   TomTom:AddWaypoint(uiMapID, x, y, opts) -> uid table
;;     x/y are MAP FRACTIONS in [0,1]; opts: title, from, persistent, crazy,
;;     cleardistance, arrivaldistance, callbacks. A custom opts.callbacks
;;     table REPLACES TomTom's defaults: callbacks.distance[yards] = fn fires
;;     as the player crosses that range (the OQ-14 arrival mechanism --
;;     src/core/circuit.fnl rides it; no OnUpdate polling needed).
;;   TomTom:RemoveWaypoint(uid)

(local Routina (or _G.Routina {}))

(local M {})

;; --- Public API ------------------------------------------------------------

(lambda M.available? []
  "Whether the TomTom addon is loaded right now (live check -- OptionalDeps
   may load after us). UI gates its waypoint affordances on this, so without
   TomTom the buttons never render (Phase 9 exit criterion).
   Domain:  (none)
   Returns: boolean."
  (not= nil _G.TomTom))

(lambda M.set-waypoint! [coord ?title ?opts]
  "Set one TomTom waypoint at a domain coord, returning its uid handle.
   Headless-safe: TomTom absent or throwing -> nil, never an error.
   Domain:  coord  : {:map-id integer :x number :y number} -- x/y fractions
                     in [0,1] (the ChainStep :coord / ActivityDef :entrance
                     shape)
            ?title : string | nil -- arrow label (default :Routina)
            ?opts  : table | nil -- extra TomTom options merged over ours
                     (e.g. {:callbacks {...}} for circuit arrival)
   Returns: uid table | nil."
  (let [tomtom _G.TomTom]
    (when (and tomtom tomtom.AddWaypoint coord coord.map-id)
      (let [opts {:title (tostring (or ?title :Routina)) :from :Routina}]
        (each [k v (pairs (or ?opts {}))]
          (tset opts k v))
        (let [(ok uid) (pcall tomtom.AddWaypoint tomtom coord.map-id coord.x
                              coord.y opts)]
          (when (and ok (= (type uid) :table))
            uid))))))

(lambda M.remove-waypoint! [?uid]
  "Remove a waypoint by the uid set-waypoint! returned. No-op on nil or when
   TomTom is absent / throws.
   Domain:  ?uid : table | nil
   Returns: nil."
  (let [tomtom _G.TomTom]
    (when (and tomtom tomtom.RemoveWaypoint ?uid)
      (pcall tomtom.RemoveWaypoint tomtom ?uid)))
  nil)

;; --- Register into the addon namespace -------------------------------------

(set _G.Routina Routina)
(set Routina.tomtom M)

M
