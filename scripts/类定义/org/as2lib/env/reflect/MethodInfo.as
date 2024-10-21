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
import org.as2lib.util.Stringifier;
import org.as2lib.env.reflect.TypeInfo;
import org.as2lib.env.reflect.TypeMemberInfo;
import org.as2lib.env.reflect.stringifier.MethodInfoStringifier;

/**
 * {@code MethodInfo} represents a method.
 * 
 * <p>{@code MethodInfo} instances for specific methods can be obtained using the
 * {@link ClassInfo#getMethods} or {@link ClassInfo#getMethod} methods. That means
 * you first have to get a class info for the class that declares or inherits the
 * method. You can therefor use the {@link ClassInfo#forObject}, {@link ClassInfo#forClass},
 * {@link ClassInfo#forInstance} and {@link ClassInfo#forName} methods.
 * 
 * <p>When you have obtained the method info you can use it to get information about
 * the method.
 *
 * <code>
 *   trace("Method name: " + methodInfo.getName());
 *   trace("Declaring type: " + methodInfo.getDeclaringType().getFullName());
 *   trace("Is Static?: " + methodInfo.isStatic());
 * </code>
 *
 * @author Simon Wacker
 */
class org.as2lib.env.reflect.MethodInfo extends BasicClass implements TypeMemberInfo {
	
	/** The method info stringifier. */
	private static var stringifier:Stringifier;
	
	/**
	 * The invoker method used to invoke this method. This invoker is invoked on
	 * different scopes, never on this scope.
	 * 
	 * <p>This invoker removes itself, before executing the method, from the object it
	 * was assigned to. It expects itself to have the name {@code "__as2lib__invoker"}.
	 * 
	 * @param object the object that holds this invoker method
	 * @param method the method to invoke on the {@code super} object
	 * @param args the arguments to use for the invocation
	 * @return the result of the invocation of {@code method} with {@code args} on the
	 * {@code super} scope
	 */
	private var INVOKER:Function = function(object, method:Function, args:Array) {
		// deletes the variable '__as2lib__invoker'; deletes the reference to this function
		delete object.__as2lib__invoker;
		// ('super' is not accessible from this scope, at least that's the compiler error) <-- this was at the time INVOKER was static
		// eval("su" + "per") is not supported by MTASC. INVOKER must thus be an instance variable because normal
		// 'super' usage is not allowed for per class / static functions
		return method.apply(super, args);
	};
	
	/**
	 * Returns the stringifier used to stringify method infos.
	 *
	 * <p>If no custom stringifier has been set via the {@link #setStringifier} method,
	 * a instance of the default {@code MethodInfoStringifier} class is returned.
	 * 
	 * @return the stringifier that stringifies method infos
	 */
	public static function getStringifier(Void):Stringifier {
		if (!stringifier) stringifier = new MethodInfoStringifier();
		return stringifier;
	}
	
	/**
	 * Sets the stringifier used to stringify method infos.
	 *
	 * <p>If {@code methodInfoStringifier} is {@code null} or {@code undefined}
	 * {@link #getStringifier} will return the default stringifier.
	 * 
	 * @param methodInfoStringifier the stringifier that stringifies method infos
	 */
	public static function setStringifier(methodInfoStringifier:MethodInfoStringifier):Void {
		stringifier = methodInfoStringifier;
	}
	
	/** The name of this method. */
	private var name:String;
	
	/** The concrete method. */
	private var method:Function;
	
	/** The type that declares this method. */
	private var declaringType:TypeInfo;
	
	/** A flag representing whether this method is static or not. */
	private var staticFlag:Boolean;
	
