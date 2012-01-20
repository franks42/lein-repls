;; Copyright (c) Frank Siebenlist. All rights reserved.
;; The use and distribution terms for this software are covered by the
;; Eclipse Public License 1.0 (http://opensource.org/licenses/eclipse-1.0.php)
;; which can be found in the file COPYING at the root of this distribution.
;; By using this software in any fashion, you are agreeing to be bound by
;; the terms of this license.
;; You must not remove this notice, or any other, from this software.

(ns cljsh.core)	

(defn repl-no-prompt "prints no prompt for pure cli-usage" [] (printf "")(flush))
(defn repl-ns-prompt [] (printf "%s=> " (ns-name *ns*))(flush))
;;(defn repl-cwd-prompt [] (printf "%s > " @fs/cwd)(flush))
(defn repl-hi-prompt [] (print "hi> ")(flush))
(defn repl-nil-prompt [] nil)

(defn current-thread [] (. Thread currentThread))
(defn thread-id [a-thread] (.getId a-thread))

(def ^:dynamic *cljsh-args* "")

(def ^:dynamic *repl-thread-prompt-map* (atom {}))
(def ^:dynamic *repl-result-print-map* (atom {}))

(defn set-prompt 
	"sets the prompt function associated with the current thread."
	[prompt-fun]
	(swap! *repl-thread-prompt-map* assoc (current-thread) prompt-fun)
	prompt-fun)

(defn set-repl-result-print 
	"sets the eval-result print function associated with the current thread."
	[print-fun]
	(swap! *repl-result-print-map* assoc (current-thread) print-fun)
	print-fun)

(defn repl-thread-prompt 
	"returns the prompt-function that is mapped to the current thread"
	[]
	(let [p (get @*repl-thread-prompt-map* (current-thread))]
		(if p
			p
			(if (= @*repl-thread-prompt-map* {})
				(set-prompt repl-ns-prompt)
				(set-prompt repl-nil-prompt)))))
			

(defn repl-result-print 
	"returns the print-function that is mapped to the current thread"
	[]
	(let [p (get @*repl-result-print-map* (current-thread))]
		(if p
			p
			(if (= @*repl-result-print-map* {})
				(set-repl-result-print prn)
				(set-repl-result-print (fn [a]))))))
			


(def ^:dynamic *repl-prompt* (fn [] ((repl-thread-prompt))))

;;(def ^:dynamic *repl-result-print* prn)
(def ^:dynamic *repl-result-print* (fn [a] ((repl-result-print) a)))

(defn -main [& args]
	(println "Welcome to my project! These are your args:" args))
