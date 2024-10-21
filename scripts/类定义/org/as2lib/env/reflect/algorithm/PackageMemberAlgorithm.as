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
import org.as2lib.env.reflect.PackageInfo;
import org.as2lib.env.reflect.ClassInfo;
import org.as2lib.env.reflect.Cache;
import org.as2lib.env.reflect.ReflectConfig;

/**
 * {@code PackageMemberAlgorithm} searches for members, that means types and packages,
 * of a specific package. Sub-packages are not searched through.
 * 
 * <p>This class is mostly used internally. If you wanna obtain the members of a 
 * package you need its representing {@code PackageInfo}. You can then also use the
 * {@link PackageInfo#getMembers}, {@link PackageInfo#getMemberClasses} and
 * {@link PackageInfo#getMemberPackages} methods directly and do not have to make
 * the detour over this method. The PackageInfo's methods are also easier to use and
 * offer some extra functionalities.
 *
 * <p>If you nevertheless want to use this class here is how it works.
 *
 * <code>
 *   var packageInfo:PackageInfo = PackageInfo.forPackage(org.as2lib.core);
 *   var packageMemberAlgorithm:PackageMemberAlgorithm = new PackageMemberAlgorithm();
 *   var members:Array = packageMemberAlgorithm.execute(packageInfo);
 * </code>
 *
 * <p>Refer to the {@link #execute} method for details on how to get data from the
 * members array appropriately.
 *
 * @author Simon Wacker
 */
class org.as2lib.env.reflect.algorithm.PackageMemberAlgorithm extends BasicClass {
	
	/** The cache. */
	private var c:Cache;
	
	/**
	 * Constructs a new {@code PackageMemberAlgorithm} instance.
	 */
	public function PackageMemberAlgorithm(Void) {
	}
	
	/**
	 * Sets the cache that is used by the {@link #execute} method to look whether the
	 * member package or class is already stored and to get the root package to start the
	 * search if not.
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
	 * Executes the search for the members, that means member types and packages, in
	 * the passed-in package {@code p}.
	 * 
	 * <p>The resulting array contains instances of type {@link PackageMemberInfo}, that
	 * is either of type {@link ClassInfo} or {@link PackageInfo}.
	 *
	 * <p>The specific members can be either referenced by index or by name.
	 * <dl>
	 *   <dt>Reference member by index; can be class or package.</dt>
	 *   <dd><code>myMembers[0];</code></dd>
	 *   <dt>Reference class by index.</dt>
	 *   <dd><code>myMembers.classes[0];</code></dd>
	 *   <dt>Reference package by index.</dt>
	 *   <dd><code>myMembers.packages[0];</code></dd>
	 *   <dt>Reference member by index; can be class or package.</dt>
	 *   <dd><code>myMembers.MyClass;</code> or <code>myMembers.mypackage</code></dd>
	 *   <dt>Reference class by name; use only the name of the class, excluding the namespace.</dt>
	 *   <dd><code>myMembers.classes.MyClass;</code></dd>
	 *   <dt>Reference package by name; use only the package name, excluding the namespace.</dt>
	 *   <dd><code>myMembers.packages.mypackage;</code></dd>
	 * </dl>
	 *
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>The passed-in package {@code p} is {@code null} or {@code undefined}.</li>
	 *   <li>The {@code getPackage} method of the passed-in package returns {@code null}.</li>
	 * </ul>
	 *
	 * <p>Only the passed-in package {@code p} will be searched through, no sub-packages.
	 *
	 * <p>In case the cache already contains a specific member class or package the
	 * contained info it will be added to the resulting members array.
	 * 
	 * @param g the package info instance representing the package to search through
	 * @return the members of the package, an empty array or {@code null}
	 */
	public function execute(p:PackageInfo):Array {
		if (p == null) return null;
		var t:Object = p.getPackage();
		if (!t) return null;
		// must set access permissions because by default all package members in _global are hidden
		_global.ASSetPropFlags(t, null, 0, true);
		_global.ASSetPropFlags(t, ["__proto__", "constructor", "__constructor__", "prototype"], 1, true);
		getCache();
		var r:Array = new Array();
		var n:Array = new Array();
		r["classes"] = n;
		var m:Array = new Array();
		r["packages"] = m;
		var i:String;
		for (i in t) {
			// The last two checks are made to exclude methods from _global like "ASnative".
			// The last two checks must be made with strict eval because there are types with prototypes whose "valueOf"
			// method returns "null" or "undefined", for example "Date", "Boolean" and "Number". But if you do a strict
			// eval check between these prototypes and "null" or "undefined", "false" is be returned.
			if (typeof(t[i]) == "function" && t[i].prototype !== undefined && t[i].prototype !== null) {
				// flex stores every class in _global and in its actual package
				// e.g. org.as2lib.core.BasicClass is stored in _global with name org_as2lib_core_BasicClass
				// this if-clause excludes these extra stored classes
				if (!eval("_global." + i.split("_").join(".")) || i.indexOf("_") < 0) {
					var b:ClassInfo = c.getClassByClass(t[i]);
					if (!b) {
						b = c.addClass(new ClassInfo(t[i], i, p));
					}
					r[r.length] = b;
					r[i] = b;
					n[n.length] = b;
					n[i] = b;
				}
			} else if (typeof(t[i]) == "object") {
				var a:PackageInfo = c.getPackage(t[i]);
				if (!a) {
					a = c.addPackage(new PackageInfo(t[i], i, p));
				}
				r[r.length] = a;
				r[i] = a;
				m[m.length] = a;
				m[i] = a;
			}
		}
		return r;
	}
	
}