(defproject lein-repls "1.9.8"
	:description "A leiningen plugin to start a persistent repl server for use with cljsh"
  :url "https://github.com/franks42/lein-repls"
  :license {:name "Eclipse Public License"
            :url "http://www.eclipse.org/legal/epl-v10.html"}
 	:dependencies [[org.clojure/clojure "1.3.0"]
	               [clj-info "0.2.1"]
	               [clj-growlnotify "0.1.0"]]
	:dev-dependencies [[lein-marginalia "0.6.0"]
  	                 [codox "0.5.0"]])
