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

import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.env.overload.Overload;
import org.as2lib.env.reflect.MethodInfo;
import org.as2lib.env.reflect.ConstructorInfo;
import org.as2lib.env.reflect.ClassInfo;
import org.as2lib.test.speed.AbstractTest;
import org.as2lib.test.speed.Test;
import org.as2lib.test.speed.SimpleTestSuiteResult;
import org.as2lib.test.speed.MethodInvocation;

/**
 * {@code MethodTestCase} is a test case for a method. It tests a method and profiles
 * its method invocations.
 *
 * @author Simon Wacker
 * @author Martin Heidegger
 */
class org.as2lib.test.speed.MethodTestCase extends AbstractTest implements Test {
	
	/** Makes the static variables of the super-class accessible through this class. */
	private static var __proto__:Function = AbstractTest;
	
	/** The previous method invocation. */
	private static var p:MethodInvocation;
	
	/** The profiled method. */
	private var method:MethodInfo;
	
	/** Scope of profiled method. */
	private var s;
	
	/** Name of profiled method. */
	private var n:String;
	
	/**
	 * @overload #MethodTestCaseByVoid
	 * @overload #MethodTestCaseByMethod
	 * @overload #MethodTestCaseByObjectAndMethod
	 * @overload #MethodTestCaseByObjectAndName	 */
	public function MethodTestCase() {
		var o:Overload = new Overload(this);
		o.addHandler([], MethodTestCaseByVoid);
		o.addHandler([MethodInfo], MethodTestCaseByMethod);
		o.addHandler([MethodInfo, Object, String], MethodTestCaseByMethod);
		o.addHandler([Object, Function], MethodTestCaseByObjectAndMethod);
		o.addHandler([Object, String], MethodTestCaseByObjectAndName);
		o.forward(arguments);
	}
	
	/**
	 * Constructs a new {@code MethodTestCase} instance for the default method. This is
	 * the method named {@code "doRun"} that must be declared on this instance.	 */
	private function MethodTestCaseByVoid(Void):Void {
		MethodTestCaseByObjectAndName(this, "doRun");
	}
	
	/**
	 * Constructs a new {@code MethodTestCase} instance by method.
	 * 
	 * <p>If you want to profile a method, referenced from a different scope and with a
	 * different name you can specify thse with the last two arguments. Note that if
	 * specified the method declared on the class will not be profiled but its
	 * reference.
	 * 
	 * @param method the method to profile
	 * @param referenceScope (optional) the scope of the method reference to profile
	 * @param referenceName (optional) the name of the method reference to profile
	 * @throws IllegalArgumentException if the passed-in {@code method} is {@code null}
	 * or {@code undefined}	 */
	private function MethodTestCaseByMethod(method:MethodInfo, referenceScope, referenceName:String):Void {
		if (!method) {
			throw new IllegalArgumentException("Argument 'method' [" + method + "] must not be 'null' nor 'undefined' or this instance must declare a method named 'doRun'.", this, arguments);
		}
		this.method = method.snapshot();
		if (referenceScope) {
			this.s = referenceScope;
		} else {
			if (method instanceof ConstructorInfo) {
				this.s = method.getDeclaringType().getPackage().getPackage();
			} else if (method.isStatic()) {
				this.s = method.getDeclaringType().getType();
			} else {
				this.s = method.getDeclaringType().getType().prototype;
			}
		}
		if (referenceName) {
			this.n = referenceName;
		} else {
			if (method instanceof ConstructorInfo) {
				this.n = method.getDeclaringType().getName();
			} else {
				this.n = method.getName();
			}
		}
		setResult(new SimpleTestSuiteResult(method.getFullName()));
	}
	
	/**
	 * Constructs a new {@code MethodTestCase} instance by object and method.
	 * 
	 * @param object the object that declares the method to profile
	 * @param method the method to profile
	 * @throws IllegalArgumentException if {@code object} or {@code method} is
	 * {@code null} or {@code undefined}	 */
	private function MethodTestCaseByObjectAndMethod(object, method:Function):Void {
		if (object == null || !method) {
			throw new IllegalArgumentException("Neither argument 'object' [" + object + "] nor 'method' [" + method + "] is allowed to be 'null' or 'undefined'.");
		}
		var c:ClassInfo = ClassInfo.forObject(object);
		MethodTestCaseByMethod(c.getMethodByMethod(method));	
	}
	
	/**
	 * Constructs a new {@code MethodTestCase} instance by object and method name.
	 * 
	 * @param object the object that declares the method to profile
	 * @param methodName the name of the method to profile
	 * @throws IllegalArgumentException if a method with the given {@code methodName}
	 * does not exist on the given {@code object} or is not of type {@code "function"}	 */
	private function MethodTestCaseByObjectAndName(object, methodName:String):Void {
		if (!object[methodName]) {
			throw new IllegalArgumentException("Method [" + object[methodName] + "] with name '" + methodName + "' on object [" + object + "] must not be 'null' nor 'undefined'.");
		}
		if (typeof(object[methodName]) != "function") {
			throw new IllegalArgumentException("Method [" + object[methodName] + "] with name '" + methodName + "' on object [" + object + "] must be of type 'function'.");
		}
		var c:ClassInfo = ClassInfo.forObject(object);
		if (c.hasMethod(methodName)) {
			MethodTestCaseByMethod(c.getMethodByName(methodName));
		} else {
			var m:MethodInfo = new MethodInfo(methodName, c, false, object[methodName]);
			MethodTestCaseByMethod(m, object, methodName);
		}
	}
	
	/**
	 * Returns the profiled method.
	 * 
	 * @return the profiled method	 */
	public function getMethod(Void):MethodInfo {
		return this.method;
	}
	
	/**
	 * Runs this performance test case.
	 */
	public function run(Void):Void {
		this.s[this.n] = createClosure();
	}
	
	/**
	 * Creates a closure, that is a wrapper method, for the method to profile.
	 * 
	 * @return the created closure	 */
	private function createClosure(Void):Function {
		var t:MethodTestCase = this;
		var mi:MethodInfo = this.method;
		var m:Function = this.method.getMethod();
		var closure:Function = function() {
			var i:MethodInvocation = t["c"]();
			i.setPreviousMethodInvocation(MethodTestCase["p"]);
			i.setArguments(arguments);
			i.setCaller(arguments.caller.__as2lib__i);
			m.__as2lib__i = i;
			var b:Number = getTimer();
			try {
				var r = mi.invoke(this, arguments);
				i.setTime(getTimer() - b);
				i.setReturnValue(r);
				return r;
			} catch (e) {
				i.setTime(getTimer() - b);
				i.setException(e);
				throw e;
			} finally {
				t["a"](i);
				MethodTestCase["p"] = i;
				delete m.__as2lib__i;
			}
		};
		closure.valueOf = function():Object {
			return m;
		};
		// sets class specific variables needed for closures of classes
		closure.__proto__ = m.__proto__;
		closure.prototype = m.prototype;
		closure.__constructor__ = m.__constructor__;
		closure.constructor = m.constructor;
		return closure;
	}
	
	/**
	 * Creates a new method invocation configured for this test case.
	 * 
	 * @return a new configured method invocation	 */
	private function c(Void):MethodInvocation {
		return new MethodInvocation(this.method);
	}
	
	/**
	 * Adds a new method invocation profile result.
	 * 
	 * @param m the new method invocation profile result	 */
	private function a(m:MethodInvocation):Void {
		this.result.addTestResult(m);
	}
	
}