	/**
	 * Constructs a new {@code MethodInfo} instance.
	 *
	 * <p>All arguments are allowed to be {@code null}. But keep in mind that not all
	 * methods will function properly if one is.
	 * 
	 * <p>If {@code method} is not specified, it will be resolved at run-time everytime
	 * it is needed. This means that the concrete method will always be up-to-date even
	 * if you have overwritten it.
	 * 
	 * @param name the name of the method
	 * @param declaringType the declaring type of the method
	 * @param staticFlag determines whether the method is static
	 * @param method (optional) the concrete method
	 */
	public function MethodInfo(name:String,
							   declaringType:TypeInfo,
							   staticFlag:Boolean,
							   method:Function) {
		this.name = name;
		this.declaringType = declaringType;
		this.staticFlag = staticFlag;
		this.method = method;
	}
	
	/**
	 * Returns the name of this method.
	 *
	 * @return the name of this method
	 */
	public function getName(Void):String {
		return name;
	}
	
	/**
	 * Returns the full name of this method.
	 * 
	 * <p>The full name is the fully qualified name of the declaring type plus the name
	 * of this method.
	 *
	 * @return the full name of this method
	 */
	public function getFullName(Void):String {
		if (declaringType.getFullName()) {
			return declaringType.getFullName() + "." + name;
		}
		return name;
	}
	
	/**
	 * Returns the concrete method this instance represents.
	 *
	 * <p>If the concrete method was not specified on construction it will be resolved
	 * on run-time by this method everytime asked for. The returned method is thus
	 * always the current method on the declaring type.
	 *
	 * @return the concrete method
	 */
	public function getMethod(Void):Function {
		if (method !== undefined) {
			return method;
		}
		var t:Function = declaringType.getType();
		if (staticFlag) {
			if (t[name] != t.__proto__[name]) {
				return t[name];
			}
		}
		var p:Object = t.prototype;
		if (p[name] != p.__proto__[name]) {
			return p[name];
		}
		return null;
	}
	
	/**
	 * Returns the type that declares this method.
	 *
	 * @return the type that declares this method
	 */
	public function getDeclaringType(Void):TypeInfo {
		return declaringType;
	}
	
	/**
	 * Invokes this method on the passed-in {@code scope} passing the given {@code args}.
	 * 
	 * <p>The object referenced by {@code this} in this method is the object this method
	 * is invoked on, its / the passed-in {@code scope}.
	 * 
	 * @param scope the {@code this}-scope for the method invocation
	 * @param args the arguments to pass-to the method on invocation
	 * @return the return value of the method invocation
	 */
	public function invoke(scope, args:Array) {
		// there is no super bug with apply and static methods because 'super' is not allowed in static methods
		if (!staticFlag) {
			var t:Function = declaringType.getType();
			// super bug can only be fixed if scope is an instance of the declaring type
			// otherwise everything is messed up anyway
			if (scope instanceof t) {
				var p:Object = t.prototype;
				// if scope is a direct instance of the declaring type super works as expected
				if (scope.__proto__ != p) {
					var s = scope.__proto__;
					while (s.__proto__ != p) {
						s = s.__proto__;
					}
					s.__as2lib__invoker = INVOKER;
					return scope.__as2lib__invoker(s, getMethod(), args);
				}
			}
		}
		return getMethod().apply(scope, args);
	}
	
	/**
	 * Returns whether this method is static or not.
	 * 
	 * <p>Static methods are methods per type.
	 *
	 * <p>Non-Static methods are methods per instance.
	 *
	 * @return {@code true} if this method is static else {@code false}
	 */
	public function isStatic(Void):Boolean {
		return staticFlag;
	}
	
	/**
	 * Returns a method info that reflects the current state of this method info.
	 * 
	 * @return a snapshot of this method info
	 */
	public function snapshot(Void):MethodInfo {
		return new MethodInfo(name, declaringType, staticFlag, getMethod());
	}
	
	/**
	 * Returns the string representation of this method.
	 *
	 * <p>The string representation is obtained via the stringifier returned by the
	 * static {@link #getStringifier} method.
	 * 
	 * @return the string representation of this method
	 */
	public function toString():String {
		return getStringifier().execute(this);
	}
	
}