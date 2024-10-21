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
import org.as2lib.env.reflect.PropertyInfo;
import org.as2lib.env.reflect.ClassInfo;

/**
 * {@code PropertyAlgorithm} searches for all properties of a class.
 *
 * <p>Properties are not variables but implicit getters and setters that can be
 * added via the {@code set} or {@code get} keyword or the {@code addProperty}
 * method.
 * 
 * <p>This class is mostly used internally. If you wanna obtain the properties of a
 * class you need its representing {@code ClassInfo}. You can then also use the
 * {@link ClassInfo#getProperties} method directly and do not have to make the detour
 * over this class. The {@link ClassInfo#getProperties} method is also easier to use
 * and offers some extra functionalities.
 *
 * <p>If you nevertheless want to use this class here is how it works.
 *
 * <code>
 *   var classInfo:ClassInfo = ClassInfo.forClass(MyClass);
 *   var propertyAlgorithm:PropertyAlgorithm = new PropertyAlgorithm();
 *   var properties:Array = propertyAlgorithm.execute(classInfo);
 * </code>
 *
 * <p>Refer to the {@link #execute} method for details on how to get data from the
 * properties array appropriately.
 * 
 * @author Simon Wacker
 */
class org.as2lib.env.reflect.algorithm.PropertyAlgorithm extends BasicClass {
	
	/** The temporary result. */
	private var r:Array;
	
	/** Already found getters. */
	private var g:Object;
	
	/** Already found setters. */
	private var s:Object;
	
	/** The class to search through. */
	private var c:ClassInfo;
	
	/** Determines whether the property is static. */
	private var a:Boolean;
	
	/**
	 * Constructs a new {@code PropertyAlgorithm} instance.
	 */
	public function PropertyAlgorithm(Void) {
	}
	
	/**
	 * Searches for all properties of the passed-in class {@code c}.
	 * 
	 * <p>The resulting array contains {@link PropertyInfo} instances.
	 * 
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>The passed-in class {@code c} is {@code null} or {@code undefined}.</li>
	 *   <li>The {@code getType} method of the passed-in class returns {@code null}.</li>
	 * </ul>
	 * 
	 * <p>Only the passed in class will be searched through, no super classes.
	 *
	 * <p>The found properties are stored in the resulting array by index as well as by
	 * name. This means you can obtain {@code PropertyInfo} instances either by index:
	 * <code>var myProperty:PropertyInfo = myProperties[0];</code>
	 * 
	 * <p>Or by name:
	 * <code>var myProperty:PropertyInfo = myProperties["myPropertyName"];</code>
	 * 
	 * @param c the class info instance representing the class to search through
	 * @return the found properties, an empty array or {@code null}
	 */
	public function execute(c:ClassInfo):Array {
		if (c == null) return null;
		var b:Function = c.getType();
		if (!b) return null;
		this.c = c;
		this.r = new Array();
		this.g = new Object();
		this.s = new Object();
		
		this.a = true;
		_global.ASSetPropFlags(b, null, 0, true);
		_global.ASSetPropFlags(b, ["__proto__", "constructor", "prototype"], 1, true);
		search(b);
		
		this.a = false;
		var d:Object = b.prototype;
		_global.ASSetPropFlags(d, null, 0, true);
		_global.ASSetPropFlags(d, ["__proto__", "constructor", "__constructor__"], 1, true);
		search(d);
		
		// ASSetPropFlags must be restored because unexpected behaviours get caused otherwise
		_global.ASSetPropFlags(b, null, 1, true);
		_global.ASSetPropFlags(d, null, 1, true);
		
		return r;
	}
	
	private function search(t):Void {
		var i:String;
		for (i in t) {
			if (typeof(t[i]) == "function") {
				var n:String = i.substring(7);
				if (i.indexOf("__get__") == 0) {
					g[n] = true;
					if (!s[n]) {
						r[r.length] = new PropertyInfo(n, c, a, t["__set__" + n], t[i]);
						r[n] = r[r.length-1];
					}
				} else if (i.indexOf("__set__") == 0) {
					s[n] = true;
					if (!g[n]) {
						r[r.length] = new PropertyInfo(n, c, a, t[i], t["__get__" + n]);
						r[n] = r[r.length-1];
					}
				}
			}
		}
	}
	
}