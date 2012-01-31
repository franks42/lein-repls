#CLJSH: A lightweight Clojure Shell - a bash-shell client that uses socat and optionally rlwrap, to interact with a persistent repl-server.

Cljsh is a bash shell script that interacts with a persistent Leiningen's networked repl-server. It allows the user to submit Clojure statement and Clojure script files to the persistent networked repl for evaluation. The script uses socat to make the networked repl appear local: the repl-server's stdin and stdout are transparently extended to cljsh. Socat also makes this client lightweight and fast, very much like the ruby-based cake-client or nailgun. The Clojure statements are sent thru socat to the persistent Leiningen-repl-server, and the results are brought back thru socat to stdout.

The advantage of using socat and the networked repl is that there is no real protocol - or no protocol different from the normal repl-interaction: feed forms in thru stdin to the clojure-reader, and have the results or printed side-effect returned on stdout. This cljsh approach is different from cake, nailgun, swank and nrepl, which have true client-server protocols that arguably make those apps more powerful and more complicated.

The repl-server is based on Leiningen's native "repl" task, which is basically refactored as a true plugin "repls", to which a number of hooks are added to turn the repl-prompt and eval-result printing on and off. By not printing the prompt and eval-result, it's easier to write clojure-scripts that rely on its side-effects like printing to stdout. "repls" is installed and run as a normal Leiningen plugin (browse clojars for the latest "lein-repls" version available):

  $ lein plugin install repls 1.6.0  
  $ lein repls  
  
cljsh's main purpose is sending clj-statements and/or clj-files to the persistent repl. That clj-code is specified as command line arguments like:
  
  $ cat three.clj | cljsh -c '(println "one")' -f two.clj - four.clj -args  
	
The sequence of positional arguments determine the evalation sequence, where stdin is indicated by "-" (default last). The first non-option should indicate a clj-file with optional args.
(see cljsh -h) The options should reflect most clojure invocation flavors.

In addition, cljsh also offers an interactive repl mode, that is similar to the other repls out there. The difference again is that it's lightweight and allows for initialization scripts before the interactive session. In addition, it will use rlwrap with word completion. The word completion file can easily be updated to reflect the context of your session. (it still is a poor-man's completion, though, compared to "real" context sensitive completers as in emacs...). It may also work with JLine, but I have not tested that.

## Install

"cljsh" needs an installed version of "socat" and optionally "rlwrap".
An easy way is thru ports/macports on macosx, but substitute your own brewing mechanism as you like:
  
  $ sudo port install socat  
  $ sudo port install rlwrap  


The "repls" plugin is installed thru the standard Leiningen mechanism:
  
  $ lein plugin install lein-repls 1.6.0  
  $ lein repls  
  REPL started; server listening on 0.0.0.0 port 12357  
  user=>  

This will start the persistent repl server, and will give you a "console" with a standard repl interaction. cljsh will use that repl server listening on the indicated port.

Lastly, you will have to download the cljsh shell script and put it somewhere on your path:

  curl https://raw.github.com/franks42/lein-repls/master/bin/cljsh.sh > cljsh  
  chmod +x cljsh  
	mv cljsh /somewhere-on-your-path/cljsh  
	
Alternatively, you can clone the github repo: "https://github.com/franks42/lein-repls"
	
That's all... you're ready to repl.

## Usage

Go to one of your clj-project, and start the repls server:

	$ lein repls  
	REPL started; server listening on 0.0.0.0 port 12357 
	user=>  
	
In a different, separate terminal session, we will work with the cljsh repls-client. Make sure you are within the project's directory tree when you invoke cljsh, such that cljsh will automatically pickup the server's port number.

### evaluate clojure-code passed as command line argument

	$ cljsh -c '(println "hello")'
	hello
	$

### to start a interactive repl-session:

	$ cljsh -r
	"Welcome to your cljsh-lein-repl"
	user=>


For examples of most supported features, please take a look at the [cljsh-test.sh](https://raw.github.com/franks42/lein-repls/master/bin/cljsh-test.sh) ("https://raw.github.com/franks42/lein-repls/master/bin/cljsh-test.sh") in the distro's bin directory. Even better, run cljsh-test.sh to see if all works well.


## Architecture & Implementation

By using socat, we can connect to lein's repl-server thru stdin and stdout.

The only way to communicate with the networked repl-server is thru sending clojure statements - no environment variables or commandline option are supported, which seems like a trivial statement to make, but it's important to stress that point. 

The cljsh client accepts clojure script code and files as command line options, and  sends those to the server for evaluation.

It writes all the clojure statements passed on the commandline to a tmp-clj-file. All clj-file command line directives are added to that tmp-clj-file as load-file clj-statements. After the command line options processing, that tmp-clj-file is sent to the repl server for eval over stdin, and the results and printed output is received back on stdout.

The clj-code passed in thru stdin to cljsh, is also piped-thru to the repl-server. The positional "-" option determines when the stdin-clj-code is processed with respect to the other clj-statement and clj-file.

Cljsh does also send a few more clojure statements transparently to the repl-server that are related to functionality like turning the repl-prompt on, turning the eval-result printing on, communicating the command line options passed with a clojure file, and a kill-switch to indicate the last clojure statement has been eval'ed.
See the cljsh-test.sh for more explanations about those.

## License

Copyright (C) 2011 - Frank Siebenlist

Distributed under the Eclipse Public License, the same as Clojure
uses. See the file COPYING.
