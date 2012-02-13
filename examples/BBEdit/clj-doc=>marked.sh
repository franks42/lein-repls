#!/bin/bash
# BBEdit script to generate clj-doc and show those in Marked
# BB_DOC_PATH yields the fqn of the current clj-file

CLJDOC="$HOME/.cljdocmarked.html"

# use applescript to get selection from current bbedit window
DOC_SELECTION=$( osascript <<-END
tell application "BBEdit"
	get selection of text window 1 as text
end tell — application "BBEdit"
END
)

if [ "${DOC_SELECTION}" != "" ]; then
  # cd to the file's directory to ensure cljsh can find correct repl-server
  if [ "${BB_DOC_PATH}" != "" ]; then cd "$( dirname "${BB_DOC_PATH}" )"; fi
  # print doc - if none or error, use println to clear screen.
  cljsh >  "${CLJDOC}" <<-EOCLJ
(require 'clojure.string)
(require 'clojure.java.shell)
(require 'hiccup.core)
(defn ul [coll] [:ul (for [x (map hiccup.core/h (map str coll))] [:li x])])

(let [	w "${DOC_SELECTION}"
				wmap (-> w symbol resolve meta)
				wdoc (-> w symbol resolve meta (#'clojure.repl/print-doc) with-out-str)
				]
	;(clojure.java.shell/sh "bash" "-c" (str "echo '" wdoc "'" " | bcat"))
	(let [page	(hiccup.core/html 
					[:h2 (str (:name wmap))] 
					[:h4 (if (:private wmap) "Private" "Public") " " (if (:macro wmap) "Macro" "Function")]
					[:h4 "Namespace"]
					[:em (str (:ns wmap))]
					[:p]
					[:h4 "Arity"]
					;[:ul (for [x (map hiccup.core/h (map str (:arglists wmap)))] [:li x])]
					(ul (:arglists wmap))
					;;[:ul (map :li (map hiccup.core/h (map str (:arglists wmap))))]
					;;[:p]
					[:h4 "Documentation"]
					[:pre (hiccup.core/escape-html (:doc wmap))]
					;[:h4 "Meta map"]
					;(hiccup.core/escape-html (with-out-str (pprint wmap)))
				)
		]
		(println page)
	)
)
EOCLJ
  
else
  echo "ERROR: No word selected for doc lookup." >&2
  exit 1
fi

if [ -f "${CLJDOC}" ]; then
	osascript > /dev/null <<-ASEND
			tell application "Marked"
				activate
				open "${CLJDOC}"
			end tell
	ASEND
	
	currentdocpath=$( osascript <<-ASEND
			tell application "Marked"
				get path of document of window index 1
			end tell
	ASEND
	)
	echo currentdocpath="${currentdocpath}"
else
	echo "ERROR: no \"${CLJDOC}\" found in project - Marginalia doc generation error (?)."  >&2;
fi

# bring the document window back in focus
# use RCDefaultApp to associate "txmt:" schmema with either bbedit or textmate
if [ "${BB_DOC_PATH}" != "" ]; then open "txmt://open/?url=file:${BB_DOC_PATH}"; fi

# EOF
