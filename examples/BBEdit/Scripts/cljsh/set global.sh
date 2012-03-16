#!/bin/bash
# BBEdit script to send either selection or whole file with cljsh to the repl-server for eval
# BB_DOC_PATH yields the fqn of the current clj-file

# cd to the file's directory to ensure cljsh can find correct repl-server
  if [ "${BB_DOC_PATH}" != "" ]; then cd "$( dirname "${BB_DOC_PATH}" )"; fi

cljsh -G  >&2
EXIT_CODE=$?

# bring the document window back in focus
# couldn't make applescript "activate" to work... so use this "txmt:" workaround
# use RCDefaultApp to associate "txmt:" schmema with either bbedit or textmate
open "txmt://open/?url=file:${BB_DOC_PATH}"

exit $EXIT_CODE

# EOF
