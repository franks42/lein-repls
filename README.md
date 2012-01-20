#CLJSH: A lightweight Clojure Shell frontend/client that uses rlwrap and socat with lein's repl-server.

Cljsh is a bash shell script that interacts with Leiningen's networked repl-server. It allows the user to submit Clojure statement and Clojure script files to the persistent networked repl for evaluation. The script uses socat to make the networked repl appear local. Socat also makes this client lightweight and fast, very much like the ruby-based cake-client. The Clojure statements are send thru socat to the persistent Leiningen-repl-server, and the results are brought back thru socat to stdout.

The advantage of using socat and the networked repl is that there is no real protocol - or no protocol different from the normal repl-interaction: feed Clojure form in thru stdin, and have the results or printed side-effect presented on stdout.

This cljsh approach is different from cake, nailgun, swank and nrepl, which have true client-server protocols. Cljsh, however, always sends normal Clojure-statement to the repl-server, while the output is whatever the program returns from either the evaluation or from the side-effect printing. You can choose to switch the printing of the evaluation results off, such that you can completely control the output thru explicit printing to stdout.

The result is a lightweight repl-client like cake/nailgun thru socat, which includes history and completion thru rlwrap for interactive use.

It can also be used as a one-shot Clojure client that you feed clojure-scripts thru stdin and yields evaluated results thru stdout from a persistent repl. 

## Install

Note that this cljsh depends on a very recent development version of leiningen (v 1.7.0 from Jan 9 2012)!
So... clone leiningen's github and make sure you have the latest version in the 1.x branch, then use the lein script from inside the bin directory of that repo... until it is part of the standard lein distro...

Cljsh also needs an installed version of socat and rlwrap.
An easy way is thru ports/macports on macosx, but any other recent version will probably do:
  
sudo port install socat  
sudo port install rlwrap  


The easiest way to play with cljsh is to clone the github [cljsh project](https://github.com/franks42/cljsh) ("https://github.com/franks42/cljsh"), build it with lein, and start the lein repl in a terminal inside the cljsh repo directory:
  
  $ lein deps  
  $ lein lein plugin install lein-repls
  $ lein repls  
  REPL started; server listening on 0.0.0.0 port 12357  
  cljsh.core=>  

This will give you the standard repl interaction, but we will not use this repl-interface directly, but use the "server listening on 0.0.0.0 port 12357".

Then there are two scripts in the bin directory "cljsc" and "catcljsh", that you should put somewhere in your PATH.

That's all...

## Usage

In a different, separate terminal session, we can play with the cljsh interface.

### evaluate clojure-code passed as command line argument

	$ cljsh -c '(println "hello")'
	hello
	$

### to start a interactive repl-session:

	$ cljsh -ip
	"Welcome to your cljsh-lein-repl"
	cljsh.core=>


For examples of most supported features, please take a look at the [cljsh-test.sh](https://github.com/franks42/cljsh/blob/master/bin/cljsh-test.sh) ("https://github.com/franks42/cljsh/blob/master/bin/cljsh-test.sh") in the distro's bin directory. Even better, run cljsh-test.sh to see if all works well.


## Architecture & Implementation

By using socat, we can connect to lein's repl-server thru stdin and stdout.

The only way to communicate with the networked repl-server is thru sending clojure statements - no environment variables or commandline option are supported, which seems like a trivial statement to make, but it's important to stress that point. 

The cljsh client accepts clojure script code and files as command line options, and  sends those to the server for evaluation.

It writes all the clojure statements passed on the commandline to a tmp-file, and a load-file statement for that tmp-file is send to the server. In that way you have access to somewhat more meaningful debug info in the stacktrace in case of error.

The clojure file passed as an argument is dealt with in the same way by sending a load-file directive to the server.

Any code passed to cljsh thru stdin however, is also directly piped on to socat and the repl-server as one cannot predict the end of the statements. Debugging is somewhat more challenging in that case.

Cljsh does also send a few more clojure statements transparently to the repl-server that are related to functionality like turning the repl-prompt on, turning the eval-result printing on, communicating the command line options passed with a clojure file, and a kill-switch to indicate the last clojure statement has been eval'ed.
See the cljsh-test.sh for more explanations about those.

The following options must be added to the project.clj to make it work:

>  :repl-options [  
>  				;; set the repl-prompt to print nothing by default in cljsh.core.clj  
>  				:prompt cljsh.core/*repl-prompt*  
>  				;; do not print the eval-result by default in cljsh.core.clj  
>  				:print cljsh.core/*repl-result-print*  
>  				 ]  
>  				   
>  ;; hardcode the port number such that the cljsh-client can easily find it  
>  ;; (ideally, lein dynamically maintains the port number used by the repl-server in some "." file such that cljsh can pick it up)  
>  :repl-port 12357  
>  :repl-host "0.0.0.0"  
>    
>  ;; have to bring-in the cljsh.core ns in order to refer to the vars in the options.  
>  :project-init (require 'cljsh.core)  

In the cljsh.core.clj file, the repl-prompt and the eval-result printing is maintained on a per thread basis. It feels like a bit of a hack to associate the repl-session threads explicitly with the prompt/eval-print functions... It may make more sense to maintain them in the (binding ...) context of the repl creation, but that requires changes in the leiningen code... If this effort gets serious, then that may be the right way forward.

## License

Copyright (C) 2011 - Frank Siebenlist

Distributed under the Eclipse Public License, the same as Clojure
uses. See the file COPYING.
