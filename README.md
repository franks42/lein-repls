#CLJSH & REPLS: "cljsh" is a lightweight client that sends clojure statements/files to a persistent repl-server "repls" for evaluation. 

## Release notes

Cljsh (> 1.9.2) and repls (> 1.9.2-SNAPSHOT) have the following new features:

- cljsh automatically finds the repls-server that is started for the project (i.e. cljsh and repls both should be started from within the project's directory tree), so no need to keep track of port numbers and such. A single project can also be designated as "global" with cljsh (-G), such that any subsequent time a cljsh can indicate (-g) that it wants to interact with that global-project's repls-server. (a single project can be used as *the* scripting environment for all general clojure scripts os-wide)

- self-update feature in cljsh (-U) that allows you to automagically download&install the latest stable cljsh version from github. (provided you installed cljsh in a place where cljsh can r&w).

- update feature in cljsh for the lein plugin "repls" (-u) that automagically shows the available version for the lein plugin at clojars and will subsequently uninstall the current one and install the chosen one. (you may want to stay away from the SNAPSHOT versions...)

- automatic upstarting from cljsh (-l) of the repls-server in a separate terminal session when it's not running yet. (no more need to start the repls-server with "lein repls" in a new terminal session by hand )

- Stopping of the repls-server thru cljsh (-L). (stopping and restarting (-Ll) gives you essentially a restart of your project's image)

- Tested to install cljsh&repls and run the test script successfully on both MacOSX and LUbuntu 11.10 (log of Lubuntu install sessions is at "https://gist.github.com/1842625" - don't forget to set the XTERM environment variable to enable the auto-start of repls-server.) - sorry, but I will not test other OS-flavors but I'm happy to accept mods that would accomodate even windows...


## Intro.

The purpose of the lightweight "cljsh" and repls-server combination is to extend the use of clojure to anywhere where you would normally use scripting languages, like bash, python, ruby, and even perl... With cljsh, you can write unix-style filters, macosx automation scripts, bbedit/textmate scripts, growl notifications, etc. 

"Cljsh" is client shell script that interacts with a persistent repls-server. It allows the user to submit clojure-code to the server for evaluation, from statement and files that are specified as command line arguments or piped-in thru stdin. The results and/or output from the evaluation are communicated back to the client and written to stdout.

"Repls" is a leiningen plugin based on the native "lein repl" code. The few changes to the lein-repl code are related to functionality to toggle the printing of a prompt and eval-result, and the redirecting of stderr to a console. "lein repls" provides essentially a persistent, networked repl that accepts clojure statement from the socket connection and writes the eval-results and output back to that socket.

Note that the repls-server is persistent, meaning that state changes made by one cljsh invocation will change the project's running image: the next cljsh-script will see those changes. This allows you to maintain state in the project's image with all the clojure mechanisms offered by vars, atoms, refs, etc. (...which you of course will loose when the jvm is stopped, unless you wrote that state to real persistent storage...). Multiple cljsh instances can send different clj-statements to the repls-server concurrently as each invocation is evaluated within a separate session defined by a system-thread. This is also true for (multiple and concurrent) cljsh's interactive repl sessions (-r). All this concurrency can potentially bite you... so be aware. Probably unnecessary to mention that cljsh and repls' persistent server can also be used for incremental clojure-development...

Under the covers, cljsh is a bash shell-script that uses "socat" to make the networked repl appear local: the repl-server's stdin and stdout are transparently extended to cljsh's. Deploying socat for the repls-server connection, also makes this client lightweight and fast, very much like the ruby-based cake-client or nailgun. The clojure statements are sent thru socat to the persistent repls-server, and the results are brought back thru socat to stdout.

The advantage of using socat and the networked interactive repl is that there is no real protocol - or no protocol different from the normal interactive repl-interaction: feed forms in thru stdin to the clojure-reader, and have the results or printed side-effect returned on stdout. Think of it as some sort of telnet session with the interactive repl where you can turn the prompt off. This cljsh approach is different from cake, nailgun, swank and nrepl, which have true client-server protocols that arguably make those apps more powerful. However, for the basic use cases that cljsh tries to address, this basic interactive repl-protocol seems to do its job well.

## Install

"cljsh" needs an installed version of "leiningen", "socat" and optionally "rlwrap".
For info about leiningen see "https://github.com/technomancy/leiningen" - please do not come back until you have lein up&running...
An easy way to install socat and rlwrap is thru ports/macports on macosx, but substitute your own brewing mechanism as you like:


    $ sudo port install socat  
    $ sudo port install rlwrap  


Now, you will have to download the cljsh shell script and put it somewhere on your path:  


   	$ curl https://raw.github.com/franks42/lein-repls/stable/bin/cljsh > /tmp/cljsh  
   	$ chmod +x /tmp/cljsh  
   	$ mv /tmp/cljsh /somewhere-on-your-path/cljsh  


If your cljsh is allowed to r&w its own instance, then you can use its auto-update feature later to obtain the latest stable version from github:

    $ cljsh -u
    ... self explanatory process ;-)...
    
On my macosx system, I have installed cljsh in ~/opt/bin/, which is on my PATH. In addition, I've made a symbolic link to /usr/bin/cljsh because macosx is somewhat non-standard in the reading of .bashrc and such :-(.

There are two ways to install the "repls" plugin. The recommended installation of the repls plugin is thru cljsh, which will automate much of it for you, and can be used to easily upgrade in the future:

    $ cljsh -U
    ... self explanatory process ;-)...

The second, alternative way to install repls is thru the standard Leiningen mechanism:

    $ lein plugin install lein-repls 1.9.0  

In that case, you will have to know lein-repls latest&greatest version number, which you can find at clojars.org and search for "lein-repls".

	
That's all... now you're ready to repls.

## Usage & examples

"cd" to one of your clj-project directory trees, and start the repls server thru cljsh:

    $ cljsh -l

which will automatically open up a new terminal window and session with:

		$ lein repls  
		REPL started; server listening on 0.0.0.0 port 12357 
		user=>  


The persistent repl server is now running in that second terminal session, and will give you a "console" with a standard repl interaction. cljsh will use that repl server listening on the indicated port.

In the terminal session where we invoked cljsh, we will use cljsh to send clj-code to the repls-server. Just make sure that you stay within the project's directory tree when you invoke cljsh, such that cljsh will automatically pickup the server's port number.


### evaluate clojure-code passed as command line argument

"cljsh"'s main purpose is sending clj-statements and/or clj-files to the persistent repl. That clj-code is specified as command line arguments like:

  	$ cat three.clj | cljsh -c '(println "one")' -f two.clj - four.clj -args  

The sequence of positional arguments determine the evalation sequence, where stdin is indicated by "-" (default last). The first non-option should indicate a clj-file with optional args. (see cljsh -h).


### to start a interactive repl-session:

In addition, cljsh also offers an interactive repl mode (-r), that is similar to the other interactive repls out there. The difference is that it's lightweight, allows for initialization scripts before the interactive session, and you can run as many as you want concurrently. In addition, it will use rlwrap with word completion. The word completion file can easily be updated to reflect the context of your session (-w). (it still is a poor-man's completion, though, compared to "real" context sensitive completers as in emacs...). It may also work with JLine, but I have not tested that.

    $ cljsh -r
    "Welcome to your Clojure (1.3.0) lein-repls (1.9.4-SNAPSHOT) client!"
    user=>

