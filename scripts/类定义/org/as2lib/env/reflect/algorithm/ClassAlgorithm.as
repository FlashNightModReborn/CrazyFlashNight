/*
 * Copyright the original author or authors.
 * 
 * Licensed under the MOZILLA PUBLIC LICENSE, Version 1.1 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *      http://www.mozilla.org/MPL/MPL-1.1.html
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import org.as2lib.core.BasicClass;
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.env.reflect.ClassNotFoundException;
import org.as2lib.env.reflect.Cache;
import org.as2lib.env.reflect.PackageInfo;
import org.as2lib.env.reflect.ClassInfo;
import org.as2lib.env.reflect.ReflectConfig;

/**
 * {@code ClassAlgorithm} searches for the class of a specific instance or class
 * and returns information about that class.
 * 
 * <p>This class is rather cumbersome to use. It is recommended to use the static
 * {@link ClassInfo#forObject}, {@link ClassInfo#forInstance}, {@link ClassInfo#forClass}
 * and {@link ClassInfo#forName} methods instead. They offer more sophisticated
 * return values and do also store {@code ClassInfo} instances retrieved by classes
 * or instances and not only those by name like this algorithm does.
 *
 * <p>To obtain information corresponding to an instance or a class you can use
 * this class as follows.
 * 
 * <code>
 *   var myInstance:MyClass = new MyClass();
 *   var classAlgorithm:ClassAlgorithm = new ClassAlgorithm();
 *   var infoByInstance:Object = classAlgorithm.execute(myInstance);
 *   var infoByClass:Object = classAlgorithm.execute(MyClass);
 * </code>
 *
 * <p>It is also possible to retrieve a class info by name.
 *
 * <code>
 *   classInfoByName:ClassInfo = classAlgorithm.executeByName("MyClass");
 * </code>
 *
 * <p>If the class is not contained in the root/default package you must specify
 * the whole path / its namespace.
 * 
 * <code>
 *   classInfoByName:ClassInfo = classAlgorithm.executeByName("org.as2lib.MyClass");
 * </code>
 *
 * <p>Already retrieved class infos are stored in a cache. There thus exists only
 * one {@code ClassInfo} instance per class. Note that the {@link #execute} method
 * does not return {@code ClassInfo} instances and does thus not store the found
 * information.
 * 
 * @author Simon Wacker
 */
class org.as2lib.env.reflect.algorithm.ClassAlgorithm extends BasicClass {
	
	/** The cache to store class and package infos. */
	private var c:Cache;
	
	/** The temporary result. */
	private var r;
	
	/**
	 * Constructs a new {@code ClassAlgorithm} instance.
	 */
	public function ClassAlgorithm(Void) {
	}
	
	/**
	 * Sets the cache that is used by the {@link #executeByName} method to look whether
	 * the class the shall be found is already stored.
	 *
	 * <p>This cache also determines where the search for a class starts.
	 * 
	 * @param cache the new cache
	 */
	public function setCache(cache:Cache):Void {
		c = cache;
	}
	
	/**
	 * Returns the cache set via the {@link #setCache} method or the default cache that
	 * is returned by the {@link ReflectConfig#getCache} method.
	 * 
	 * @return the currently used cache
	 */
	public function getCache(Void):Cache {
		if (!c) c = ReflectConfig.getCache();
		return c;
	}
	
	/**
	 * @overload #executeByClass
	 * @overload #executeByInstance
	 */
	public function execute(d) {
		if (typeof(d) == "function") {
			return executeByClass(d);
		}
		return executeByInstance(d);
	}
	
	/**
	 * Executes the search for the passed-in class {@code d} and returns information
	 * about this class.
	 * 
	 * <p>The returned object has the following properties:
	 * <dl>
	 *   <dt>clazz</dt>
	 *   <dd>The class as {@code Function} that has been searched for, this is the
	 *       passed-in class {@code d}.</dd>
	 *   <dt>name</dt>
	 *   <dd>The name as {@code String} of the searched for class.</dd>
	 *   <dt>package</dt>
	 *   <dd>The package represented by a {@link PackageInfo} instance the class is
	 *       a member of.</dd>
	 * </dl>
	 *
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>The passed-in class {@code d} is {@code null} or {@code undefined}.</li>
	 *   <li>The passed-in class {@code d} could not be found.</li>
	 * </ul>
	 *
	 * <p>The search starts on the package returned by the {@link Cache#getRoot} method
	 * of the set cache. If this method returns a package info whose {@code getPackage}
	 * method returns {@code null} or {@code undefined} {@code _global} is used instead.
	 * 
	 * @param d the class to return information about
	 * @return an object that contains information about the passed-in class {@code d}
	 * @see #getCache
	 */
	public function executeByClass(d:Function) {
		if (d === null || d === undefined) return null;
		return executeByComparator(function(f:Function) {
			// use f.valueOf() because this allows one to overwrite the original class,
			// to add a valueOf method that returns the original class and still find
			// the correct class at run-time (this is for example used by the aop framework)
			return f.valueOf() == d.valueOf();
		});
	}
	
