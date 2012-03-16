(ns cljsh.completion
	(:import 	[java.io File FilenameFilter]
				 		[java.util StringTokenizer]
				 		[java.util.jar JarFile JarEntry]
				 		[java.util.regex Pattern]))

;; copied swank.command.completions with all dependent code from swank.*
;; to avoid direct dependencies on the swank-clojure code base.
;; simple clojure-swank dependency in project.clj doesn't seem to work
;; too bad those function are not moved into a separate library
;; at the end of the file there are some convenient functions to create 
;; the rlwrap word list.


(defn maybe-ns [package]
  (cond
   (symbol? package) (or (find-ns package) (maybe-ns 'user))
   (string? package) (maybe-ns (symbol package))
   (keyword? package) (maybe-ns (name package))
   (instance? clojure.lang.Namespace package) package
   :else (maybe-ns 'user)))

;; swank.util.clojure

(defn symbol-name-parts
  "Parses a symbol name into a namespace and a name. If name doesn't
   contain a namespace, the default-ns is used (nil if none provided)."
  ([symbol] (symbol-name-parts symbol nil))
  ([#^String symbol default-ns]
     (let [ns-pos (.indexOf symbol (int \/))]
       (if (= ns-pos -1) ;; namespace found? 
         [default-ns symbol] 
         [(.substring symbol 0 ns-pos) (.substring symbol (inc ns-pos))]))))

(defn resolve-ns [sym ns]
  (or (find-ns sym)
      (get (ns-aliases ns) sym))) 
      

;; swank.util.java

(defn member-name [#^java.lang.reflect.Member member]
  (.getName member))

(defn member-static? [#^java.lang.reflect.Member member]
  (java.lang.reflect.Modifier/isStatic (.getModifiers member)))

(defn static-methods [#^Class class]
  (filter member-static? (.getMethods class)))

(defn static-fields [#^Class class]
  (filter member-static? (.getDeclaredFields class)))

(defn instance-methods [#^Class class]
  (remove member-static? (.getMethods class)))

;; ns swank.util.class-browse
;  "Provides Java classpath and (compiled) Clojure namespace browsing.
;  Scans the classpath for all class files, and provides functions for
;  categorizing them. Classes are resolved on the start-up classpath only.
;  Calls to 'add-classpath', etc are not considered.
;
;  Class information is built as a list of maps of the following keys:
;    :name  Java class or Clojure namespace name
;    :loc   Classpath entry (directory or jar) on which the class is located
;    :file  Path of the class file, relative to :loc"

;;; Class file naming, categorization

(defn jar-file? [#^String n] (.endsWith n ".jar"))
(defn class-file? [#^String n] (.endsWith n ".class"))
(defn clojure-ns-file? [#^String n] (.endsWith n "__init.class"))
(defn clojure-fn-file? [#^String n] (re-find #"\$.*__\d+\.class" n))
(defn top-level-class-file? [#^String n] (re-find #"^[^\$]+\.class" n))
(defn nested-class-file? [#^String n]
  ;; ^ excludes anonymous classes
  (re-find #"^[^\$]+(\$[^\d]\w*)+\.class" n))

(def clojure-ns? (comp clojure-ns-file? :file))
(def clojure-fn? (comp clojure-fn-file? :file))
(def top-level-class? (comp top-level-class-file? :file))
(def nested-class? (comp nested-class-file? :file))

(defn class-or-ns-name
  "Returns the Java class or Clojure namespace name for a class relative path."
  [#^String n]
  (.replace
   (if (clojure-ns-file? n)
     (-> n (.replace "__init.class" "") (.replace "_" "-"))
     (.replace n ".class" ""))
   File/separator "."))

;;; Path scanning

(defmulti path-class-files
  "Returns a list of classes found on the specified path location
  (jar or directory), each comprised of a map with the following keys:
    :name  Java class or Clojure namespace name
    :loc   Classpath entry (directory or jar) on which the class is located
    :file  Path of the class file, relative to :loc"
  (fn [#^ File f _]
    (cond (.isDirectory f)           :dir
          (jar-file? (.getName f))   :jar
          (class-file? (.getName f)) :class)))

(defmethod path-class-files :default
  [& _] [])

(defmethod path-class-files :jar
  ;; Build class info for all jar entry class files.
  [#^File f #^File loc]
  (let [lp (.getPath loc)]
    (try
     (map (fn [fp] {:loc lp :file fp :name (class-or-ns-name fp)})
          (filter class-file?
                  (map #(.getName #^JarEntry %)
                       (enumeration-seq (.entries (JarFile. f))))))
     (catch Exception e []))))          ; fail gracefully if jar is unreadable

(defmethod path-class-files :dir
  ;; Dispatch directories and files (excluding jars) recursively.
  [#^File d #^File loc]
  (let [fs (.listFiles d (proxy [FilenameFilter] []
                           (accept [d n] (not (jar-file? n)))))]
    (reduce concat (for [f fs] (path-class-files f loc)))))

(defmethod path-class-files :class
  ;; Build class info using file path relative to parent classpath entry
  ;; location. Make sure it decends; a class can't be on classpath directly.
  [#^File f #^File loc]
  (let [fp (.getPath f), lp (.getPath loc)
        m (re-matcher (re-pattern (Pattern/quote
                                   (str "^" lp File/separator))) fp)]
    (if (not (.find m))                 ; must be descendent of loc
      []
      (let [fpr (.substring fp (.end m))]
        [{:loc lp :file fpr :name (class-or-ns-name fpr)}]))))

;;; Classpath expansion

(def java-version
     (Float/parseFloat (.substring (System/getProperty "java.version") 0 3)))

(defn expand-wildcard
  "Expands a wildcard path entry to its matching .jar files (JDK 1.6+).
  If not expanding, returns the path entry as a single-element vector."
  [#^String path]
  (let [f (File. path)]
    (if (and (= (.getName f) "*") (>= java-version 1.6))
      (-> f .getParentFile
          (.list (proxy [FilenameFilter] []
                   (accept [d n] (jar-file? n)))))
      [f])))

(defn scan-paths
  "Takes one or more classpath strings, scans each classpath entry location, and
  returns a list of all class file paths found, each relative to its parent
  directory or jar on the classpath."
  ([cp]
     (if cp
       (let [entries (enumeration-seq
                      (StringTokenizer. cp File/pathSeparator))
             locs (mapcat expand-wildcard entries)]
         (reduce concat (for [loc locs] (path-class-files loc loc))))
       ()))
  ([cp & more]
     (reduce #(concat %1 (scan-paths %2)) (scan-paths cp) more)))

;;; Class browsing

(def available-classes
     (filter (complement clojure-fn?)  ; omit compiled clojure fns
             (scan-paths (System/getProperty "sun.boot.class.path")
                         (System/getProperty "java.ext.dirs")
                         (System/getProperty "java.class.path"))))

;; Force lazy seqs before any user calls, and in background threads; there's
;; no sense holding up SLIME init. (It's usually quick, but a monstrous
;; classpath could concievably take a while.)

(def top-level-classes
     (future (doall (map (comp class-or-ns-name :name)
                         (filter top-level-class?
                                 available-classes)))))

(def nested-classes
     (future (doall (map (comp class-or-ns-name :name)
                         (filter nested-class?
                                 available-classes)))))

;; start of "real" completion.clj

(defn potential-ns
  "Returns a list of potential namespace completions for a given
   namespace"
  ([] (potential-ns *ns*))
  ([ns]
     (for [ns-sym (concat (keys (ns-aliases (ns-name ns)))
                          (map ns-name (all-ns)))]
       (name ns-sym))))

(defn potential-var-public
  "Returns a list of potential public var name completions for a
   given namespace"
  ([] (potential-var-public *ns*))
  ([ns]
     (for [var-sym (keys (ns-publics ns))]
       (name var-sym))))

(defn potential-var
  "Returns a list of all potential var name completions for a given
   namespace"
  ([] (potential-var *ns*))
  ([ns]
     (for [[key v] (ns-map ns)
           :when (var? v)]
       (name key))))

(defn potential-classes
  "Returns a list of potential class name completions for a given
   namespace"
  ([] (potential-classes *ns*))
  ([ns]
     (for [class-sym (keys (ns-imports ns))]
       (name class-sym))))

(defn potential-dot
  "Returns a list of potential dot method name completions for a given
   namespace"
  ([] (potential-dot *ns*))
  ([ns]
     (map #(str "." %) (set (map member-name (mapcat instance-methods (vals (ns-imports ns))))))))

(defn potential-static
  "Returns a list of potential static members for a given namespace"
  ([#^Class class]
     (concat (map member-name (static-methods class))
             (map member-name (static-fields class)))))


(defn potential-classes-on-path
  "Returns a list of Java class and Clojure package names found on the current
  classpath. To minimize noise, list is nil unless a '.' is present in the search
  string, and nested classes are only shown if a '$' is present."
  ([#^String symbol-string]
         (when (.contains symbol-string ".")
           (if (.contains symbol-string "$")
                 @nested-classes
                 @top-level-classes))))

(defn resolve-class
  "Attempts to resolve a symbol into a java Class. Returns nil on
   failure."
  ([sym]
     (try
      (let [res (resolve sym)]
        (when (class? res)
          res))
      (catch Throwable t
        nil))))

(defn- maybe-alias [sym ns]
  (or (resolve-ns sym (maybe-ns ns))
      (maybe-ns ns)))

(defn potential-completions [symbol-ns ns]
  (if symbol-ns
    (map #(str symbol-ns "/" %)
         (if-let [class (resolve-class symbol-ns)]
           (potential-static class)
           (potential-var-public (maybe-alias symbol-ns ns))))
    (concat (potential-var ns)
            (when-not symbol-ns
              (potential-ns))
            (potential-classes ns)
            (potential-dot ns))))


;; custom additions for cljsh and rlwarp
;; for the rlwrap word list, we want all words from ns-map
;; and all fqn's from all public keys for each ns in all-ns

(def special-forms
  (map name '[def if do let quote var fn loop recur throw try monitor-enter monitor-exit dot new set!]))

(defn print-current-ns-words []
	(doall (map println (sort (cljsh.completion/potential-completions nil *ns*)))))

(defn print-fqn-words [ns]
	(doall (map println (sort (cljsh.completion/potential-completions ns "")))))

(defn print-all-fqn-words []
	(doall (map println 
							(sort (flatten 
								(map 	#(cljsh.completion/potential-completions % "") 
											(map 	#(symbol (ns-name %)) 
														(all-ns))))))))

(defn print-all-words []
	(doall (map println (sort (concat
		special-forms
		(cljsh.completion/potential-completions nil *ns*)
		(flatten (map	#(cljsh.completion/potential-completions % "") 
									(map 	#(symbol (ns-name %)) 
												(all-ns)))))))))

(defn all-current-ns-words []
	(doall (sort (concat
		special-forms
		(cljsh.completion/potential-completions nil *ns*)))))

(defn print-all-current-ns-words []
	(doall (map println (sort (concat
		special-forms
		(cljsh.completion/potential-completions nil *ns*))))))
		

(defn ns-find
  "locate and return the namespace for a given string/symbol/keyword/namespace"
  ([] (ns-find *ns*))
  ([package]
  (cond
   (symbol? package) (find-ns package)
   (string? package) (ns-find (symbol package))
   (keyword? package) (ns-find (name package))
   (instance? clojure.lang.Namespace package) package
   :else nil)))



(defn dir-fqn 
  ([] (dir-fqn *ns*))
  ([ns-maybe]
    (when-let [ns (ns-find ns-maybe)]
      (doseq [x (clojure.repl/dir-fn ns)] 
        (println (str (ns-name ns) "/" x))))))


