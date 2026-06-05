;; format.fnl -- pure formatters for probabilities, durations, scores.
;;
;; Widgets consume these to keep numeric formatting in one place. Pure;
;; busted-testable. No WoW API.
;; See docs/UI.md §6 (item-pill, chance-meter, activity-card all read here).

(local M {})

(lambda M.percent [?p]
  "Format a probability as 'NN%'.
   Domain:  ?p : number in [0, 1], nil, or NaN
   Returns: string like \"62%\"; \"--\" if p is nil or NaN."
  (if (or (not ?p) (not= ?p ?p))
      "--"
      (.. (math.floor (+ 0.5 (* ?p 100))) "%")))

(lambda M.duration-short [?seconds]
  "Format a duration as the largest two units.
   Domain:  ?seconds : non-negative number or nil
   Returns: \"2d 4h\", \"8h 21m\", \"0:42\", or \"--\" if nil or negative."
  (if (or (not ?seconds) (< ?seconds 0))
      "--"
      (let [day 86400
            hour 3600
            minute 60
            d (math.floor (/ ?seconds day))
            h (math.floor (/ (% ?seconds day) hour))
            m (math.floor (/ (% ?seconds hour) minute))
            s (math.floor (% ?seconds minute))]
        (if (> d 0) (.. d "d " h :h)
            (> h 0) (.. h "h " m :m)
            (.. m ":" (string.format "%02d" s))))))

(lambda M.score-short [?score]
  "Format a score as a two-decimal fraction.
   Domain:  ?score : number or nil
   Returns: \"0.83\"; \"--\" if nil."
  (if (not ?score) "--" (string.format "%.2f" ?score)))

;; --- Slash-command lines (/rt plan, /rt debug) ------------------------------
;;
;; Pure plan/diagnostics -> chat-line builders. The imperative shell
;; (src/core/ace.fnl) only iterates these and Prints; everything assertable
;; lives here. PRD §6.6.

;; /rt plan prints at most this many target items per step (PRD §6.1: top 3).
(local plan-line-max-items 3)

(fn by-chance-then-label [a b]
  "Total-order comparator for a step's target items: likelier first, ties by
   label then item-id (table.sort is not stable, so the order must be total)."
  (if (not= a.chance b.chance) (> (or a.chance 0) (or b.chance 0))
      (not= a.label b.label) (< (tostring a.label) (tostring b.label))
      (< (or a.item-id 0) (or b.item-id 0))))

(fn step-items [step]
  "The step's top target items as 'Label NN%' fragments, likeliest first."
  (let [sorted (icollect [_ it (ipairs step.items)] it)]
    (table.sort sorted by-chance-then-label)
    (icollect [i it (ipairs sorted) &until (> i plan-line-max-items)]
      (.. (tostring it.label) " " (M.percent it.chance)))))

(fn step-line [i step]
  "One numbered plan line: rank, name, type, minutes, score, top items."
  (.. i ". " (tostring step.name) " (" (tostring step.type) ", ~" step.minutes
      "m, score " (M.score-short step.score) "): "
      (table.concat (step-items step) ", ")))

(lambda M.plan-lines [?plan]
  "Chat lines for /rt plan: a header plus one numbered line per step, each with
   its top target items by at-least-one chance.
   Domain:  ?plan : route.plan-week result {:steps :score :est-minutes} | nil
   Returns: [string] -- a single 'nothing to plan' line when empty or nil."
  (let [steps (or (and ?plan ?plan.steps) [])]
    (if (= 0 (length steps))
        ["Routina: nothing to plan -- no available activity awards a missing BiS item."]
        (let [lines [(.. "Routina weekly plan -- score "
                         (M.score-short ?plan.score) ", ~"
                         (math.floor (or ?plan.est-minutes 0)) " min:")]]
          (each [i step (ipairs steps)]
            (table.insert lines (step-line i step)))
          lines))))

(lambda M.debug-lines [state]
  "Chat lines for /rt debug: a compact diagnostic dump of the addon state.
   Domain:  state : {:version ?integer :log-level ?string|keyword
                     :tracking? ?boolean :runs ?integer :drops ?integer
                     :err ?string -- route-input failure text, nil when ok
                     :steps ?integer :score ?number :est-minutes ?number}
   Returns: [string] -- three lines: db/log, luck tracking, plan or input error."
  [(.. "Routina debug -- db v" (tostring (or state.version "?")) ", log "
       (tostring (or state.log-level "?")))
   (.. "luck tracking: " (if state.tracking? :on :off) " (runs "
       (tostring (or state.runs 0)) ", drops " (tostring (or state.drops 0)) ")")
   (if state.err
       (.. "route input: unavailable -- " (tostring state.err))
       (.. "plan: " (tostring (or state.steps 0)) " steps, score "
           (M.score-short state.score) ", ~"
           (math.floor (or state.est-minutes 0)) " min"))])

;; --- Register --------------------------------------------------------------

(local Routina (or _G.Routina {}))
(set _G.Routina Routina)
(set Routina.format M)

M
