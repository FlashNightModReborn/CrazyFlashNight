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
import org.as2lib.env.reflect.PackageNotFoundException;
import org.as2lib.env.reflect.Cache;
import org.as2lib.env.reflect.PackageInfo;
import org.as2lib.env.reflect.ReflectConfig;

/**
 * {@code PackageAlgorithm} searches for the specified package and returns the
 * package info representing the found package.
 * 
 * <p>To obtain the package info corresponding to package you use this class as
 * follows.
 *
 * <code>
 *   var packageAlgorithm:PackageAlgorithm = new PackageAlgorithm();
 *   var packageInfoByPackage:PackageInfo = packageAlgorithm.execute(org.as2lib.core);
 * </code>
 *
 * <p>It is also possible to retrieve a package info by name.
 *
 * <code>
 *   packageInfoByName:PackageInfo = packageAlgorithm.executeByName("org.as2lib.core");
 * </code>
 *
 * <p>Already retrieved package infos are stored in a cache. There thus exists only
 * one {@code PackageInfo} instance per package. The following traces {@code true}.
 * 
 * <code>
 *   trace(packageInfoByPackage == packageInfoByName);
 * </code>
 *
 * @author Simon Wacker
 */
class org.as2lib.env.reflect.algorithm.PackageAlgorithm extends BasicClass {
	
	/** The chache. */
	private var c:Cache;
	
	/** The found packages. */
	private var p;
	
	/**
	 * Constructs a new {@code PackageAlgorithm} instance.
	 */
	public function PackageAlgorithm(Void) {
	}
	
	/**
	 * Sets the cache that is used by the {@link #execute} method to look whether the
	 * package to find is already stored and where to start the search if not.
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
	 * Executes the search for the passed-in package {@code o} and returns information
	 * about this package.
	 * 
	 * <p>The returned object has the following properties:
	 * <dl>
	 *   <dt>package</dt>
	 *   <dd>The package as {@code Object} that has been searched for, this is the
	 *       passed-in package {@code o}.</dd>
	 *   <dt>name</dt>
	 *   <dd>The name as {@code String} of the searched for package.</dd>
	 *   <dt>parent</dt>
	 *   <dd>The parent represented by a {@ling PackageInfo} instance the searched for
	 *       package is a member of.</dd>
	 * </dl>
	 *
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>The passed-in package {@code o} is {@code null} or {@code undefined}.</li>
	 *   <li>The searched for package {@code o} could not be found.</li>
	 * </ul>
	 *
	 * <p>The search starts on the package returned by the cache's {@code getRoot}
	 * method, this is by default {@code _global}.
	 * 
	 * @param o the package to return information about
	 * @return an object that contains information about the passed-in package
	 */
	public function execute(o) {
		if (o === null || o === undefined) return null;
		p = null;
		// must set access permissions because by default all package members in _global are hidden
		_global.ASSetPropFlags(o, null, 0, true);
		_global.ASSetPropFlags(o, ["__proto__", "constructor", "__constructor__", "prototype"], 1, true);
		findAndStore(getCache().getRoot(), o);
		return p;
	}
	
	private function findAndStore(a:PackageInfo, o):Boolean {
		var b = a.getPackage();
		var i:String;
		for (i in b) {
			var e:Object = b[i];
			if (typeof(e) == "object") {
				if (e.valueOf() == o.valueOf()) {
					p = new Object();
					p.package = o;
					p.name = i;
					p.parent = a;
					return true;
				}
				var d:PackageInfo = c.getPackage(e);
				if (!d) {
					d = c.addPackage(new PackageInfo(e, i, a));
				}
				if (!d.isParentPackage(a)) {
					// todo: replace recursion with loop
					if (findAndStore(d, o)) {
						return true;
					}
				}
			}
		}
		return false;
	}
	
	/**
	 * Returns the package info representing the package corresponding to the passed-in
	 * package name {@code n}.
	 * 
	 * <p>The name must be fully qualified, that means it must consist of the package's
	 * path as well as its name. For example 'org.as2lib.core'.
	 *
	 * <p>The search starts on the package returned by the {@link Cache#getRoot} method
	 * of the set cache. If this method returns a package info whose {@code getFullName}
	 * method returns {@code null}, {@code undefined} or an empty string {@code "_global"}
	 * is used instead
	 * 
	 * @param n the fully qualified name of the package
	 * @return the package info representing the package corresponding to the passed-in
	 * name
	 * @throws IllegalArgumentException if the passed-in name is {@code null},
	 * {@code undefined} or an empty string or if the object corresponding to the
	 * passed-in name is not of type {@code "object"}
	 * @throws PackageNotFoundException if a package with the passed-in name could not
	 * be found
	 */
	public function executeByName(n:String):PackageInfo {
		if (!n) throw new IllegalArgumentException("The passed-in package name '" + n + "' is not allowed to be null, undefined or an empty string.", this, arguments);
		var p:PackageInfo = getCache().getRoot();
		var x:String = p.getFullName();
		if (!x) x = "_global";
		var f:Object = eval(x + "." + n);
		if (f === null || f === undefined) {
			throw new PackageNotFoundException("A package with the name '" + n + "' could not be found.", this, arguments);
		}
		if (typeof(f) != "object") throw new IllegalArgumentException("The object corresponding to the passed-in package name '" + n + "' is not of type object.", this, arguments);
		var r:PackageInfo = c.getPackage(f);
		if (r) return r;
		var a:Array = n.split(".");
		var g:Object = p.getPackage();
		for (var i:Number = 0; i < a.length; i++) {
			g = g[a[i]];
			p = c.addPackage(new PackageInfo(g, a[i], p));
		}
		return p;
	}
	
}