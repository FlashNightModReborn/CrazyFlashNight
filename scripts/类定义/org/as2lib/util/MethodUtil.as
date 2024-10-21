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

/**
 * @author Simon Wacker
 */
class org.as2lib.util.MethodUtil extends BasicClass {
	
	/**
	 * Invokes the method with the given name {@code methodName} on the given
	 * {@code scope} using the givne {@code args}.
	 * 
	 * @param methodName the name of the method to invoke on the given {@code scope}
	 * @param scope the scope to invoke the method on
	 * @param args the arguments for the method invocation
	 * @return the result of the method invocation
	 */
	public static function invoke(methodName:String, scope, args:Array) {
		var m:Function = scope[methodName];
		if (m) {
			if (scope.__proto__[methodName] == scope.__proto__.__proto__[methodName]) {
				var s = scope.__proto__.__proto__;
				while (s[methodName] == s.__proto__[methodName]
						&& s.__proto__[methodName] == s.__proto__.__proto__[methodName]) {
					s = s.__proto__;
				}
				s.__as2lib__invoker = function() {
					delete s.__as2lib__invoker;
					return m.apply(super, args);
				};
				return scope.__as2lib__invoker();
			}
			return m.apply(scope, args);
		}
	}
	
	/**
	 * Constructs a new {@code MethodUtil} instance.
	 */
	private function MethodUtil() {
	}
	
}