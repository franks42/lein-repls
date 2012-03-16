#!/bin/bash
# BBEdit script to send either selection or whole file with cljsh to the repl-server for eval
# BB_DOC_PATH yields the fqn of the current clj-file
# BB_DOC_SELSTART and BB_DOC_SELEND yield character index for start and end of selection.
# If start and end are equal, then no selection and it designates the cursor position

CLJSH_OUTPUT_TXT=${CLJSH_OUTPUT_TXT:-"$HOME/.cljsh_output_dir/cljsh_output.txt"}
CLJSH_OUTPUT_HTML=${CLJSH_OUTPUT_HTML:-"$HOME/.cljsh_output_dir/cljsh_output.html"}

# use applescript to get selection from current bbedit window
DOC_SELECTION=$( osascript <<-END
tell application "BBEdit"
	get selection of text window 1 as text
end tell — application "BBEdit"
END
)

# cd to the file's directory to ensure cljsh can find correct repl-server
  if [ "${BB_DOC_PATH}" != "" ]; then cd "$( dirname "${BB_DOC_PATH}" )"; fi

if [ "${DOC_SELECTION}" != "" ]; then
	# write selection to a newly created temp-file
	CLJ_FILE=`mktemp -t bbedit_cljsh_XXXX`.clj || exit 1
	echo '(require (quote clojure.pprint))(clojure.pprint/pprint (macroexpand-1 (quote '"${DOC_SELECTION}" ')))' > "${CLJ_FILE}"
	# send the clj-file or tmp-file for eval
	cljsh -l "${CLJ_FILE}" >&2
	EXIT_CODE=$?

else
	echo 'ERROR: must select a complete clj-form for macroexpand-1' >&2
fi

# bring the document window back in focus
# couldn't make applescript "activate" to work... so use this "txmt:" workaround
# use RCDefaultApp to associate "txmt:" schmema with either bbedit or textmate
open "txmt://open/?url=file:${BB_DOC_PATH}"

exit $EXIT_CODE

# test: (doc map)
# EOF
