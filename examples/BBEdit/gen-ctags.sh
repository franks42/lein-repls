#!/bin/bash

cd "$( dirname "${BB_DOC_PATH}" )"

# determine the directory of the associated project.clj, or $HOME if none.
export LEIN_PROJECT_DIR=$(
	NOT_FOUND=1
	ORIGINAL_PWD="$PWD"
	while [ ! -r "$PWD/project.clj" ] && [ "$PWD" != "/" ] && [ $NOT_FOUND -ne 0 ]
	do
			cd ..
			if [ "$(dirname "$PWD")" = "/" ]; then
					NOT_FOUND=0
					cd "$ORIGINAL_PWD"
			fi
	done
	if [ ! -r "$PWD/project.clj" ]; then cd "$HOME"; fi
	printf "$PWD"
)

if [ "$LEIN_PROJECT_DIR" == "$HOME" ]; then
	echo "ERROR: cannot find any directory/project.clj"
	exit 1
else
	
	cd $LEIN_PROJECT_DIR
	
	/usr/local/bin/ctags --file-scope=no -R . 
	/usr/local/bin/ctags --file-scope=no -aR /Users/franks/Development/Clojure/clojure
	/usr/local/bin/ctags --file-scope=no -aR /Users/franks/Development/Clojure/leiningen
	/usr/local/bin/ctags --file-scope=no -aR /Users/franks/Development/Clojure/noir
	#/usr/local/bin/ctags --file-scope=no -aR /Users/franks/Development/Clojure/lein-repls
	
fi
