#!/bin/sh
#
# Copyright (c) Frank Siebenlist. All rights reserved.
# The use and distribution terms for this software are covered by the
# Eclipse Public License 1.0 (http://opensource.org/licenses/eclipse-1.0.php)
# which can be found in the file COPYING at the root of this distribution.
# By using this software in any fashion, you are agreeing to be bound by
# the terms of this license.
# You must not remove this notice, or any other, from this software.

# helper shell-script that takes all the script files passed as arguments and pipes those thru socat's stdin on to the lein-repl server

# optionally, anything coming in from stdin to this script is also forwarded by cat based on the position of "-" in the command line options.
# the files as arguments can be used pre/post code for the stdin submitted code

# note that normally this script is not called directly, but used by cljsh.sh

# CLJSH_MAXTIME is the maximum time a task is allowed to take before socat will assume that that task is finished
# the time is measured between the subsequent writes to stdout by that task
# if you expect tasks to take more than 10min (default), increase CLJSH_MAXTIME appropriately
# (shorter tasks force the closing of the connection by sending a kill-switch at the end of the script, i.e. :leiningen.repl/exit)

cat $@ | socat -t ${CLJSH_MAXTIME:-"600"} - TCP4:${LEIN_REPL_HOST:-"0.0.0.0"}:${LEIN_REPL_PORT:-"12357"}

# following does not work... not sure why netcat acts up...
# cat $@ | nc $LEIN_REPL_HOST $LEIN_REPL_PORT

# EOF "catcljsh.sh"