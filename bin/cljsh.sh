#!/bin/sh
#
# Copyright (c) Frank Siebenlist. All rights reserved.
# The use and distribution terms for this software are covered by the
# Eclipse Public License 1.0 (http://opensource.org/licenses/eclipse-1.0.php)
# which can be found in the file COPYING at the root of this distribution.
# By using this software in any fashion, you are agreeing to be bound by
# the terms of this license.
# You must not remove this notice, or any other, from this software.

###############################################################################
# "cljsh" is a bash shell script that interacts with Leiningen's plugin "repls".
# It allows the user to submit Clojure statement and Clojure script files
# to a persistent networked repl for evaluation.

CLJSH_VERSION="1.6.0"

# util functions

function fullFilePath()
{
if [ -f "$1" ]; then
	/bin/echo -n $( cd "$( dirname $1 )" && pwd )/"$( basename $1 )"
else
	echo "ERROR: \"$1\" is no valid file-path for a clojure-file." >&2
	exit 1
fi
}

# Clojure code snippets
# send kill-switch as final separate statement to end the repl session/connection gracefully
CLJ_EVAL_PRINT_CODE='(cljsh.core/set-repl-result-print prn)'
CLJ_NO_EVAL_PRINT_CODE='(cljsh.core/set-repl-result-print (fn [&a]))'
CLJ_REPL_PROMPT_CODE='(cljsh.core/set-prompt cljsh.core/repl-ns-prompt)'
CLJ_PRINT_CLJ_WORDS_CODE='(require (quote cljsh.completion)) (cljsh.completion/print-all-words)'
CLJ_CLOSE_IN_CODE='(.close *in*)'
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
if [ -f "${LEIN_REPL_INIT_FILE}" ]; then source "${LEIN_REPL_INIT_FILE}" ; fi

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

###############################################################################
# Option processing.

# file that will hold clj-statements associated with cmd-line options
CLJ_CODE=`mktemp -t ${CLJ_TMP_FNAME}` || exit 1
CLJ_CODE_BEFORE=${CLJ_CODE}
CLJ_CODE_AFTER=

