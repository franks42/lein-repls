#!/bin/bash
# BBEdit script to kibit on project's namespaces
# BB_DOC_PATH yields the fqn of the current clj-file

CLJSH_OUTPUT_TXT=${CLJSH_OUTPUT_TXT:-"$HOME/.cljsh_output_dir/cljsh_output.txt"}
CLJSH_OUTPUT_HTML=${CLJSH_OUTPUT_HTML:-"$HOME/.cljsh_output_dir/cljsh_output.html"}

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

lein kibit | tee ${CLJSH_OUTPUT_TXT}

cat "${CLJSH_OUTPUT_TXT}" | textutil -font Inconsolata -fontsize 16 -convert html -stdin -stdout > "${CLJSH_OUTPUT_HTML}"

# bring the document window back in focus
# use RCDefaultApp to associate "txmt:" schmema with either bbedit or textmate
if [ "${BB_DOC_PATH}" != "" ]; then open "txmt://open/?url=file:${BB_DOC_PATH}"; fi

# EOF
