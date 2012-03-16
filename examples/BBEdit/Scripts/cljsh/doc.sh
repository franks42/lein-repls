#!/bin/bash
# BBEdit script to lookup doc for selected word.
# BB_DOC_PATH yields the fqn of the current clj-file
# BB_DOC_SELSTART and BB_DOC_SELEND yield character index for start and end of selection.
# If start and end are equal, then no selection and it designates the cursor position
# or use applescript to get selection - no need to save doc first then

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

# cd to the file's directory to ensure cljsh can find correct repl-server
if [ "${BB_DOC_PATH}" != "" ]; then cd "$( dirname "${BB_DOC_PATH}" )"; fi

# use applescript to get selection from current bbedit window
DOC_SELECTION=$( osascript <<-END
tell application "BBEdit"
	get selection of text window 1 as text
end tell — application "BBEdit"
END
)

if [ "${DOC_SELECTION}" != "" ]; then
  # print doc - if none or error, use println to clear screen.
  cljsh -lc '(require (quote clj-info))(clj-info/tdoc* "'"${DOC_SELECTION}"'")(println)' >&2 ;
  EXIT_CODE=$?;
else
	displayAlert "ERROR: No word selected for clj-doc lookup";
  exit 1;
fi

# bring the document window back in focus
# couldn't make applescript "activate" to work... so use this "txmt:" workaround
# use RCDefaultApp to associate "txmt:" schmema with either bbedit or textmate
open "txmt://open/?url=file:${BB_DOC_PATH}";

exit $EXIT_CODE

# EOF