	/**
	 * Executes the search for the class the passed-in object {@code d} is an instance
	 * of and returns information about that class.
	 * 
	 * <p>The returned object has the following properties:
	 * <dl>
	 *   <dt>clazz</dt>
	 *   <dd>The class as {@code Function} that has been searched for.</dd>
	 *   <dt>name</dt>
	 *   <dd>The name as {@code String} of the searched for class.</dd>
	 *   <dt>package</dt>
	 *   <dd>The package represented by a {@link PackageInfo} instance the class is
	 *       a member of.</dd>
	 * </dl>
	 *
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>The passed-in instance {@code d} is {@code null} or {@code undefined}.</li>
	 *   <li>The class of the passed-in instance could not be found.</li>
	 * </ul>
	 *
	 * <p>The search starts on the package returned by the {@link Cache#getRoot} method
	 * of the set cache. If this method returns a package info whose {@code getPackage}
	 * method returns {@code null} or {@code undefined} {@code _global} is used instead.
	 *
	 * @param d the instance of the class to return information about
	 * @return an object that contains information about the class the passed-in object
	 * {@code d} is an instance of
	 * @see #getCache
	 */
	public function executeByInstance(d) {
		// not 'if (!d)' because 'd' could be en empty string or a boolean
		// 'valueOf' method of 'd' could return 'null' or 'undefined' thus strict eval is used
		if (d === null || d === undefined) return null;
		return executeByComparator(function(f:Function) {
			return f.prototype === d.__proto__;
		});
	}
	
	/**
	 * Executes the search for a class and returns information about that class.
	 * 
	 * <p>The returned object has the following properties:
	 * <dl>
	 *   <dt>clazz</dt>
	 *   <dd>The class as {@code Function} that has been searched for.</dd>
	 *   <dt>name</dt>
	 *   <dd>The name as {@code String} of the searched for class.</dd>
	 *   <dt>package</dt>
	 *   <dd>The package represented by a {@ling PackageInfo} instance the class is
	 *       a member of.</dd>
	 * </dl>
	 *
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>The passed-in comparator {@code v} method is {@code null} or {@code undefined}.</li>
	 *   <li>The searched for class could not be found.</li>
	 * </ul>
	 * 
	 * <p>The search starts on the package returned by the {@link Cache#getRoot} method
	 * of the set cache. If this method returns a package info whose {@code getPackage}
	 * method returns {@code null} or {@code undefined} {@code _global} is used instead.
	 *
	 * <p>The passed-in comparator is invoked for every found class to determine whether
	 * it is the right one or not. The comparator method gets passed the found class and
	 * must return {@code true} or {@code false}. If it returns {@code true} the
	 * algorithm stops and returns the information about this class.
	 * @param v the comparator to determine the correct class
	 * @return an object that contains information about the class
	 * @see #getCache
	 */
	public function executeByComparator(v:Function) {
		if (!v) return null;
		r = null;
		var b:PackageInfo = getCache().getRoot();
		var a:Object = b.getPackage();
		if (!a) a = _global;
		_global.ASSetPropFlags(a, null, 0, true);
		_global.ASSetPropFlags(a, ["__proto__", "constructor", "__constructor__", "prototype"], 1, true);
		findAndStore(b, v);
		return r;
	}
	
	private function findAndStore(a:PackageInfo, v:Function):Boolean {
		var p = a.getPackage();
		var i:String;
		for (i in p) {
			var f = p[i];
			if (typeof(f) == "function") {
				if (v(f)) {
					// flex stores every class in _global and in its actual package
					// e.g. org.as2lib.core.BasicClass is stored in _global with name org_as2lib_core_BasicClass
					// this if-clause excludes these extra stored classes
					if (!eval("_global." + i.split("_").join(".")) || i.indexOf("_") < 0) {
						r = new Object();
						r.clazz = f;
						r.name = i;
						r.package = a;
						return true;
					}
				}
			} else if (typeof(f) == "object") {
				var e:PackageInfo = c.getPackage(f);
				if (!e) {
					e = c.addPackage(new PackageInfo(f, i, a));
				}
				if (!e.isParentPackage(a)) {
					// todo: replace recursion with loop
					if (findAndStore(e, v)) {
						return true;
					}
				}
			}
		}
		return false;
	}
	
	/**
	 * Returns the class info representing the class corresponding to the passed-in
	 * class name {@code n}.
	 * 
	 * <p>The class name must be fully qualified, that means it must consist of the
	 * class's path (namespace) as well as its name. For example 'org.as2lib.core.BasicClass'.
	 *
	 * <p>The search starts on the package returned by the {@link Cache#getRoot} method
	 * of the set cache. If this method returns a package info whose {@code getFullName}
	 * method returns {@code null} or {@code undefined} {@code "_global"} is used instead.
	 * 
	 * @param n the fully qualified name of the class
	 * @return the class info representing the class corresponding to the passed-in name
	 * @throws IllegalArgumentException if the passed-in name is {@code null}, {@code undefined}
	 * or an empty string or if the object corresponding to the passed-in name is not of
	 * type function
	 * @throws ClassNotFoundException if a class with the passed-in name could not be found
	 */
	public function executeByName(n:String):ClassInfo {
		if (!n) throw new IllegalArgumentException("The passed-in class name '" + n + "' is not allowed to be null, undefined or an empty string.", this, arguments);
		var p:PackageInfo = getCache().getRoot();
		var x:String = p.getFullName();
		if (!x) x = "_global";
		var f:Function = eval(x + "." + n);
		if (!f) throw new ClassNotFoundException("A class with the name '" + n + "' could not be found.", this, arguments);
		if (typeof(f) != "function") throw new IllegalArgumentException("The object corresponding to the passed-in class name '" + n + "' is not of type function.", this, arguments);
		var r:ClassInfo = c.getClassByClass(f);
		if (r) return r;
		var a:Array = n.split(".");
		var g:Object = p.getPackage();
		for (var i:Number = 0; i < a.length; i++) {
			if (i == a.length-1) {
				return c.addClass(new ClassInfo(f, a[i], p));
			} else {
				g = g[a[i]];
				p = c.addPackage(new PackageInfo(g, a[i], p));
			}
		}
		return null;
		// unreachable!!!
	}
	
}