The best way to learn about all the options is to use the command line help (cljsh -h).
For examples of most supported features, please take a look at the [cljsh-test.sh](https://raw.github.com/franks42/lein-repls/master/bin/cljsh-test.sh) ("https://raw.github.com/franks42/lein-repls/master/bin/cljsh-test.sh") in the distro's bin directory. Even better, run cljsh-test.sh to see if all works well.


## Architecture & Implementation

By using socat, we can connect to lein's repl-server thru stdin and stdout.

The only way to communicate with the networked repl-server is thru sending clojure statements - none pf the client's environment variables or commandline option are available on the server side, unless we explicitly communicate those, which seems like a trivial statement to make, but it's important to stress that point. 

The cljsh client accepts clojure script code and files as command line options, and  sends those to the server for evaluation.

It writes all the clojure statements passed on the commandline to a tmp-clj-file. All clj-file command line directives are added to that tmp-clj-file as load-file clj-statements. After the command line options processing, that tmp-clj-file is sent to the repl server for eval over stdin, and the results and printed output is received back on stdout.

The clj-code passed in thru stdin to cljsh, is also piped-thru to the repl-server. The positional "-" option determines when the stdin-clj-code is processed with respect to the other clj-statement and clj-file.

Cljsh does also send a few more clojure statements transparently to the repl-server that are related to functionality like turning the repl-prompt on, turning the eval-result printing on, communicating the client's environment variables and command line options passed with a clojure file, and a kill-switch to indicate that the last clojure statement has been eval'ed.
See the cljsh-test.sh for more explanations about some of those features.

## Acknowledgements

Thanks to "technomancy" for leiningen, "ninjudd" for cake, and the irc-clojure community for the great real-time support.

## License

Copyright (C) 2011 - Frank Siebenlist

Distributed under the Eclipse Public License, the same as Clojure
uses. See the file COPYING.
