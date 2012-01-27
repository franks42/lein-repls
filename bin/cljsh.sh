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

CLJSH_VERSION="0.7"

# Clojure code snippets
# send kill-switch as final separate statement to end the repl session/connection gracefully
CLJ_EVAL_PRINT_CODE='(cljsh.core/set-repl-result-print prn)'
CLJ_REPL_PROMPT_CODE='(cljsh.core/set-prompt cljsh.core/repl-ns-prompt)'
LEIN_REPL_KILL_SWITCH=':leiningen.repl/exit'

# rlwrap's clojure word completion in the repl use the following file
RLWRAP_CLJ_WORDS_FILE=${RLWRAP_CLJ_WORDS_FILE:-"$HOME/.clj_completions"}

# determine the directory of the associated project.clj, or $HOME if none.
export LEIN_PROJECT_DIR=$(
	NOT_FOUND=1
	ORIGINAL_PWD="$PWD"
	while [ ! -r "$PWD/project.clj" ] && [ "$PWD" != "/" ] && [ $NOT_FOUND -ne 0 ]
	do
			cd ..
			if [ "$(dirname "$PWD")" = "/" ]; then
					NOT_FOUND=0
					cd "$ORIGINAL_PWD"
			fi
	done
	if [ ! -r "$PWD/project.clj" ]; then cd "$HOME"; fi
	printf "$PWD"
)

export LEIN_REPL_INIT_FILE=${LEIN_REPL_INIT_FILE:-"${LEIN_PROJECT_DIR}/.lein_repls"}
if [ -f "${LEIN_REPL_INIT_FILE}" ]; then . "${LEIN_REPL_INIT_FILE}" ; fi

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
while getopts "irwpghtm:c:s:e:" opt; do
  case $opt in
    c) 	# clojure code statements expected as options value
    	if [ -n "${CLJ_CODE}" ]; then
    		CLJ_CODE="${CLJ_CODE}\n$OPTARG";   # concat with newline to allow for multiple -c code
    	else
    		CLJ_CODE="$OPTARG";
    	fi
      ;;
    e) 	# clojure code statements expected as options value (same as c))
    	if [ -n "${CLJ_CODE}" ]; then
    		CLJ_CODE="${CLJ_CODE}\n$OPTARG";   # concat with newline to allow for multiple -c code
    	else
    		CLJ_CODE="$OPTARG";
    	fi
      ;;
    m) 	# maximum time for a task expected as option value
    	CLJSH_MAXTIME="$OPTARG";
    	;;
    s)	# Leiningen repl server port
    	LEIN_REPL_PORT="$OPTARG";
    	;;
    r) 	# interactive/repl so turn on the printing of a repl-prompt
    	CLJ_REPL_PROMPT=1
    	CLJ_EVAL_PRINT=1
      ;;
    i) 	# interactive/repl so turn on the printing of a repl-prompt
    	CLJ_REPL_PROMPT=1
      ;;
    w) 	# refresh word completion file with current repl-context
    	CLJ_REFRESH_COMPLETION=1
      ;;
    t) 	# text/arbitrary data and no clojure-code expected from stdin, so don't eval stdin.
    	CLJ_STDIN_TEXT=1
      ;;
    g) 	# force a pickup of the "global" repls-server coordinates from the $HOME directory.
			if [ -r "${HOME}/.lein_repls" ]; then 
				. "${HOME}/.lein_repls" ; 
			else
				echo "ERROR: no global/default init file found at ${HOME}/.lein_repls" >&2 ;
      	exit 1;
			fi
      ;;
    p) 	# turn on printing of eval-results by the repl.
    	CLJ_EVAL_PRINT=1
      ;;
    h)  # print help text and do some basic diagnostics
    	echo "Usage: `basename $0` [OPTIONS] [FILE]" >&2;
    	echo "Clojure Shell version: \"${CLJSH_VERSION}\"" >&2;
    	echo "'cljsh' is a shell script that sends clojure code to a persistent socket-repls-server for evaluation." >&2;
    	echo "The repls-server is started in the project's directory thru 'lein repls'." >&2;
    	echo "Printed output and optional eval results (-p) are returned thru stdout." >&2;
    	echo "Clojure code is passed on command line (-c or -e), in file, or thru stdin" >&2;
    	echo "Optionally, arbitrary data can be passed in thru stdin (-t)." >&2;
    	echo "True '#!/usr/bin/env cljsh' clojure shell-script files are supported." >&2;
    	echo "'cljsh' also has an interactive repl mode (-r) with code completion support (-w)" >&2;
			# do simple check to see if repl-server can be seen listenen
			# lsof -P -p 37683 -i TCP:14331 -sTCP:LISTEN -t
			if [ "$(netstat -an -f inet |grep '*.*' | grep ${LEIN_REPL_PORT})" == "" ]; then
				echo "ERROR: no \"lein repls\" server listening on port ${LEIN_REPL_PORT} (use -s or \$LEIN_REPL_PORT for different port)" >&2;
			else
				echo "\"lein repls\" server most probably is listening on port ${LEIN_REPL_PORT}" >&2;
			fi
			hash socat 2>&-  || { echo >&2 "ERROR: \"socat\" is require for cljsh but not installed.";}
			hash rlwrap 2>&- || { echo >&2 "ERROR: \"rlwrap\" is require for cljsh but not installed.";}
			echo "`basename $0` -r                         # -r interactive repl session - equivalent of -ip " >&2;
			echo "`basename $0` -c clojure-code            # -c eval the clojure-code in repl-server (equivalent to -e)" >&2;
			echo "`basename $0` -e clojure-code            # -e eval the clojure-code in repl-server (equivalent to -c)" >&2;
			echo "`basename $0` clojure-file               # load&eval clojure-file in repl-server" >&2;
			echo "cat clojure-file | `basename $0`         # eval piped clojure-code in repl-server" >&2;
			echo "echo clojure-code | `basename $0`        # eval piped clojure-code in repl-server" >&2;
			echo "echo text | `basename $0` -t -c code     # -t input from stdin is arbitrary data, not code" >&2;
			echo "`basename $0` -i                         # -i interactive repl-shell with namespace-prompt (without print eval result)" >&2;
			echo "`basename $0` -p                         # -p print eval results to stdout (discarded by default)" >&2;
			echo "`basename $0` -w                         # -w refresh the clojure words for completion in repl" >&2;
			echo "`basename $0` -g                         # -g force a pickup of the \"global\" repls-server coordinates from \"~/.lein_repls\"" >&2;
			echo "`basename $0` -s repl-server-port        # -s repl server port (by default automatically set by 'lein repls')" >&2;
			echo "`basename $0` -m task-max-time-sec       # -m set max time for task (default ${CLJSH_MAXTIME}sec - see docs)" >&2;
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
if [ ${CLJ_REFRESH_COMPLETION:-0} -eq 1 ]; then
# 	cljsh -e '(require (quote cljsh.complete)) (doall (map println (sort (set (cljsh.complete/completions "")))))' > "${RLWRAP_CLJ_WORDS_FILE}"
	cljsh -e '(require (quote cljsh.completion)) (cljsh.completion/print-all-words)' > "${RLWRAP_CLJ_WORDS_FILE}"
