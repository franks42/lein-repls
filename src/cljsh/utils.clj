;; Copyright (c) Frank Siebenlist. All rights reserved.
;; The use and distribution terms for this software are covered by the
;; Eclipse Public License 1.0 (http://opensource.org/licenses/eclipse-1.0.php)
;; which can be found in the file COPYING at the root of this distribution.
;; By using this software in any fashion, you are agreeing to be bound by
;; the terms of this license.
;; You must not remove this notice, or any other, from this software.

(ns cljsh.utils
  (:import clojure.lang.IDeref))

;;---------------------------------------------------------------------------------------
;; The inheritable-thread-local code is mimic'ed after the useful.utils/thread-local
;; from https://github.com/flatland/useful
;; thanks to amalloy on #clojure irc for the hints and feedback
;; maybe/hopefully this inheritable-thread-local will one day be part of flatland's libs.

(defn ^{:dont-test "Used in impl of thread-local"}
  inheritable-thread-local*
  "Non-macro version of inheritable-thread-local - see documentation for same."
  [c-init init]
  (let [cinit (or c-init (fn [p] p))
        generator (proxy [InheritableThreadLocal] []
                    (initialValue [] (init))
                    (childValue [p] (cinit p)))]
    (reify IDeref
      (deref [this]
        (.get generator)))))


(defmacro inheritable-thread-local
  "Takes a body of expressions, and returns a java.lang.InheritableThreadLocal object.
   (see http://docs.oracle.com/javase/6/docs/api/java/lang/InheritableThreadLocal.html).
  
   The root parent thread wil have the \"init\" value when instantiated. The initial 
   thread-local value for a new thread is determined by the value returned by
   child-init-fn, which is passed the current value of the parent.

   To get the current value of the thread-local binding, you must deref (@) the
   thread-local object. The body of expressions will be executed once per thread
   and future derefs will be cached.

   Note that while nothing is preventing you from passing these objects around
   to other threads (once you deref the thread-local, the resulting object knows
   nothing about threads), you will of course lose some of the benefit of having
   thread-local objects."
  [child-init-fn & body]
  `(inheritable-thread-local* ~child-init-fn (fn [] ~@body)))
  
;;---------

(defn copy-atom-child-init 
  "A child-init-fn for inheritable-thread-local where the child thread inherits the
   parent's value as the initial value. Only works for atom-refs used for thread-local."
  [p]
  (atom @p :meta (meta p)))
  
;; Usage:
; (def counter (inheritable-thread-local copy-atom-child-init (atom 0)))
; (swap! @counter inc)
; (prinln "counter:" @@counter)

;;---------------------------------------------------------------------------------------


;; eof utils.clj
