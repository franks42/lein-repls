(ns leiningen.repls
  "Start a repl session either with the current project or standalone."
  (:require [clojure.main])
  ;;(:require [fs.core :as fs])
  (:use [leiningen.core :only [exit user-settings *interactive?*]]
        [leiningen.compile :only [eval-in-project]]
        [leiningen.deps :only [find-deps-files deps]]
        [leiningen.trampoline :only [*trampoline?*]]
        [clojure.java.io :only [copy]])
  (:import (java.net Socket InetAddress ServerSocket SocketException)
           (java.io OutputStreamWriter InputStreamReader File PrintWriter)
           (clojure.lang LineNumberingPushbackReader)))

;;---------------------------------------------------------------------------------------------------------------------

;;(defn -main [] "println "HELLO")

(defn repl-no-prompt "prints no prompt for pure cli-usage" [] (printf "")(flush))
(defn repl-ns-prompt [] (printf "%s=> " (ns-name *ns*))(flush))
;(defn repl-cwd-prompt [] (printf "%s > " @fs/cwd)(flush))
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

;;---------------------------------------------------------------------------------------------------------------------

(def retry-limit 200)

(defn repl-options [project options]
  (let [options (apply hash-map options)
        init `#(let [is# ~(:repl-init-script project)
                     in# '~(:repl-init project)
                     mn# '~(:main project)]
                 ~(:init options)
                 (when (and is# (.exists (File. (str is#))))
                   (println (str "Warning: :repl-init-script is "
                                 "deprecated; use :repl-init."))
                   (load-file is#))
                 (when in#
                   (require in#))
                 (when mn#
                   (require mn#))
                 (in-ns (or in# mn# '~'user)))
        ;; Suppress socket closed since it's part of normal operation
        caught `(fn [t#]
                  (when-not (instance? SocketException t#)
                    (~(:caught options 'clojure.main/repl-caught) t#)))
        ;; clojure.main/repl has no way to exit without signalling EOF,
        ;; which we can't do with a socket. We can't rebind skip-whitespace
        ;; in Clojure 1.3, so we have to duplicate the function
        read `(fn [request-prompt# request-exit#]
                (or ({:line-start request-prompt# :stream-end request-exit#}
                     (try (clojure.main/skip-whitespace *in*)
                          (catch Exception _# :stream-end)))
                    (let [input# (read)]
                      (clojure.main/skip-if-eol *in*)
                      ;;(if (= ::exit input#) ; programmatically signal close
                      (if (= :leiningen.repls/exit input#) ; programmatically signal close
                        (do (.close *in*) request-exit#)
                        input#))))
		;;:prompt leiningen.repls/*repl-prompt*
		prompt (var *repl-prompt*)
		;;:print leiningen.repls/*repl-result-print*
		;;ppprint `(fn [a#] ((~repl-result-print) a#))
        ]
    (println "JAJAJA" prompt)
    ;;(println [:init init :caught caught :read read :prompt prompt :print ppprint])
    (println options)
    (apply concat [:init init :caught caught :read read :prompt prompt]
           (dissoc options :caught :init :read :prompt :print))))
    ;;(apply concat [:init init :caught caught :read read]
           ;;(dissoc options :caught :init :read))))

(defn repl-server [project host port & options]
	`(do (try ;; transitive requires don't work for stuff on bootclasspath
			(require '~'clojure.java.shell)
			(require '~'clojure.java.browse)
			(require '~'leiningen.repls)
			;; these are new in clojure 1.2, so swallow exceptions for 1.1
			(catch Exception _#))
			(set! *warn-on-reflection* false)
		(let [server# (ServerSocket. ~port 0 (InetAddress/getByName ~host))
			acc# (fn [s#]
				(let [ins# (.getInputStream s#)
				outs# (.getOutputStream s#)
				out-writer# (OutputStreamWriter. outs#)]
				(doto 
					(Thread.
						#(binding [*in* (-> ins# InputStreamReader.
											LineNumberingPushbackReader.)
									*out* out-writer#
									*err* (PrintWriter. out-writer#)
									*warn-on-reflection*
										~(:warn-on-reflection project)]
							(clojure.main/repl
							~@(repl-options project options))))
					.start)))]

			(doto (Thread. #(when-not (.isClosed server#)
								(try
									(acc# (.accept server#))
									(catch SocketException e#
										(.printStackTrace e#)))
								(recur)))
					.start)

			(if ~*trampoline?*
				(clojure.main/repl ~@options)
				(do (when-not ~*interactive?*
						(println "repls-repl started; server listening on"
							~host "port" ~port))
					;; block to avoid shutdown-agents
					@(promise))))))

(defn copy-out-loop [reader]
  (let [buffer (make-array Character/TYPE 1000)]
    (loop [length (.read reader buffer)]
      (when-not (neg? length)
        (.write *out* buffer 0 length)
        (flush)
        (Thread/sleep 100)
        (recur (.read reader buffer))))))

(defn repl-client [reader writer & [socket]]
  (.start (Thread. #(do (copy-out-loop reader)
                        (exit 0))))
  (loop []
    (let [input (read-line)]
      (when (and input (not= "" input) (not (.isClosed socket)))
        (.write writer (str input "\n"))
        (.flush writer)
        (recur)))))

(defn- connect-to-server [socket handler]
  (let [reader (InputStreamReader. (.getInputStream socket))
        writer (OutputStreamWriter. (.getOutputStream socket))]
    (handler reader writer socket)))

(defn poll-repl-connection
  ([port retries handler]
     (when (> retries retry-limit)
       (throw (Exception. "Couldn't connect")))
     (Thread/sleep 100)
     (let [val (try (connect-to-server (Socket. "localhost" port) handler)
                    (catch java.net.ConnectException _ ::retry))]
       (if (= ::retry val)
         (recur port (inc retries) handler)
         val)))
  ([port]
     (poll-repl-connection port 0 repl-client)))

(defn repl-socket-on [{:keys [repl-port repl-host]}]
  [(Integer. (or repl-port
                 (System/getenv "LEIN_REPL_PORT")
                 (dec (+ 1024 (rand-int 64512)))))
   (or repl-host
       (System/getenv "LEIN_REPL_HOST")
       "localhost")])

(defn repls
  "Start a repl session either with the current project or standalone.

A socket-repl will also be launched in the background on a socket based on the
:repl-port key in project.clj or chosen randomly. Running outside a project
directory will start a standalone repl session."
  ([] (repls nil))
  ([project]
     (when (and project (or (empty? (find-deps-files project))
                            (:checksum-deps project)))
       (deps project))
     (let [[port host] (repl-socket-on project)
           server-form (apply repl-server project host port
                              (concat (:repl-options project)
                                      (:repl-options (user-settings))))
           ;; TODO: make this less awkward when we can break poll-repl-connection
           retries (- retry-limit (or (:repl-retry-limit project)
                                        ((user-settings) :repl-retry-limit)
                                        retry-limit))]
       (if *trampoline?*
         (eval-in-project project server-form)
         (do (future (if (empty? project)
                       (clojure.main/with-bindings (println (eval server-form)))
                       (eval-in-project project server-form)))
             (poll-repl-connection port retries repl-client)
             (exit)))))
  ([project init-namespace]
     (if (= init-namespace ":lein")
       (repls nil)
       (repls (assoc project :repl-init (symbol init-namespace))))))