# command line option processing
while [ "${!OPTIND}" == "-" ] || getopts ":drwpPghtvm:c:s:e:f:i:" opt; do
  case $opt in
    c) 	# clojure code statements expected as options value
    	echo "${OPTARG}" >> ${CLJ_CODE}
      ;;
    e) 	# clojure code statements expected as options value (same as c))
    	echo "${OPTARG}" >> ${CLJ_CODE}
      ;;
    f) 	# clojure file expected as options value (same as i)
    	echo '(load-file "'"$(fullFilePath ${OPTARG})"'")' >> ${CLJ_CODE}
      ;;
    i) 	# clojure file expected as options value (same as f)
    	echo '(load-file "'"$(fullFilePath ${OPTARG})"'")' >> ${CLJ_CODE}
      ;;
    m) 	# maximum time for a task expected as option value
    	CLJSH_MAXTIME="$OPTARG";
    	;;
    s)	# Leiningen repl server port
    	LEIN_REPL_PORT="$OPTARG";
    	;;
    r) 	# interactive/repl so turn on the printing of repl-prompt and eval result
    	echo "${CLJ_REPL_PROMPT_CODE}" >> ${CLJ_CODE}
    	echo "${CLJ_EVAL_PRINT_CODE}" >> ${CLJ_CODE}
    	CLJ_REPL_PROMPT=1
      ;;
    w) 	# refresh word completion file with current repl-context
			cljsh -f ${CLJ_CODE} -e ${CLJ_PRINT_CLJ_WORDS_CODE} > "${RLWRAP_CLJ_WORDS_FILE}"
      ;;
    t) 	# text/arbitrary data and no clojure-code expected from stdin, so don't eval stdin.
    	CLJ_STDIN_TEXT=1
      ;;
    g) 	# force a pickup of the "global" repls-server coordinates from the $HOME directory.
			if [ -r "${HOME}/.lein_repls" ]; then 
				source "${HOME}/.lein_repls" ; 
			else
				echo "ERROR: no global/default init file found at ${HOME}/.lein_repls" >&2 ;
      	exit 1;
			fi
      ;;
    p) 	# turn on printing of eval-results by the repl.
    	echo "${CLJ_EVAL_PRINT_CODE}" >> ${CLJ_CODE}
      ;;
    P) 	# turn off printing of eval-results by the repl.
    	echo "${CLJ_NO_EVAL_PRINT_CODE}" >> ${CLJ_CODE}
      ;;
    v) 	# version information
    	echo "Clojure Shell version: \"${CLJSH_VERSION}\"" >&2;
    	exit 0
      ;;
    d) 	# debug options
      CLJSH_DEBUG=1
      ;;
    h)  # print help text and do some basic diagnostics
    	CLJSH_PRG=`basename $0`
    	cat  >&2 <<-EOHELP
			Usage: ${CLJSH_PRG} [OPTIONS] [FILE]
			Clojure Shell version: "${CLJSH_VERSION}"
			"${CLJSH_PRG}" is a shell script that sends clojure code to a persistent socket-repls-server.
			The lein-plugin repls-server is started in the project's directory thru "lein repls".
			${CLJSH_PRG} auto-detects server-port within project's dir - optional global project (-g)
			Printed output and optionally eval results (-p) are returned thru stdout.
			Clojure code is passed on command line (-c or -e), in file (-i or -f or FILE), or thru stdin.
			Sequence of evaluation is determined by option's position - stdin defaults to last or "-".
			Optionally, arbitrary data can be passed in thru stdin (-t).
			"#!" clojure shell-script files are supported.
			"${CLJSH_PRG}" also supports interactive repl mode (-r) with rlwrap code-completion (-w)
			---
			${CLJSH_PRG} -r                             # -r interactive repl session
			${CLJSH_PRG} -c clj-code                    # -c eval the clj-code (equivalent to -e)
			${CLJSH_PRG} -e clj-code                    # -e eval the clj-code (equivalent to -c)
			${CLJSH_PRG} -f clj-file                    # -f load&eval clj-file (equivalent to -i)
			${CLJSH_PRG} -i clj-file                    # -i load&eval clj-file (equivalent to -f)
			${CLJSH_PRG} clj-file args                  # load&eval clj-file with (optional) args
			echo clj-code | ${CLJSH_PRG} -c clj-code    # eval piped clj-code after -c clj-code
			echo clj-code | ${CLJSH_PRG} - -c clj-code  # "-" eval piped clj-code before -c clj-code
			echo text | ${CLJSH_PRG} -t -c clj-code     # -t process arbitrary data from stdin with clj-code
			${CLJSH_PRG} -p                             # -p print eval results to stdout (discarded by default)
			${CLJSH_PRG} -w                             # -w refresh the clojure words for completion in interactive repl
			${CLJSH_PRG} -g                             # -g pickup "global" repls-server coordinates from "~/.lein_repls"
			${CLJSH_PRG} -s repl-server-port            # -s repls server port (default automatically set by "lein repls")
			${CLJSH_PRG} -m task-max-time-sec           # -m set max time for task (default ${CLJSH_MAXTIME}sec - see docs)
			${CLJSH_PRG} -h                             # -h this usage help plus diagnostic check & exit
			---
			Docs & code at "https://github.com/franks42/lein-repls"
