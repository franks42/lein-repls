#!/bin/bash
#------------------------------------------------------------------------------
# Copyright (c) Frank Siebenlist. All rights reserved.
# The use and distribution terms for this software are covered by the
# Eclipse Public License 1.0 (http://opensource.org/licenses/eclipse-1.0.php)
# which can be found in the file COPYING at the root of this distribution.
# By using this software in any fashion, you are agreeing to be bound by
# the terms of this license.
# You must not remove this notice, or any other, from this software.
#------------------------------------------------------------------------------

set -v   # turn on verbose - easy for verifying expected output 

# cljsh-test.sh is a bash shell script that tests most non-interactive use cases for cljsh.

# Use the following command to capture the annotated output of this script in a log-file
# ./cljsh-test.sh  > cljsh-test.log 2>&1

# all clojure scripts are passed to the "lein repl" server over the network/loopback 
# for eval, and the output is brought back to stdout.

# cljsh -h will give help info and does some basic diagnostics

# note that the lein-repls server must be running for cljsh to do real work
# you can always start with cljsh -l to ensure the repls-server is running
cljsh -l

#------------------------------------------------------------------------------
# print out version info so we can record what we're using 
# real version numbers will vary depending on what you have installed:
cljsh -v
#------------------------------------------------------------------------------
# cljsh version: 1.9.6 and lein-repls version: 1.9.6
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# evaluate clojure-code passed as command line argument with -c or -e
cljsh -c '(println "=> hello")'
#------------------------------------------------------------------------------
# => hello
#------------------------------------------------------------------------------
# multiple statements can be added thru multiple -c directives
cljsh -c '(println "=> hello")' -c '(println "=> there")'
#------------------------------------------------------------------------------
# => hello
# => there
#------------------------------------------------------------------------------

# Note that by default, the eval results are not printed, which can be confusing:
cljsh -c '"=> hi - you cannot see me"'
#------------------------------------------------------------------------------
# => (...nothing...)
#------------------------------------------------------------------------------

# We can turn on the eval result printing with the -p flag:
cljsh -pc '"now you can see me"'
#------------------------------------------------------------------------------
# "now you can see me"
#------------------------------------------------------------------------------

# a disadvantage of the eval result printing is that you get those results (line "nil"s)
# in your output mixed together with what you actually explicitly "print":
cljsh -pc '(println "=> this is followed by a nil on the next line as the result from evaluating println")'
#------------------------------------------------------------------------------
# => this is followed by a nil on the next line as the result from evaluating println
# nil
#------------------------------------------------------------------------------

# by turning the eval result printing off (default), the only thing printed is what we explicitly write to stdout
cljsh -c '(println "=> this is NOT followed by a nil on the next line")'
#------------------------------------------------------------------------------
# => this is NOT followed by a nil on the next line
#------------------------------------------------------------------------------

# cljsh interacts with a persistent repl - any changes to the repl-state are preserved across cljsh invocations:
cljsh -pc '(defn jaja [t] (println t))'
#------------------------------------------------------------------------------
#  #'user/jaja
#------------------------------------------------------------------------------
cljsh -c '(jaja "=> hello again")'
#------------------------------------------------------------------------------
# => hello again
#------------------------------------------------------------------------------

# we can pipe the clojure code in thru stdin:
echo '(println "=> coming in from the left...")' | cljsh
#------------------------------------------------------------------------------
# => coming in from the left...
#------------------------------------------------------------------------------

# or both as command line and piped code:
echo '(println "=> then from pipe")' | cljsh -c '(println "=> first from arg")'
#------------------------------------------------------------------------------
# => first from arg
# => then from pipe
#------------------------------------------------------------------------------

# we can also read from a clojure file as the first non-option argument:
echo '(println "=> this is from the tst.clj file")' > tst.clj
cljsh tst.clj
#------------------------------------------------------------------------------
# => this is from the tst.clj file
#------------------------------------------------------------------------------

# or we can read that clj-file with the -f or -i option:
echo '(println "=> one (file)")' > tst1.clj
echo '(println "=> two (file)")' > tst2.clj
echo '(println "=> three (file)")' > tst3.clj
echo '(println "=> four (file)")' > tst4.clj
cljsh -i tst1.clj -f tst2.clj tst3.clj
#------------------------------------------------------------------------------
# => one (file)
# => two (file)
# => three (file)
#------------------------------------------------------------------------------

# watch the sequence of code eval (note that stdin is last by default):
echo '(println "=> four (pipe)")' | cljsh -f tst1.clj -e '(println "=> two (arg)")' tst3.clj
#------------------------------------------------------------------------------
# => one (file)
# => two (arg)
# => three (file)
# => four (pipe)
#------------------------------------------------------------------------------

# the code is evaluated in the same sequence as the options on the command line
# we can insert "-" in the option sequence to set the index of eval for stdin:
echo '(println "=> two (pipe)")' | cljsh  -e '(println "=> one (arg)")' - -f tst3.clj tst4.clj
#------------------------------------------------------------------------------
# => one (arg)
# => two (pipe)
# => three (file)
# => four (file)
#------------------------------------------------------------------------------