fi

# only include the rlwrap completions file directive if that file actually exists
RLWRAP_CLJ_WORDS_OPTION=""
if [ -f "${RLWRAP_CLJ_WORDS_FILE}" ]; then RLWRAP_CLJ_WORDS_OPTION="-f ${RLWRAP_CLJ_WORDS_FILE}"; fi

# after options processing with getopts, the remaining args are expected to be an optional single clojure-file name
# followed by optional arguments associated with that clojure file
# shift past the args processed by getopts
shift $(($OPTIND-1))
# first arg should be a clojure file name followed by associated args
CLJFILE="$1"
CLJ_LOAD_CODE=""
if [ -n "$CLJFILE" ]; then
	if [ -f "$CLJFILE" ]; then   # check if file actually exists
		# now write a load-file statement for that file in a tmp-file
		CLJFNAME="$( basename $CLJFILE )"
		CLJFILEFP=$( cd "$( dirname $CLJFILE )" && pwd )/"$CLJFNAME"  # absolute file path
		CLJ_LOAD_CODE='(load-file "'${CLJFILEFP}'")'
		# assign cljsh.core/*cljsh-command-line-args* to the args associated with that clojure file
		shift   #  now we're left with the additional argument that go with the clojure file
		CLJ_ARGS_CODE='(binding [*ns* (find-ns (quote cljsh.core))] (eval (quote (def ^:dynamic cljsh.core/*cljsh-command-line-args* "'${CLJFILEFP}' '$*'"))))'
		CLJ_ARGS_CODE=`echo $CLJ_ARGS_CODE | sed s/\"/\\\\\"/g`
	else
		echo "ERROR: \"$CLJFILE\" is no valid file-path for a clojure-file." >&2
		exit 1
	fi
fi

# if we have no options and no file, i.e. no args at all, and are connected to the terminal, 
# just start the repl
if [[ ${OPTIND} -eq 1 && -z "${CLJFILE}" && ${CLJSH_STDIN} == "TERM" ]]; then
	CLJ_REPL_PROMPT=1
	CLJ_EVAL_PRINT=1
