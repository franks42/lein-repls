#!/bin/bash
# BBEdit script to generate clj-doc and show those in Marked
# BB_DOC_PATH yields the fqn of the current clj-file

CLJDOC_MARKED="$HOME/.cljdocmarked.html"

# use applescript to get selection from current bbedit window
DOC_SELECTION=$( osascript <<-END
tell application "BBEdit"
	get selection of text window 1 as text
end tell — application "BBEdit"
END
)

if [ "${DOC_SELECTION}" != "" ]; then

  if [ "${BB_DOC_PATH}" != "" ]; then cd "$( dirname "${BB_DOC_PATH}" )"; fi
  cljsh >  "${CLJDOC_MARKED}" <<-EOCLJ
(require 'clojure.string)
(require 'clojure.java.shell)
(require 'hiccup.core)

(let [w "${DOC_SELECTION}"
			wmap (-> w symbol resolve meta)]
	(if wmap
		(let [page	(hiccup.core/html 
						[:h2 (str (:name wmap))] 
						[:h5 (if (:private wmap) "Private" "Public") " " (if (:macro wmap) "Macro" "Function")]
						[:h4 "Namespace"]
						[:em (str (:ns wmap))]
						[:h4 "Arity"]
						[:ul (for [x (map hiccup.core/h (map str (:arglists wmap)))] [:li x])]
						[:h4 "Documentation"]
						[:pre (hiccup.core/escape-html (:doc wmap))]
						)]
			(println page))
		(let [page	(hiccup.core/html 
						[:h2 (str "Sorry... no doc for \"" w "\"")]
						[:pre "(maybe try to include or exclude namespace (?))"])]
			(println page)))
	)
EOCLJ
  
else
  echo "ERROR: No word selected for doc lookup." >&2
  exit 1
fi

if [ -f "${CLJDOC_MARKED}" ]; then
	osascript > /dev/null <<-ASEND
			tell application "Marked"
				activate
				open "${CLJDOC_MARKED}"
			end tell
	ASEND
else
	echo "ERROR: no \"${CLJDOC_MARKED}\" found (?)."  >&2;
fi

# bring the document window back in focus
# use RCDefaultApp to associate "txmt:" schmema with either bbedit or textmate
if [ "${BB_DOC_PATH}" != "" ]; then open "txmt://open/?url=file:${BB_DOC_PATH}"; fi

# EOF