EOHELP
			# do simple check to see if repls-server can be seen listenen
			# lsof -P -p 37683 -i TCP:14331 -sTCP:LISTEN -t
			if [ "$(netstat -an -f inet |grep '*.*' | grep ${LEIN_REPL_PORT})" == "" ]; then
				echo "ERROR: no \"lein repls\" server listening on port ${LEIN_REPL_PORT} (use -s or \$LEIN_REPL_PORT for different port)" >&2;
			else
				echo "\"lein repls\" server most probably is listening on port ${LEIN_REPL_PORT}" >&2;
			fi
			hash socat 2>&-  || { echo >&2 "ERROR: \"socat\" is require for cljsh but not installed.";}
			hash rlwrap 2>&- || { echo >&2 "ERROR: \"rlwrap\" is require for cljsh but not installed.";}

    	exit 1
      ;;
    \?) echo "Invalid option: -$OPTARG" >&2
    		exit 1
    		;;
    :)	echo "Option -$OPTARG requires an argument." >&2
      	exit 1
      	;;
  esac
  
  # deal with stdin directive "-" separately because getopts does not...
  if [ "${!OPTIND}" == "-" ]; then
  	if [ ${CLJSH_STDIN} == "TERM"  ]; then
			echo "ERROR: No possible \"-\" directive with terminal connected to stdin." >&2
			exit 1
  	fi
  	if [ -z "${CLJ_CODE_AFTER}" ]; then  # switch to "after stdin" code-file
			CLJ_CODE=`mktemp -t ${CLJ_TMP_FNAME}` || exit 1
			CLJ_CODE_AFTER=${CLJ_CODE}
			shift;
		else
			echo "ERROR: More than one stdin \"-\" directive." >&2
			exit 1
		fi
	fi
done  # end of getopts processing


# process optional clj-file + args after the cljsh-options

# the remaining args are expected to be an optional single clj-file name with (optional) args
shift $(($OPTIND-1))  # shift past the args processed by getopts
CLJFILE="$1"  # first arg should be a clojure file name followed by associated args
if [ -n "$CLJFILE" ]; then
	CLJFILEFP="$(fullFilePath ${CLJFILE})"
	shift   #  now we're left with the additional argument that go with the clojure file
	CLJ_ARGS_CODE='(binding [*ns* (find-ns (quote cljsh.core))] (eval (quote (def ^:dynamic cljsh.core/*cljsh-command-line-file* "'${CLJFILEFP}'")))(eval (quote (def ^:dynamic cljsh.core/*cljsh-command-line-args* "'$*'"))))'
	CLJ_ARGS_CODE=`echo $CLJ_ARGS_CODE | sed s/\"/\\\\\"/g`
	echo ${CLJ_ARGS_CODE} >> ${CLJ_CODE}  # first write args before load-file
	echo '(load-file "'"${CLJFILEFP}"'")' >> ${CLJ_CODE}
fi

# special cases for options

# no options, no clj-file and connected to the terminal => assume interactive repl
if [[ ${OPTIND} -eq 1 && -z "${CLJFILE}" && ${CLJSH_STDIN} == "TERM" ]]; then
	echo "${CLJ_REPL_PROMPT_CODE}" >> ${CLJ_CODE}
 	CLJ_REPL_PROMPT=1
	echo "${CLJ_EVAL_PRINT_CODE}" >> ${CLJ_CODE}
fi

# add welcome message for interactive repl
if [ ${CLJ_REPL_PROMPT:-0} = 1 ]; then
	/bin/echo '(str "Welcome to your Clojure (" (clojure-version) ") lein-repls (" cljsh.core/lein-repls-version ") client!")' >> ${CLJ_CODE};
fi

# if -t option, then append kill switch to code
if [ ${CLJ_STDIN_TEXT:-0} = 1 ]; then
	if [ -n "${CLJ_CODE_AFTER}" ]; then
		echo "ERROR: No code  \"-\" directive with -t option." >&2;	exit 1
	fi
	if [ ${CLJ_REPL_PROMPT:-0} = 1 ]; then
		echo "ERROR: No interactive repl (-r) with -t option." >&2;	exit 1
	fi
	# when arbitrary data from stdin, then close stdin and send the kill-switch at the end
	/bin/echo ${CLJ_CLOSE_IN_CODE} >> ${CLJ_CODE_BEFORE};
	/bin/echo ${LEIN_REPL_KILL_SWITCH} >> ${CLJ_CODE_BEFORE};
