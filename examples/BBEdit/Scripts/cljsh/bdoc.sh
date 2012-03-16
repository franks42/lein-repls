#!/bin/bash
# BBEdit script to generate clj-doc and show those in Marked
# BB_DOC_PATH yields the fqn of the current clj-file

# use applescript to get selection from current bbedit window
DOC_SELECTION=$( osascript <<-END
tell application "BBEdit"
	get selection of text window 1 as text
end tell — application "BBEdit"
END
)

if [ "${DOC_SELECTION}" != "" ]; then

  if [ "${BB_DOC_PATH}" != "" ]; then cd "$( dirname "${BB_DOC_PATH}" )"; fi
  
  export CLJSH_OUTPUT_FILE="$HOME/.cljsh_output_dir/cljsh_output.html"
	cljsh -loc '(require (quote clj-info))(clj-info/bdoc* "'"${DOC_SELECTION}"'")' > /dev/null

else
  echo "ERROR: No word selected for doc lookup." >&2
  exit 1
fi

# bring the document window back in focus
# couldn't make applescript "activate" to work... so use this "txmt:" workaround
# use RCDefaultApp to associate "txmt:" schmema with either bbedit or textmate
if [ "${BB_DOC_PATH}" != "" ]; then open "txmt://open/?url=file:${BB_DOC_PATH}"; fi

# EOF
