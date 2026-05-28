;; spec/ui/root_spec.fnl -- smoke test: loading the root module under the
;; mock CreateFrame surface should not raise, and show/hide/toggle/show-tab!
;; should run without erroring against the stubbed frames.

(local root (require :src.ui.root))

(describe :root
          (fn []
            (it "exports show!/hide!/toggle!/show-tab! lambdas"
                (fn []
                  (assert.are.equal :function (type root.show!))
                  (assert.are.equal :function (type root.hide!))
                  (assert.are.equal :function (type root.toggle!))
                  (assert.are.equal :function (type root.show-tab!))))
            (it "toggle! constructs the root frame and shows it"
                (fn []
                  (root.toggle!)
                  ;; Second toggle hides it; third reopens. No throw is the
                  ;; assertion -- the stub frames record state, but pixel
                  ;; correctness is wowUnit territory (see docs/TESTING.md).
                  (root.toggle!)
                  (root.toggle!)))
            (it "show-tab! accepts every known key"
                (fn []
                  (root.show!)
                  (root.show-tab! :weekly)
                  (root.show-tab! :lockouts)
                  (root.show-tab! :bis)
                  (root.hide!)))
            (it "show-tab! rejects unknown keys"
                (fn []
                  (assert.has_error (fn [] (root.show-tab! :nope)))))))
