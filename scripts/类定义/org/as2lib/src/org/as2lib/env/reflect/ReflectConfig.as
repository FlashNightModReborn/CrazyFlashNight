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
import org.as2lib.env.reflect.Cache;
import org.as2lib.env.reflect.SimpleCache;
import org.as2lib.env.reflect.PackageInfo;

/**
 * {@code ReflectConfig} is the main config used to globally configure key parts of
 * the work the classes of the reflect package try to solve.
 * 
 * @author Simon Wacker
 */
class org.as2lib.env.reflect.ReflectConfig extends BasicClass {
	
	/** Caches found classes and packages. */
	private static var cache:Cache;
	
	/**
	 * Private constructor.
	 */
	private function ReflectConfig(Void) {
	}
	
	/**
	 * Returns the cache used to cache all classes and packages that have already been
	 * found.
	 * 
	 * <p>If no cache was set manually via {@link #setCache} the default cache will be
	 * returned, that is an instance of class {@link SimpleCache} and that is configured
	 * with the root package returned by the {@link PackageInfo#getRootPackage} method.
	 *
	 * @return the cache used to cache classes and packages
	 */
	public static function getCache(Void):Cache {
		if (!cache) cache = new SimpleCache(PackageInfo.getRootPackage());
		return cache;
	}
	
	/**
	 * Sets the new cache used to cache classes and packages.
	 * 
	 * <p>If {@code newCache} is {@code null} the default cache will be returned by
	 * the {@link #getCache} method.
	 *
	 * @param cache the new cache to use
	 */
	public static function setCache(newCache:Cache):Void {
		cache = newCache;
	}
	
}