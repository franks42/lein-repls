;; Copyright (c) Frank Siebenlist. All rights reserved.
;; The use and distribution terms for this software are covered by the
;; Eclipse Public License 1.0 (http://opensource.org/licenses/eclipse-1.0.php)
;; which can be found in the file COPYING at the root of this distribution.
;; By using this software in any fashion, you are agreeing to be bound by
;; the terms of this license.
;; You must not remove this notice, or any other, from this software.

(ns cljsh.core)	

(defn current-thread [] (. Thread currentThread))

;; place holder for argument passing thru cljsh invocation
(def ^:dynamic *cljsh-args* "")


;; repl prompt functions
;; implementation keeps a map of thread, i.e. repl instance, and prompt preference.
;; this feels kind of a hack - (binding...) would be better be requires deeper integration
;; in lein-repl and/or clojure.main/repl code - maybe later...

(defn repl-no-prompt "prints empty-string prompt for pure cli-usage" [] (printf "")(flush))
(defn repl-ns-prompt "prints namespace prompt for interactive usage" [] (printf "%s=> " (ns-name *ns*))(flush))
;;(defn repl-cwd-prompt [] (printf "%s > " @fs/cwd)(flush))
(defn repl-nil-prompt [] nil)

(def ^:dynamic *repl-thread-prompt-map* (atom {}))

(defn set-prompt 
	"sets the prompt function associated with the current thread."
	[prompt-fun]
	(swap! *repl-thread-prompt-map* assoc (current-thread) prompt-fun)
	prompt-fun)

(defn repl-thread-prompt 
	"returns the prompt-function that is mapped to the current thread"
	[]
	(let [p (get @*repl-thread-prompt-map* (current-thread))]
		(if p
			p
			(if (= @*repl-thread-prompt-map* {})
				;; if map is empty, we have the console so turn ns-prompt on
				(set-prompt repl-ns-prompt)
				;; by default no prompt
				(set-prompt repl-nil-prompt)))))

;; this function setting is used inside of the repl(s) code 
;; indirection needed because of all the delayed loading thru quoting
(def ^:dynamic *repl-prompt* (fn [] ((repl-thread-prompt))))


;; repl result printing functions

(def ^:dynamic *repl-result-print-map* (atom {}))

(defn set-repl-result-print 
	"sets the eval-result print function associated with the current thread."
	[print-fun]
	(swap! *repl-result-print-map* assoc (current-thread) print-fun)
	print-fun)


(defn repl-result-print 
	"returns the print-function that is mapped to the current thread"
	[]
	(let [p (get @*repl-result-print-map* (current-thread))]
		(if p
			p
			(if (= @*repl-result-print-map* {})
				;; if map is empty, we have the console so turn printing on
				(set-repl-result-print prn)
				;; by default turn printing off
				(set-repl-result-print (fn [a]))))))
			

;; this function setting is used inside of the repl(s) code 
;; indirection needed because of all the delayed loading thru quoting
(def ^:dynamic *repl-result-print* (fn [a] ((repl-result-print) a)))