# the first argument that is not (part of) an option should be a single clj-file
# additional args after the clj-file name are accessed thru: "@@cljsh.core/cljsh-file-command-line-args",
# the clj-file name itself is retrieved with: "@@cljsh.core/cljsh-file-command-path":
# both are inheritable-thread-local atom-vars, and the args are in an vector ready for use in cli.tools
echo '(println "=> clj-file path and additional clj-file args: " @@cljsh.core/cljsh-file-command-path @@cljsh.core/cljsh-file-command-line-args)' > tst.clj
cljsh tst.clj -a -b -c why -def not 
#------------------------------------------------------------------------------
# => clj-file path and additional clj-file args:  /Users/franks/Development/Clojure/lein-repls/tst.clj [-a -b -c why -def not]
#------------------------------------------------------------------------------

# the original command path for cljsh and its line options/args vector are also available thru 
# @@cljsh.core/cljsh-command-path and @@cljsh.core/cljsh-command-line-args:
# (as is cljsh's environment @@cljsh.core/cljsh-env, but that is a bit big to print out here...)
echo '(println "=> command path and args: " @@cljsh.core/cljsh-command-path @@cljsh.core/cljsh-command-line-args)' > tst.clj
cljsh -p tst.clj -a -b -c why -def not 
#------------------------------------------------------------------------------
# => command path and args:  /Users/franks/Development/Clojure/lein-repls/bin/cljsh [-p tst.clj -a -b -c why -def not]
# nil
#------------------------------------------------------------------------------

# another option is to embed clojure code in an executable script file thru #!:
echo '#!/usr/bin/env cljsh' > tst.cljsh
echo '(println "=> one")' >> tst.cljsh
echo '(println "=> and that is two")' >> tst.cljsh
chmod +x tst.cljsh
./tst.cljsh
#------------------------------------------------------------------------------
# => one
# => and that is two
#------------------------------------------------------------------------------

# we also have the command line arguments available thru "cljsh.core/*cljsh-command-line-args*":
echo '#!/usr/bin/env cljsh' > tst.cljsh
echo '(println "=> args passed with script:" @@cljsh.core/cljsh-file-command-path @@cljsh.core/cljsh-file-command-line-args)' >> tst.cljsh
chmod +x tst.cljsh
./tst.cljsh -a b -cd efg
#------------------------------------------------------------------------------
# => args passed with script: /Users/franks/Development/Clojure/lein-repls/tst.cljsh [-a b -cd efg]
#------------------------------------------------------------------------------

# alternatively, we can use the "Here Document" construct to easily write clojure code in bash shell scripts
# either without parameter substitution:
ONE="one"
cljsh <<"EOCLJ"
(println "=> ${ONE}")
(do 
	(println "=> two")
	(prn "=> three"))
EOCLJ
#------------------------------------------------------------------------------
# => ${ONE}
# => two
# "=> three"
#------------------------------------------------------------------------------

# or with the shell's parameter substitution when we needed:
ONE="one"
cljsh <<EOCLJ
(println "=> ${ONE}") 
(do 
	(println "=> two")
	(prn "=> three"))
EOCLJ
#------------------------------------------------------------------------------
# => one
# => two
# "=> three"
#------------------------------------------------------------------------------

# we can also feed any arbitrary data stream thru stdin that we process with a clojure script, 
# but we have to indicate that what comes in thru stdin is not clojure code with the -t option:
echo "=> this is a stream of text and no clojure code" | cljsh -t -c '(prn (read-line))'
#------------------------------------------------------------------------------
# "=> this is a stream of text and no clojure code"
#------------------------------------------------------------------------------

# processing a text stream allows you to easily write unix-like filters in clojure:
# prepare test file with text:
echo "=> this is a stream of text" > tst.txt
echo "=> all lower case" >> tst.txt
echo "=> that wants to be upper'ed" >> tst.txt
# unfortunately, the #! is not portable across unixes...
# ideally we would use "#!/usr/bin/env cljsh -t", which works on bsd/macos,
# but linux doesn't support more than one option, so -t isn't recognized
# but as always, one level of indirection solves everything :-( :
# instead of -t option, we set the env-variable CLJ_STDIN_TEXT before we call our cljsh-script:
cat <<EOBSC > upper-cljsh.sh
#!/bin/bash
env CLJ_STDIN_TEXT=1 "$(pwd)/upper-without-t.cljsh"
EOBSC
chmod +x upper-cljsh.sh
# now we can write out clj-code in the separate upper-without-t.cljsh file.
# remember to close *in* in your script otherwise you'll wait a looong time
# (note that there is no way to add a kill-switch automagically at the end of the code...)
cat <<"EOCLJ" > upper-without-t.cljsh
#!/usr/bin/env cljsh
(require 'clojure.string)
(doseq [line (line-seq (java.io.BufferedReader. *in*))] 
  (prn (clojure.string/upper-case line)))
(.close *in*)
EOCLJ
chmod +x upper-without-t.cljsh
# test the filter:
cat tst.txt | ./upper-cljsh.sh
#------------------------------------------------------------------------------
# "=> THIS IS A STREAM OF TEXT"
# "=> ALL LOWER CASE"
# "=> THAT WANTS TO BE UPPER'ED"
#------------------------------------------------------------------------------

# see if it behaves well as a true unix filter by lowering it again:
cat tst.txt | ./upper-cljsh.sh | tr '[:upper:]' '[:lower:]'
#------------------------------------------------------------------------------
# "=> this is a stream of text"
# "=> all lower case"
# "=> that wants to be upper'ed"
#------------------------------------------------------------------------------

# that's all folks... enjoy!
# EOF "cljsh-test.sh"
