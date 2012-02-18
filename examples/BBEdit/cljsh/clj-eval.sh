#!/bin/bash
# BBEdit script to send either selection or whole file with cljsh to the repl-server for eval
# BB_DOC_PATH yields the fqn of the current clj-file
# BB_DOC_SELSTART and BB_DOC_SELEND yield character index for start and end of selection.
# If start and end are equal, then no selection and it designates the cursor position

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
	echo "${DOC_SELECTION}" > "${CLJ_FILE}"
else
	# ensure that document is saved, otherwise we work with out-of-date data
	osascript <<-END
		tell application "BBEdit"
			save document 1
		end tell
	END
	# no selection, so send whole clj-file for eval
	CLJ_FILE="${BB_DOC_PATH}"
fi

# send the clj-file or tmp-file for eval
cljsh -lp "${CLJ_FILE}" >&2
EXIT_CODE=$?

# bring the document window back in focus
# use RCDefaultApp to associate "txmt:" schmema with either bbedit or textmate
open "txmt://open/?url=file:${BB_DOC_PATH}"

exit $EXIT_CODE

# EOF
