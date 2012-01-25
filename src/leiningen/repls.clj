(ns leiningen.repls
  "Start a persistent repl-server console, and interact/eval/repl thru a lightweight command-line \"cljsh\" client."
  (:require [clojure.main]
  					[clojure.pprint]
  					[clojure.java.shell]
  					;[lein-repls.core]
  					)
  ;;(:require [fs.core :as fs])
  (:use [leiningen.core :only [exit user-settings *interactive?*]]
        [leiningen.compile :only [eval-in-project]]
        [leiningen.deps :only [find-deps-files deps]]
        [leiningen.trampoline :only [*trampoline?*]]
        [leiningen.util.paths :only [leiningen-home]]
        [clojure.java.io :only [copy]])
  (:import (java.net Socket InetAddress ServerSocket SocketException)
           (java.io OutputStreamWriter InputStreamReader File PrintWriter)
           (clojure.lang LineNumberingPushbackReader)))

(require 'cljsh.core)


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
                 		(println "repl-init:" in#)
                   (require in#))
                 (when mn#
                   (require mn#))
                 (in-ns (or in# mn# '~'user)))
        ;; Suppress socket closed since it's part of normal operation
        caught `(fn [t#]
                  (when-not (instance? SocketException t#)
                    ;;(~(:caught options 'clojure.main/repl-caught) t#)))
                    (~(:caught options 'cljsh.core/cljsh-repl-caught) t#)))
                    
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
                      (if (= :leiningen.repl/exit input#) ; programmatically signal close
                        (do (.close *in*) request-exit#)
                        input#))))]
    (apply concat [:init init :caught caught :read read]
           (dissoc options :caught :init :read))))
				
(defn repl-server [project host port & options]
	`(do (try ;; transitive requires don't work for stuff on bootclasspath
			(require '~'clojure.java.shell)
			(require '~'clojure.java.browse)
      ;;(require '~'cljsh.core)
			;;(require '~'leiningen.repls)
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
					(println "## Clojure" (clojure-version) "- \"lein-repls\" console and server started on project" (str "\"" ~(:name project) " " ~(:version project) "\"") (str "(pid/host/port:" (binding [*ns* (find-ns (quote clojure.java.shell))] (eval (quote (:out (clojure.java.shell/sh "bash" "-c" (str "echo -n ${PPID}")))))) "/" ~host "/" ~port ") ##"))
					;; block to avoid shutdown-agents
					@(promise)))))))

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
  "Start a persistent repl-server console, and interact/eval/repl thru a lightweight command-line \"cljsh\" client.

A socket-repl server is launched in the background with a console-like repl-session. 
A separate lightweight \"cljsh\" command-line bash-client will send clojure code passed on the command line, thru stdin and/or in a file to the repl-server for eval. This setup allows you to use clojure for shell-scripts with almost zero-startup time.  
Invoked from within the project's directory, cljsh will use that lein-project's config for the repl. Running outside any project, it will use a standalone repl session. (code based on leiningen's repl)
See \"https://github.com/franks42/lein-repls\" for details and docs."
  ([] (repls nil))
  ([project]
     (when (and project (or (empty? (find-deps-files project))
                            (:checksum-deps project)))
       (deps project))
     (let	[ ;; project is modified to accomodate pre-loading of cljsh.core without having to change project.clj
     			 project (assoc project :project-init '(require 'cljsh.core))
     			 [port host] (repl-socket-on project)
           server-form (apply repl-server project host port
                              (concat (:repl-options project)
                                      (:repl-options (user-settings))
                                      ;; :prompt and :print are forced-set by functions defined in cljsh.core
                                      [:print  'cljsh.core/*repl-result-print*
                                       :prompt 'cljsh.core/*repl-prompt*]))
           ;; TODO: make this less awkward when we can break poll-repl-connection
           retries (- retry-limit (or (:repl-retry-limit project)
                                        ((user-settings) :repl-retry-limit)
                                        retry-limit))]
     	(let [pwd (:out (clojure.java.shell/sh "bash" "-c" (str "echo -n `pwd`")))
       			pid (:out (clojure.java.shell/sh "bash" "-c" (str "echo -n ${PPID}")))
       			lfname (str "echo export LEIN_REPL_PORT='" port "'" " >  " pwd "/.lein_repls")
      	 		out2 (:out (clojure.java.shell/sh "bash" "-c" lfname))
      	 		out3 (:out (clojure.java.shell/sh "bash" "-c" (str "echo export LEIN_REPL_PID='" pid "'" " >>  " pwd "/.lein_repls")))]
       )
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
