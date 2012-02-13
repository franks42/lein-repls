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

export CLJSH_VERSION="2.0.0-SNAPSHOT"


#################

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

#################

if [ "$BB_DOC_PATH" != "" ]; then cd $( dirname $BB_DOC_PATH ); fi

export CLJSH_OPT="$*"
export CLJSH_OPT2="$@"
export CLJSH_ARGS
for iarg in "$@"
do
	CLJSH_ARGS="$CLJSH_ARGS \"`echo "$iarg" | sed 's/\"/\\\\\"/g'`\""
done

export CLJSH_PID="$$"
export CLJSH__="$_"
export CLJSH_0="$0"
export CLJSH_HOSTNAME="$HOSTNAME"
export CLJSH_HOSTTYPE="$HOSTTYPE"
export CLJSH_OSTYPE="$OSTYPE"
export CLJSH_PWD="$PWD"
export CLJSH_UID="$UID"

export CLJSH_STDIN="REDIRECTED"
if [[ -p /dev/stdin ]]; then CLJSH_STDIN="PIPE"; fi
if [[ -t 0 ]]; then CLJSH_STDIN="TERM"; fi

export RLWRAP_CLJ_WORDS_FILE=${RLWRAP_CLJ_WORDS_FILE:-"$HOME/.clj_completions"}

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

#################

# variable needed for local execution

export LEIN_REPL_INIT_FILE=${LEIN_REPL_INIT_FILE:-"${LEIN_PROJECT_DIR}/.lein_repls"}
if [ -f "${LEIN_REPL_INIT_FILE}" ]; then source "${LEIN_REPL_INIT_FILE}" ; fi
export LEIN_REPL_HOST=${LEIN_REPL_HOST:-"0.0.0.0"}
export LEIN_REPL_PORT=${LEIN_REPL_PORT:-"12357"}
export CLJSH_MAXTIME=${CLJSH_MAXTIME:-"600"}

#################
# prepped env - now prepare CLJSH_ENV for repl

export CLJ_TMP_FNAME=`basename $0`
export CLJ_CODE_FILE=`mktemp -t ${CLJ_TMP_FNAME}` || exit 1
export CLJ_CODE_LOAD_FILE=`mktemp -t ${CLJ_TMP_FNAME}` || exit 1

export CLJSH_ENV=$( env )
CLJSH_ENV=`echo "$CLJSH_ENV" | sed 's/\"/\\\\\"/g'`

/bin/echo  '(require (quote cljsh.core))' >> $CLJ_CODE_FILE
/bin/echo  '(cljsh.core/register-cljsh-env "'"${CLJSH_ENV}"'")' >> $CLJ_CODE_FILE
/bin/echo  '(cljsh.core/register-cljsh-command-line-args ['"$CLJSH_ARGS"'])' >> $CLJ_CODE_FILE
/bin/echo  '(cljsh.core/process-cljsh-req)' >> $CLJ_CODE_FILE

/bin/echo  '(load-file "'${CLJ_CODE_FILE}'")' >> $CLJ_CODE_LOAD_FILE


#################
# ready to submit to the repl

#cljsh -c '(cljsh.core/register-cljsh-env "'"${CLJSH_ENV}"'")' -c '(cljsh.core/register-cljsh-command-line-args ['"$CLJSH_ARGS"'])' -c '(pprint @@cljsh.core/cljsh-env)' -c '(pprint @@cljsh.core/cljsh-command-line-args)'
cljsh -c '(cljsh.core/register-cljsh-env "'"${CLJSH_ENV}"'")' -c '(cljsh.core/register-cljsh-command-line-args ['"$CLJSH_ARGS"'])' -c '(cljsh.core/process-cljsh-req)'


# EOF "cljsh.sh"
