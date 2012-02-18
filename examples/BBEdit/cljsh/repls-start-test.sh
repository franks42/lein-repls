#!/bin/bash

# cd to the file's directory to ensure we can find the right lein project.clj
if [ "${BB_DOC_PATH}" != "" ]; then cd "$( dirname "${BB_DOC_PATH}" )"; fi

cljsh -laT >&2
EXIT_CODE=$?

# bring the document window back in focus
# use RCDefaultApp to associate "txmt:" schmema with either bbedit or textmate
if [ "${BB_DOC_PATH}" != "" ]; then open "txmt://open/?url=file:${BB_DOC_PATH}"; fi

exit $EXIT_CODE

# EOF