fi

###############################################################################
# Load File Generation
# load code-file thru second file => benefit of line# debug in stacktraces

CLJ_BEFORE_LOAD=`mktemp -t ${CLJ_TMP_FNAME}` || exit 1
/bin/echo  '(load-file "'${CLJ_CODE_BEFORE}'")' >> $CLJ_BEFORE_LOAD

if [ -n "${CLJ_CODE_AFTER}" ]; then
	CLJ_AFTER_LOAD=`mktemp -t ${CLJ_TMP_FNAME}` || exit 1
	/bin/echo '(load-file "'${CLJ_CODE_AFTER}'")' >> ${CLJ_AFTER_LOAD}
fi

if [ "${CLJSH_DEBUG:-0}" -eq 1 ]; then
	CLJ_BEFORE_LOAD=$CLJ_CODE_BEFORE
	CLJ_AFTER_LOAD=$CLJ_CODE_AFTER
fi

CLJ_KILL_FILE=`mktemp -t ${CLJ_TMP_FNAME}` || exit 1
/bin/echo ${LEIN_REPL_KILL_SWITCH} >> ${CLJ_KILL_FILE};

###############################################################################
# lastly, we send the code to the persistent repl

if [ ${CLJ_REPL_PROMPT:-0} = 1 ]; then  # user wants an interactive REPL

	# max task time doesn't seem to affect interactive repl, but does affect the delay of ctrl-d
	CLJSH_MAXTIME="0.1"
	
	RLWRAP=`which rlwrap`
	if [ -x ${RLWRAP} ]; then
		# only include the rlwrap completions file directive if that file actually exists
		RLWRAP_CLJ_WORDS_OPTION=""
		if [ -f "${RLWRAP_CLJ_WORDS_FILE}" ]; then 
			RLWRAP_CLJ_WORDS_OPTION="-f ${RLWRAP_CLJ_WORDS_FILE}"; 
		fi
		RLWRAP="${RLWRAP}"" -p${RLWRAP_PROMPT_COLOR:-Red}"" -R"" -m\ "" -q\""" -b (){}[],^%$#@\";:'\\"" ${RLWRAP_CLJ_WORDS_OPTION}"
	fi

	exec ${RLWRAP} bash -c "cat ${CLJ_BEFORE_LOAD} - | socat -t ${CLJSH_MAXTIME} - TCP4:${LEIN_REPL_HOST}:${LEIN_REPL_PORT}"
	
else  # no REPL, nothing interactive

	if [ "${CLJSH_STDIN}" == "TERM" ]; then # not interactive, so no code will come-in thru stdin

		exec cat "${CLJ_BEFORE_LOAD}" "${CLJ_KILL_FILE}" | socat -t ${CLJSH_MAXTIME} - TCP4:${LEIN_REPL_HOST}:${LEIN_REPL_PORT};
		
	elif [ ${CLJ_STDIN_TEXT:-0} -eq 1 ]; then   # arbitrary data but no code coming from stdin

			# user's code is responsible for closing *in* to indicate eof as we cannot deduce it to use the kill-switch
			exec cat ${CLJ_BEFORE_LOAD} - | socat -t ${CLJSH_MAXTIME} - TCP4:${LEIN_REPL_HOST}:${LEIN_REPL_PORT};
		
	else   # expect clojure code to be piped-in from stdin and kill&end the session after that

			# because the repl keeps reading from stdin for clojure-statements, we can append the kill-switch at the end
			exec cat ${CLJ_BEFORE_LOAD} - ${CLJ_AFTER_LOAD} ${CLJ_KILL_FILE} | socat -t ${CLJSH_MAXTIME} - TCP4:${LEIN_REPL_HOST}:${LEIN_REPL_PORT};
			
	fi
fi

# EOF "cljsh.sh"