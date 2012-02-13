#!/bin/bash
# BBEdit script to start a lein-repls server if needed
# BB_DOC_PATH yields the fqn of the current clj-file

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

# show applescript alert if osascript is detected
function displayAlert ()
{
	if [ "`which osascript`" ]; then
		osascript > /dev/null <<-OSAEND
		tell application "System Events"
        activate
        display alert "$*"
    end tell	
		OSAEND
	fi
 	echo "$*" >&2
}

# start shell script in MacOSX Terminal or xterm
function startTerminalScript ()
{
	if [ "`which osascript`" ]; then
		osascript > /dev/null <<-ASEND
				tell application "Terminal"
					activate
					do script "$*"
				end tell -- application "Terminal"
		ASEND
	else
		${XTERM:-"/usr/X11/bin/xterm"} -e "$*" &
	fi
}

# search upwards for directory with project.clj 
function leinProjectDir ()
{
 	original_dir="$PWD";
 	if [ -f "$1" ]; then cd $( dirname "$1" ); 
 	elif [ -d "$1" ]; then cd "$1"; 
 	elif [ "$1" != "" ]; then echo "not good" >&2; exit 1; fi
 	while [ ! -r "$PWD/project.clj" ] && [ "$PWD" != "/" ]; do cd ..; done
	if [ -r "$PWD/project.clj" ]; then projectDir="$PWD"; fi
	cd "$original_dir";
	echo "${projectDir}";
}

# test to see if cljsh-repls connection works
function testRepls ()
{
	if [ "ping" == "$( cljsh -c '(println "ping")' )" ]; then 
		displayAlert "OK: repls server up & running and listening on port ${LEIN_REPL_PORT}";
		exit 0;
	else
		displayAlert "ERROR: some server listening on port ${LEIN_REPL_PORT}, but repls server not responding... not sure why (?).";
		exit 1;
	fi
}

#########

# cd to the file's directory to ensure we can find the right lein project.clj
if [ "${BB_DOC_PATH}" != "" ]; then cd "$( dirname "${BB_DOC_PATH}" )"; fi

# determine the directory of the associated project.clj, or $HOME if none.
export LEIN_PROJECT_DIR=$(leinProjectDir)
if [ "${LEIN_PROJECT_DIR}" == "" ]; then 
	displayAlert "ERROR: no lein project.clj found"; 
	exit 1
fi

export LEIN_REPL_INIT_FILE="${LEIN_PROJECT_DIR}/.lein_repls"
if [ -f "${LEIN_REPL_INIT_FILE}" ]; then source "${LEIN_REPL_INIT_FILE}" ; fi

# start "lein repls" if needed
function startRepls ()
{
	if [ "${LEIN_REPL_PORT}" == "" ] || [ "$(netstat -an -f inet | grep '*.*' | grep "${LEIN_REPL_PORT}")" == "" ]; then
		# no app listening on expected port, so start a new repls server
		if [ -f "${LEIN_REPL_INIT_FILE}" ]; then rm "${LEIN_REPL_INIT_FILE}"; fi
		startTerminalScript 'cd '"${LEIN_PROJECT_DIR}"'; lein repls'
		ii=0; until [[ -f "${LEIN_REPL_INIT_FILE}" || $ii -gt 10 ]]; do
			sleep 1; ii=$(($ii-1));
		done
		sleep 3
		if [ -f "${LEIN_REPL_INIT_FILE}" ]; then 
			source "${LEIN_REPL_INIT_FILE}" ; 
			exit 0
		else
			displayAlert "ERROR: no lein project.clj found after starting lein repls (?)";
			exit 1;
		fi
	fi
}

$(startRepls)
$(testRepls)

# bring the document window back in focus
# use RCDefaultApp to associate "txmt:" schmema with either bbedit or textmate
if [ "${BB_DOC_PATH}" != "" ]; then open "txmt://open/?url=file:${BB_DOC_PATH}"; fi

# EOF
