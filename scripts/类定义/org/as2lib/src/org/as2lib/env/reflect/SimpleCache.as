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
import org.as2lib.env.overload.Overload;
import org.as2lib.env.reflect.ClassInfo;
import org.as2lib.env.reflect.PackageInfo;
import org.as2lib.env.reflect.Cache;

/**
 * {@code SimpleCache} is a simple and performant implementation of the {@code Cache}
 * interface.
 * 
 * <p>The caching of classes and packages leads to better performance. You also
 * must cache them because for example the parent of two classes residing in the
 * same package should be the same {@code PackageInfo} instance.
 * 
 * <p>This cache is mostly used internally. But you can also use it to add
 * {@code ClassInfo} or {@code PackageInfo} instances directly so that they do not
 * have to be searched for. This can improve the performance dramatically with
 * classes or packages that are needed quite often.
 *
 * <p>This implementation sets a variable with name {@code "__as2lib__hashCode"} on
 * every cached class and package to offer better performance. Do not delete this
 * property.
 *
 * @author Simon Wacker
 */
class org.as2lib.env.reflect.SimpleCache extends BasicClass implements Cache {
	
	/** The number of generated hash codes. */
	private static var hashCodeCounter:Number = 0;

	/** The added infos. */
	private var cache:Array;
	
	/** The root package. */
	private var root:PackageInfo;
	
	/**
	 * Constructs a new {@code SimpleCache} instance.
	 *
	 * <p>The root/default package determines where the {@code ClassAlgorithm} and
	 * {@code PackageAlgorithm} classes start their search.
	 * 
	 * @param root the root/default package of the package hierarchy
	 */
	public function SimpleCache(root:PackageInfo) {
		this.root = root;
		releaseAll();
	}
	
	/**
	 * @overload #getClassByClass
	 * @overload #getClassByInstance
	 */
	public function getClass():ClassInfo {
		var o:Overload = new Overload(this);
		o.addHandler([Function], getClassByClass);
		o.addHandler([Object], getClassByInstance);
		return o.forward(arguments);
	}
	
	/**
	 * Returns the class info representing the passed-in {@code clazz}.
	 * 
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>There is no corresponding {@code ClassInfo} instance cached.</li>
	 *   <li>The passed-in {@code clazz} is {@code null} or {@code undefined}.</li>
	 * </ul>
	 *
	 * @param clazz the class to return the class info for
	 * @return the class info representing the passed-in {@code clazz}
	 */
	public function getClassByClass(clazz:Function):ClassInfo {
		if (clazz === null || clazz === undefined) return null;
		var p:Object = clazz.prototype;
		var c:Number = p.__as2lib__hashCode;
		if (c == undefined) return null;
		if (c == p.__proto__.__as2lib__hashCode) {
			return null;
		}
		return cache[c];
	}
	
	/**
	 * Returns the class info representing the class the {@code instance} was
	 * instantiated of.
	 * 
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>There is no corresponding {@code ClassInfo} instance cached.</li>
	 *   <li>The passed-in {@code instance} is {@code null} or {@code undefined}.</li>
	 * </ul>
	 *
	 * @param instance the instance to return the appropriate class info for
	 * @return the class info representing the instance's class
	 */
	public function getClassByInstance(instance):ClassInfo {
		if (instance === null || instance === undefined) return null;
		var p:Object = instance.__proto__;
		var c:Number = p.__as2lib__hashCode;
		if (c == undefined) return null;
		if (c == p.__proto__.__as2lib__hashCode) {
			return null;
		}
		return cache[c];
	}
	
	/**
	 * Adds the passed-in {@code classInfo} to the list of cached class infos and returns
	 * this {@code classInfo}.
	 * 
	 * @param classInfo the class info to add
	 * @return the passed-in and added {@code classInfo}
	 */
	public function addClass(info:ClassInfo):ClassInfo {
		if (!info) return null;
		var p = info.getType().prototype;
		var h:Number = p.__as2lib__hashCode;
		if (h != null && h != p.__proto__.__as2lib__hashCode) {
			cache[h] = info;
		} else {
			cache[p.__as2lib__hashCode = hashCodeCounter++] = info;
			_global.ASSetPropFlags(p, "__as2lib__hashCode", 1, true);
		}
		return info;
	}
	
	/**
	 * Returns the package info representing the passed-in {@code package}. 
	 *
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>There is no corresponding {@code PackageInfo} instance cached.</li>
	 *   <li>The passed-in {@code package} is {@code null} or {@code undefined}.</li>
	 * </ul>
	 *
	 * @param package the package to return the appropriate package info for
	 * @return the pakcage info representing the passed-in {@code package}
	 */
	public function getPackage(package):PackageInfo {
		if (package === null || package === undefined) return null;
		var c:Number = package.__as2lib__hashCode;
		if (c == null) return null;
		if (c == package.__proto__.__as2lib__hashCode) {
			return null;
		}
		return cache[c];
	}
	
	/**
	 * Adds the passed-in {@code packageInfo} to this cache and returns this added
	 * {@code packageInfo}.
	 * 
	 * @param packageInfo the package info to add
	 * @return the passed-in and added {@code packageInfo}
	 */
	public function addPackage(info:PackageInfo):PackageInfo {
		if (!info) return null;
		var p = info.getPackage();
		var h:Number = p.__as2lib__hashCode;
		if (h != null && h != p.__proto__.__as2lib__hashCode) {
			cache[h] = info;
		} else {
			cache[p.__as2lib__hashCode = hashCodeCounter++] = info;
			_global.ASSetPropFlags(p, "__as2lib__hashCode", 1, true);
		}
		return info;
	}
	
	/**
	 * Returns the root package of the whole package hierarchy.
	 * 
	 * <p>The root package is also refered to as the default package.
	 *
	 * <p>The root/default package determines where the {@code ClassAlgorithm} and
	 * {@code PackageAlgorithm} classes start their search.
	 *
	 * @return the root/default package
	 */
	public function getRoot(Void):PackageInfo {
		return root;
	}
	
	/**
	 * Releases all cached class and package infos.
	 *
	 * <p>Note that their {@code __as2lib__hashCode} variable stays the same.
	 */
	public function releaseAll(Void):Void {
		cache = new Array();
		addPackage(root);
	}
	
}