fi

# by writing the clojure code first in a file that is loaded for eval, we get the benefit of line# debug
# write the clojure code for repl, eval-print and command-line code into a tmp-file
CLJTMPFILE=`mktemp -t ${CLJ_TMP_FNAME}` || exit 1
if [ ${CLJ_EVAL_PRINT:-0} -eq 1 ]; then /bin/echo "$CLJ_EVAL_PRINT_CODE"  >> $CLJTMPFILE; fi
if [ -n "${CLJ_ARGS_CODE}" ];  then /bin/echo "$CLJ_ARGS_CODE"   >> $CLJTMPFILE; fi
if [ ${CLJ_REPL_PROMPT:-0} -eq 1 ];  then /bin/echo "$CLJ_REPL_PROMPT_CODE"   >> $CLJTMPFILE; fi
if [ -n "${CLJ_CODE}" ]; then 
	echo "${CLJ_CODE}"   >> $CLJTMPFILE;
	if [ ${CLJ_STDIN_TEXT:-0} = 1 ]; then
		# if we expect arbitrary data from stdin, then we can close stdin and send the kill-switch at the end
		/bin/echo '(.close *in*)' >> $CLJTMPFILE;
		/bin/echo ${LEIN_REPL_KILL_SWITCH} >> $CLJTMPFILE;
	fi
fi

# write the load-file clojure statements into a separate tmp-file
CLJ_LOAD_TMP_CODE='(load-file "'${CLJTMPFILE}'")'
CLJTMPLOADFILE=`mktemp -t ${CLJ_TMP_FNAME}` || exit 1
# create the tmp-file for the load-file statements and the welcome message
/bin/echo -n  '(do ' >> ${CLJTMPLOADFILE}
/bin/echo -n  "${CLJ_LOAD_TMP_CODE}" >> $CLJTMPLOADFILE
if [ -n "${CLJ_LOAD_CODE}" ]; then /bin/echo -n  "${CLJ_LOAD_CODE}" >> ${CLJTMPLOADFILE}; fi
if [ ${CLJ_REPL_PROMPT:-0} = 1 ]; then  # user wants an interactive REPL
	/bin/echo '(str "Welcome to your Clojure (" (clojure-version) ") lein-repls (" cljsh.core/lein-repls-version ") client"))' >> $CLJTMPLOADFILE;
else
	/bin/echo ')'     >> $CLJTMPLOADFILE;
fi

CLJKILLTMPFILE=`mktemp -t ${CLJ_TMP_FNAME}` || exit 1
/bin/echo ${LEIN_REPL_KILL_SWITCH} >> $CLJKILLTMPFILE;

###############################################################################

# lastly, we send the code to the persistent repl

if [ ${CLJ_REPL_PROMPT:-0} = 1 ]; then  # user wants an interactive REPL

	# max task time doesn't seem to affect interactive repl, but does affect the delay of ctrl-d
	CLJSH_MAXTIME="0.1"
	
	rlwrap -p ${RLWRAP_PROMPT_COLOR:-"Red"} -R -m " \ " -q'"' -b "(){}[],^%$#@\";:'\\" ${RLWRAP_CLJ_WORDS_OPTION} bash -c "cat $CLJTMPLOADFILE - | socat -t ${CLJSH_MAXTIME} - TCP4:${LEIN_REPL_HOST}:${LEIN_REPL_PORT}"
	
else  # no REPL, nothing interactive

	if [ "$CLJSH_STDIN" = "TERM" ]; then
	
		cat $CLJTMPLOADFILE $CLJKILLTMPFILE | socat -t ${CLJSH_MAXTIME} - TCP4:${LEIN_REPL_HOST}:${LEIN_REPL_PORT};
		
	else
	
		if [ ${CLJ_STDIN_TEXT:-0} = 1 ]; then   # arbitrary data and no code coming from stdin
		
			# user's code is responsible for closing *in* to indicate eof as we cannot deduce it to use the kill-switch
		cat $CLJTMPLOADFILE - | socat -t ${CLJSH_MAXTIME} - TCP4:${LEIN_REPL_HOST}:${LEIN_REPL_PORT};
		
		else   # expect clojure code to be piped-in from stdin and kill/end the session after that
		
			# because the repl keeps reading from stdin for clojure-statements, we can append the kill-switch at the end
			cat $CLJTMPLOADFILE - $CLJKILLTMPFILE | socat -t ${CLJSH_MAXTIME} - TCP4:${LEIN_REPL_HOST}:${LEIN_REPL_PORT};
			
		fi
	fi
fi

# EOF "cljsh.sh"