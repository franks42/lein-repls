#!/bin/sh
#
# Copyright (c) Frank Siebenlist. All rights reserved.
# The use and distribution terms for this software are covered by the
# Eclipse Public License 1.0 (http://opensource.org/licenses/eclipse-1.0.php)
# which can be found in the file COPYING at the root of this distribution.
# By using this software in any fashion, you are agreeing to be bound by
# the terms of this license.
# You must not remove this notice, or any other, from this software.

# cljsh is a bash shell script that interacts with Leiningen's networked repl.
# It allows the user to submit Clojure statement and Clojure script files
# to the persistent networked repl for evaluation.

CLJSH_VERSION="0.3"

# send kill-switch as final separate statement to end the repl session/connection gracefully
LEIN_REPL_KILL_SWITCH=':leiningen.repl/exit'

# rlwrap's clojure word completion in the repl use the following file
CLJ_WORDS_FILE=${CLJ_WORDS_FILE:-"$HOME/.clj_completions"}

# ideally should be able to deduce repl-server parameters from lein... 
# for now just hard-code those values, which should match those in project.clj

export LEIN_REPL_INITFILE=${LEIN_REPL_INITFILE:-"${HOME}/.lein_repls"}
if [ -f "${LEIN_REPL_INITFILE}" ]; then . "${LEIN_REPL_INITFILE}" ; fi

export LEIN_REPL_HOST=${LEIN_REPL_HOST:-"0.0.0.0"}
export LEIN_REPL_PORT=${LEIN_REPL_PORT:-"12357"}

# CLJSH_MAXTIME is the maximum time a task is allowed to take before socat will assume that that task is finished
# the time is measured between the subsequent reads from stdin or writes to stdout by that task
# if you expect clojure programs to take more than 10min (default 600s) inbetween i/o, increase CLJSH_MAXTIME appropriately
# (shorter tasks force the closing of the connection by sending a kill-switch at the end of the script, i.e. :leiningen.repl/exit)
export CLJSH_MAXTIME=${CLJSH_MAXTIME:-"600"}

# basename component for tmp-files
CLJ_TMP_FNAME=`basename $0`

# determine what is connected to the stdin of this script
CLJSH_STDIN="REDIRECTED"
if [[ -p /dev/stdin ]]; then CLJSH_STDIN="PIPE"; fi
if [[ -t 0 ]]; then CLJSH_STDIN="TERM"; fi

