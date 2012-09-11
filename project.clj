(defproject lein-repls "1.9.9-SNAPSHOT"
	:description "A leiningen plugin to start a persistent repl server for use with cljsh"
  :url "https://github.com/franks42/lein-repls"
  :license {:name "Eclipse Public License"
            :url "http://www.eclipse.org/legal/epl-v10.html"}
 	:dependencies [[org.clojure/clojure "1.4.0"]
	               [clj-info "0.2.6"]
	               [clj-growlnotify "0.1.2-SNAPSHOT"]]
	:dev-dependencies [[lein-marginalia "0.7.1"]
  	                 [codox "0.6.1"]])
