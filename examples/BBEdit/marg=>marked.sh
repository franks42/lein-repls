#!/bin/bash
# BBEdit script to generate Marginalia docs and show those in Marked
# BB_DOC_PATH yields the fqn of the current clj-file

# cd to the file's directory to ensure we can find the right lein project.clj
if [ "${BB_DOC_PATH}" != "" ]; then cd "$( dirname "${BB_DOC_PATH}" )"; fi

# determine the directory of the associated project.clj, or $HOME if none.
export LEIN_PROJECT_DIR=$(
	while [ ! -r "$PWD/project.clj" ] && [ "$PWD" != "/" ];	do cd ..;	done
	if [ -r "$PWD/project.clj" ]; then printf "$PWD";	fi
)
if [ "${LEIN_PROJECT_DIR}" == "" ]; then 
	echo "ERROR: no lein project.clj found"  >&2; 
	exit 1
fi

cd "${LEIN_PROJECT_DIR}"

lein marg

UBERDOCPATH="$PWD/docs/uberdoc.html"

if [ -f "${UBERDOCPATH}" ]; then
	osascript > /dev/null <<-ASEND
			tell application "Marked"
				activate
				open "${UBERDOCPATH}"
			end tell
	ASEND
else
	echo "ERROR: no \"${UBERDOCPATH}\" found in project - Marginalia doc generation error (?)."  >&2;
fi

# bring the document window back in focus
# use RCDefaultApp to associate "txmt:" schmema with either bbedit or textmate
if [ "${BB_DOC_PATH}" != "" ]; then open "txmt://open/?url=file:${BB_DOC_PATH}"; fi

# EOF