# command line option processing
CLJ_REPL=0; CLJ_EVAL_PRINT=0
CLJ_CODE=""; CLJ_REPL_CODE=""; CLJ_PRINT_CODE=""
while getopts "iwphtm:c:s:" opt; do
  case $opt in
    c) 	# clojure code statements expected as options value
    	if [ "$CLJ_CODE" ]; then
    		CLJ_CODE="$CLJ_CODE $OPTARG";   # concat to allow for multiple -c code
    	else
    		CLJ_CODE="$OPTARG";
    	fi
      	;;
    m) 	# maximum time for a task expected as option value
    	CLJSH_MAXTIME="$OPTARG";
    	;;
    s) 	# Leiningen repl server port
    	LEIN_REPL_PORT="$OPTARG";
    	;;
    i) 	# interactive/repl so turn on the printing of a repl-prompt
    	CLJ_REPL=1
      	CLJ_REPL_CODE='(cljsh.core/set-prompt cljsh.core/repl-ns-prompt)'
      	;;
    w) 	# refresh word completion file with current repl-context
    	CLJ_REFRESH_COMPLETION="1"
      	;;
    t) 	# text/arbitrary data and no clojure-code expected from stdin, so don't eval stdin.
    	CLJ_STDIN_TEXT=1
      	;;
    p) 	# turn on printing of eval-results by the repl.
    	CLJ_EVAL_PRINT=1
      	CLJ_PRINT_CODE='(cljsh.core/set-repl-result-print prn)'
      	;;
    h)  echo "Usage: `basename $0` [OPTIONS] [FILE]" >&2;
    	echo "Clojure Shell version: \"${CLJSH_VERSION}\"" >&2;
    	echo "cljsh sends clojure code to leiningen's repl-server for evaluation." >&2;
    	echo "printed output and optional eval results (-p) are returned thru stdout" >&2;
    	echo "clojure code is passed on command line (-c), in file, or thru stdin" >&2;
    	echo "optionally, arbitrary data can be passed in thru stdin (-t)" >&2;
    	echo "cljsh also has an interactive repl mode (-i) with code completion support (-w)" >&2;
		# do simple check to see if repl-server can be seen listenen
		if [ "$(netstat -an -f inet |grep '*.'${LEIN_REPL_PORT})" == "" ]; then
			echo "ERROR: no \"lein repl\" server listening on port ${LEIN_REPL_PORT} (use -s or \$LEIN_REPL_PORT for different port)" >&2;
		else
			echo "\"lein repl\" server most probably is listening on port ${LEIN_REPL_PORT}" >&2;
		fi
		hash socat 2>&-  || { echo >&2 "ERROR: \"socat\" is require for cljsh but not installed.";}
		hash rlwrap 2>&- || { echo >&2 "ERROR: \"rlwrap\" is require for cljsh but not installed.";}
		echo "`basename $0` -i                         # -i interactive repl-shell with namespace-prompt" >&2;
		echo "`basename $0` -p                         # -p print eval results to stdout (discarded by default)" >&2;
		echo "`basename $0` -c clojure-code            # -c eval the clojure-code in repl-server" >&2;
		echo "`basename $0` clojure-file               # load&eval clojure-file in repl-server" >&2;
		echo "cat clojure-file | `basename $0`         # eval piped clojure-code in repl-server" >&2;
		echo "echo clojure-code | `basename $0`        # eval piped clojure-code in repl-server" >&2;
		echo "echo text | `basename $0` -t -c code     # -t input from stdin is arbitrary data, not code" >&2;
		echo "`basename $0` -w                         # -w refresh the clojure words for completion in repl" >&2;
		echo "`basename $0` -s repl-server-port        # -s repl server port (default ${LEIN_REPL_PORT} or use \$LEIN_REPL_PORT)" >&2;
		echo "`basename $0` -m task-max-time-sec       # -m set max time for task (default ${CLJSH_MAXTIME}sec)" >&2;
		echo "`basename $0` -h                         # -h this usage help plus diagnostic check & exit" >&2;
    	echo "---" >&2;
		echo "Docs & code at \"https://github.com/franks42/lein-repls\"" >&2;
      	exit 1
		;;
    \?) echo "Invalid option: -$OPTARG" >&2
    	exit 1
    	;;
    :)	echo "Option -$OPTARG requires an argument." >&2
      	exit 1
      	;;
  esac
done

# if needed, update the clojure completion words file before we do anything else
if [ ${CLJ_REFRESH_COMPLETION} ]; then
cljsh <<EOCLJ
(def completions (mapcat (comp keys ns-publics) (all-ns)))
(with-open [f (java.io.BufferedWriter. (java.io.FileWriter. (str "${CLJ_WORDS_FILE}")))]
    (.write f (apply str (interpose \newline completions))))
(println "Clojure completion words updated")
(.close *in*)
;:leiningen.repl/exit
EOCLJ
fi

# only include the rlwrap completions file directive if that file actually exists
CLJ_FLAG_WORDS=""
if [ -f ${CLJ_WORDS_FILE} ]; then CLJ_FLAG_WORDS="-f ${CLJ_WORDS_FILE}"; fi

# after options processing with getopts, the remaining args are expected to be an optional single clojure-file name
# followed by optional arguments associated with that clojure file
# shift past the args processed by getopts
shift $(($OPTIND-1))
# first arg should be a clojure file name followed by associated args
CLJFILE="$1"
CLJ_LOAD_CODE=""
if [ $CLJFILE ]; then
	if [ -f "$CLJFILE" ]; then   # check if file actually exists
		# now write a load-file statement for that file in a tmp-file
		CLJFNAME="$( basename $CLJFILE )"
		CLJFILEFP=$( cd "$( dirname $CLJFILE )" && pwd )/"$CLJFNAME"  # absolute file path
		CLJ_LOAD_CODE='(load-file "'${CLJFILEFP}'")'
		# assign cljsh.core/*cljsh-args* to the args associated with that clojure file
		shift   #  now we're left with the additional argument that go with the clojure file
		CLJ_ARGS_CODE='(def ^:dynamic cljsh.core/*cljsh-args* "'${CLJFILEFP}' '$*'")'
		CLJ_ARGS_CODE=`echo $CLJ_ARGS_CODE | sed s/\"/\\\\\"/g`
	else
		echo "ERROR: \"$CLJFILE\" is no valid file-path for a clojure-file." >&2
		exit 1
	fi
