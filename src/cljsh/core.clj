;; Copyright (c) Frank Siebenlist. All rights reserved.
;; The use and distribution terms for this software are covered by the
;; Eclipse Public License 1.0 (http://opensource.org/licenses/eclipse-1.0.php)
;; which can be found in the file COPYING at the root of this distribution.
;; By using this software in any fashion, you are agreeing to be bound by
;; the terms of this license.
;; You must not remove this notice, or any other, from this software.

(ns cljsh.core
  ;(:use (swank util core commands))
	(:require [clojure.main]
						[cljsh.complete]
						[cljsh.completion]
						;;[swank.commands.completion]
						))

(defn jjj [] (cljsh.completion/potential-ns))

;; note that we have to keep this in sync with the project.clj entry
(def lein-repls-version "1.4.0-SNAPSHOT")

(defn current-thread [] (. Thread currentThread))

;; place holder for argument passing thru cljsh invocation
(def ^:dynamic *cljsh-command-line-file* "")
(def ^:dynamic *cljsh-command-line-args* "")
(def ^:dynamic *cljsh-args* "")

(def ^:dynamic *console-out* *out*)
(def ^:dynamic *console-err* *err*)

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

(declare set-repl-result-print)
(defn repl-thread-prompt 
	"returns the prompt-function that is mapped to the current thread"
	[]
	(let [p (get @*repl-thread-prompt-map* (current-thread))]
		(if p
			p
			(if (empty? @*repl-thread-prompt-map*)
				;; if map is empty, we have the console so turn ns-prompt on
				(do (def ^:dynamic *console-out* *out*)
						(def ^:dynamic *console-err* *err*)
						(set-repl-result-print prn)
						(set-prompt repl-ns-prompt))
				;; by default no prompt
				;(def ^:dynamic *err* *console*)
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
			(if (empty? @*repl-result-print-map*)
				;; if map is empty, we have the console so turn printing on
				(set-repl-result-print prn)
				;; by default turn printing off
				(set-repl-result-print (fn [&a]))))))
			

;; this function setting is used inside of the repl(s) code 
;; indirection needed because of all the delayed loading thru quoting
(def ^:dynamic *repl-result-print* (fn [a] ((repl-result-print) a)))


;; see if we can redirect the error messages...
;;if we do not want a repl-prompt, we infer that we do not want the error messages to stderr but to the *console-err*
;; any errors in scripts passed to cljsh will be shown on the console.

(defn cljsh-repl-caught [e]
	(if (= (get @*repl-thread-prompt-map* (current-thread)) repl-nil-prompt)
		(binding [*err* cljsh.core/*console-err*]
			(clojure.main/repl-caught e))
		(clojure.main/repl-caught e)))
		
;;
(defn completion-words []
	(let [completions (mapcat (comp keys ns-publics) (all-ns))
				all-completions (concat completions ['if 'def])] ;; special forms
		(println (apply str (interpose \newline (sort all-completions))))))
