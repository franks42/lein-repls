;; Copyright (c) Frank Siebenlist. All rights reserved.
;; The use and distribution terms for this software are covered by the
;; Eclipse Public License 1.0 (http://opensource.org/licenses/eclipse-1.0.php)
;; which can be found in the file COPYING at the root of this distribution.
;; By using this software in any fashion, you are agreeing to be bound by
;; the terms of this license.
;; You must not remove this notice, or any other, from this software.

(ns cljsh.core
	(:require [clojure.main]
	          [clojure.string]
	          [clojure.pprint]
	          [cljsh.utils]
	          [clojure.java.shell]
	          ;[clojure.tools.cli]
	          ))

;; some set at lein-repls start in leiningen.repls/repl-server
(def ^:dynamic cljsh.core/lein-repls-name "lein-repls") 
(def ^:dynamic cljsh.core/lein-repls-version "1.9.8")
(def ^:dynamic cljsh.core/lein-project-name "") 
(def ^:dynamic cljsh.core/lein-project-version "")
(def ^:dynamic cljsh.core/lein-repls-host "")
(def ^:dynamic cljsh.core/lein-repls-port "")
(def ^:dynamic cljsh.core/lein-repls-pid (:out (clojure.java.shell/sh "bash" "-c" (str "echo -n ${PPID}"))))



(defn ping [] (println "pong"))

(def cljsh-env (cljsh.utils/inheritable-thread-local 
                  cljsh.utils/copy-atom-child-init 
                  (atom "")))
(def cljsh-command-path (cljsh.utils/inheritable-thread-local 
                  cljsh.utils/copy-atom-child-init 
                  (atom "")))
(def cljsh-command-line-args (cljsh.utils/inheritable-thread-local 
                  cljsh.utils/copy-atom-child-init 
                  (atom [])))
(def cljsh-file-command-path (cljsh.utils/inheritable-thread-local 
                  cljsh.utils/copy-atom-child-init 
                  (atom "")))
(def cljsh-file-command-line-args (cljsh.utils/inheritable-thread-local 
                  cljsh.utils/copy-atom-child-init 
                  (atom [])))
; (swap! @cljsh.core/cljsh-env (fn [_] new-env-str))
; (println "cljsh-env:" @@cljsh.core/cljsh-env)

(defn register-cljsh-env 
  "Environment is passed as a string and massaged into a map, 
   and stored in an inheritable-thread-local"
  [env-str]
  (let [env-map (apply assoc {} (flatten 
                  (map  (fn [s] (let [v (clojure.string/split s #"=" 2)
                                      vv (if (= (count v) 1) [(first v) ""] v)]
                                  vv))
                        (clojure.string/split-lines env-str))))]
    (swap! @cljsh.core/cljsh-env (fn [_] env-map))))

(defn register-cljsh-command-path [v] (swap! @cljsh.core/cljsh-command-path (fn [_] v)))
(defn register-cljsh-command-line-args [v] (swap! @cljsh.core/cljsh-command-line-args (fn [_] v)))
(defn register-cljsh-file-command-line-args [v] (swap! @cljsh.core/cljsh-file-command-line-args (fn [_] v)))
(defn register-cljsh-file-command-path [v] (swap! @cljsh.core/cljsh-file-command-path (fn [_] v)))

(defn current-thread [] (. Thread currentThread))

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


;; redirect the error messages from the stacktraces...

;;if we do not want a repl-prompt, we infer that we do not want the error messages to stderr but to the *console-err*
;; any errors in scripts passed to cljsh will be shown on the console.
;; still the reader's error messages are not redirected... todo.

(defn cljsh-repl-caught 
  "Set in leiningen.repls/repl-options and hooks in before clojure.main/repl-caught to redirect stderr if needed. If no repl prompt, then redirect the stderr to the console's, otherwise just forward."
  [e]
	(if (= (get @*repl-thread-prompt-map* (current-thread)) repl-nil-prompt)
		(binding [*err* cljsh.core/*console-err*]
			(clojure.main/repl-caught e))
		(clojure.main/repl-caught e)))

;; ns context facility

(def ^:dynamic *saved-ns-context*   (atom "user"))
(def ^:dynamic *default-ns-context* (atom "user"))

(defn save-ns-context 
  "Saves the current namespace context."
  []
  (println "save :" (str *ns*))
  (swap! *saved-ns-context* (fn [_,n] (println "n:" n) n) (str *ns*)))

(defn restore-ns-context 
  "Restore the namespace context identified with ctxt (String)."
  []
  (println "restore :" (str *ns*))
  (when-not (=  (str *ns*) @*default-ns-context*)
    (swap! *default-ns-context* (fn [_,n] n) (str *ns*)))
  (when-not (=  (str *ns*) @*saved-ns-context*)
    (in-ns (symbol @*saved-ns-context*))))

(defn restore-default-ns-context 
  "Restore the namespace context identified with ctxt (String)."
  []
  (println "restore default :" (str *ns*))
  (when-not (=  (str *ns*) @*default-ns-context*)
    (in-ns (symbol @*default-ns-context*))))


;;;;
;; future processing
;;
;; (defn process-cljsh-req
;;   ""
;;   []
;;   ;(clojure.pprint/pprint  @@cljsh.core/cljsh-env)
;;   (clojure.pprint/pprint @@cljsh.core/cljsh-command-line-args)
;;   (let [ c (clojure.tools.cli/cli @@cljsh.core/cljsh-command-line-args
;;              ["-p" "--port" "Listen on this port" :parse-fn #(Integer. %)] 
;;              ["-h" "--host" "The hostname" :default "localhost"]
;;              ["-v" "--[no-]verbose" :default true]
;;              ["-c" "--code"]
;;              ["-f" "--file"]
;;              ["-l" "--log-directory" :default "/some/path"])]
;;       (clojure.pprint/pprint @@cljsh.core/cljsh-command-line-args)
;;       (clojure.pprint/pprint c)
;;       (println "code:" (:code (first c)))
;;       (println "load-string:" (load-string (:code (first c))))))