fi

# by writing the clojure code first in a file that is loaded for eval, we get the benefit of line# debug
# write the clojure code for repl, eval-print and command-line code into a tmp-file
CLJTMPFILE=`mktemp -t ${CLJ_TMP_FNAME}` || exit 1
# /bin/echo -n "$CLJ_PRINT_CODE" $CLJ_ARGS_CODE "$CLJ_REPL_CODE" "$CLJ_CODE" >> $CLJTMPFILE
if [ "$CLJ_PRINT_CODE" ]; then /bin/echo "$CLJ_PRINT_CODE"  >> $CLJTMPFILE; fi
if [ "$CLJ_ARGS_CODE" ];  then /bin/echo "$CLJ_ARGS_CODE"   >> $CLJTMPFILE; fi
if [ "$CLJ_REPL_CODE" ];  then /bin/echo "$CLJ_REPL_CODE"   >> $CLJTMPFILE; fi
if [ "$CLJ_CODE" ];       then 
	/bin/echo "$CLJ_CODE"   >> $CLJTMPFILE;
	if [ "$CLJ_STDIN_TEXT" = 1 ]; then
		# if we expect arbitrary data from stdin, then we can close stdin and send the kill-switch at the end
		/bin/echo '(.close *in*)' >> $CLJTMPFILE;
		/bin/echo LEIN_REPL_KILL_SWITCH >> $CLJTMPFILE;
	fi
fi

# write the load-file clojure statements into a separate tmp-file
CLJ_LOAD_TMP_CODE='(load-file "'${CLJTMPFILE}'")'
CLJTMPLOADFILE=`mktemp -t ${CLJ_TMP_FNAME}` || exit 1
# create the tmp-file for the load-file statements and the welcome message
/bin/echo -n  '(do ' >> $CLJTMPLOADFILE
/bin/echo -n  "$CLJ_LOAD_TMP_CODE" >> $CLJTMPLOADFILE
if [ "" != "$CLJ_LOAD_CODE" ]; then /bin/echo -n  "$CLJ_LOAD_CODE" >> $CLJTMPLOADFILE; fi
if [ "$CLJ_REPL" = 1 ]; then  # user wants an interactive REPL
	/bin/echo '"Welcome to your cljsh-lein-repl")' >> $CLJTMPLOADFILE;
else
	/bin/echo ')'     >> $CLJTMPLOADFILE;
fi

CLJKILLTMPFILE=`mktemp -t ${CLJ_TMP_FNAME}` || exit 1
/bin/echo ${LEIN_REPL_KILL_SWITCH} >> $CLJKILLTMPFILE;

###############################################################################

# lastly, we send the code to the persistent repl

if [ "$CLJ_REPL" = 1 ]; then  # user wants an interactive REPL

	# max task time doesn't seem to affect interactive repl, but does affect the delay of ctrl-d
	CLJSH_MAXTIME="0.1"
	
	rlwrap $CLJ_FLAG_WORDS -p Red -R -m " \ " -q'"' -b "(){}[],^%$#@\"\";:''|\\" catcljsh $CLJTMPLOADFILE -

else  # no REPL, nothing interactive

	if [ "$CLJSH_STDIN" = "TERM" ]; then
	
		catcljsh $CLJTMPLOADFILE $CLJKILLTMPFILE    # ignore the terminal as user doesn't want interactive-repl
		
	else
	
		if [ "$CLJ_STDIN_TEXT" = 1 ]; then   # arbitrary data and no code coming from stdin
		
			# user's code is responsible for closing *in* to indicate eof as we cannot deduce it to use the kill-switch
			catcljsh $CLJTMPLOADFILE - ;
			
		else   # expect clojure code to be piped-in from stdin and kill/end the session after that
		
			# because the repl keeps reading from stdin for clojure-statements, we can append the kill-switch at the end
			catcljsh $CLJTMPLOADFILE - $CLJKILLTMPFILE ;
			
		fi
	fi
fi

# EOF "cljsh.sh"