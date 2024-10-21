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
import org.as2lib.env.reflect.MethodInfo;
import org.as2lib.env.reflect.ClassInfo;

/**
 * {@code MethodAlgorithm} searches for all methods of a specific class.
 * 
 * <p>This class is mostly used internally. If you wanna obtain the methods of a
 * class you need its representing ClassInfo. You can then also use the
 * {@link ClassInfo#getMethods} method directly and do not have to make the detour
 * over this class. The {@link ClassInfo#getMethods} method is also easier to use
 * and offers some extra functionalities.
 *
 * <p>If you nevertheless want to use this class here is how it works.
 *
 * <code>
 *   var classInfo:ClassInfo = ClassInfo.forClass(MyClass);
 *   var methodAlgorithm:MethodAlgorithm = new MethodAlgorithm();
 *   var methods:Array = methodAlgorithm.execute(classInfo);
 * </code>
 *
 * <p>Refer to the {@link #execute} method for details on how to get data from the
 * methods array appropriately.
 * 
 * @author Simon Wacker
 */
class org.as2lib.env.reflect.algorithm.MethodAlgorithm extends BasicClass {
	
	/** The temporary result. */
	private var r:Array;
	
	/** The class to return methods for. */
	private var i:ClassInfo;
	
	/** Determines whether the method is static or not. */
	private var s:Boolean;
	
	/**
	 * Constructs a new {@code MethodAlgorithm} instance.
	 */
	public function MethodAlgorithm(Void) {
	}
	
	/**
	 * Searches for all methods of the passed-in class {@code i}.
	 * 
	 * <p>The resulting array contains instances of type {@link MethodInfo}.
	 * 
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>The passed-in class {@code i} is {@code null} or {@code undefined}.</li>
	 *   <li>The {@code getType} method of the passed-in class returns {@code null}.</li>
	 * </ul>
	 *
	 * <p>Only the passed in class will be searched through, no super classes.
	 *
	 * <p>The found methods are stored in the resulting array by index as well as by
	 * name. This means you can obtain {@code MethodInfo} instances either by index:
	 * <code>var myMethod:MethodInfo = myMethods[0];</code>
	 *
	 * <p>Or by name:
	 * <code>var myMethod:MethodInfo = myMethods["myMethodName"];</code>
	 * 
	 * @param i the class info instance representing the class to search through
	 * @return the found methods, an empty array or {@code null}
	 */
	public function execute(i:ClassInfo):Array {
		if (i == null) return null;
		var c:Function = i.getType();
		if (!c) return null;
		this.i = i;
		this.r = new Array();
		
		this.s = true;
		_global.ASSetPropFlags(c, null, 0, true);
		_global.ASSetPropFlags(c, ["__proto__", "constructor", "__constructor__", "prototype"], 1, true);
		search(c);
		
		this.s = false;
		var p:Object = c.prototype;
		_global.ASSetPropFlags(p, null, 0, true);
		_global.ASSetPropFlags(p, ["__proto__", "constructor", "__constructor__", "prototype"], 1, true);
		search(p);
		
		// ASSetPropFlags must be restored because unexpected behaviors get caused otherwise
		_global.ASSetPropFlags(c, null, 1, true);
		_global.ASSetPropFlags(p, null, 1, true);
		
		return r;
	}
	
	private function search(t):Void {
		var k:String;
		for (k in t) {
			if (typeof(t[k]) == "function"
					&& k.indexOf("__get__") < 0
					&& k.indexOf("__set__") < 0) {
				r[r.length] = new MethodInfo(k, i, s);
				r[k] = r[r.length-1];
			}
		}
	}
	
}