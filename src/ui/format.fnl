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

;; --- Register --------------------------------------------------------------

(local Routina (or _G.Routina {}))
(set _G.Routina Routina)
(set Routina.format M)

M
