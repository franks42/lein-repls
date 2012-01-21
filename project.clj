(defproject lein-repls "1.0.0-SNAPSHOT"
	:description "A leiningen plugin to start a persistent repl server for use with cljsh"
	:dependencies [	[org.clojure/clojure "1.3.0"]
								]

  ;;:repl-port 12357
  ;;:repl-host "0.0.0.0"

  :main cljsh.core

	:project-init (require 'cljsh.core)

  )
