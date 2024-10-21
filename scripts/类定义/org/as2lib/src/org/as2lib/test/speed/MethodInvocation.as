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
import org.as2lib.env.reflect.MethodInfo;
import org.as2lib.env.reflect.ConstructorInfo;
import org.as2lib.env.reflect.ClassInfo;
import org.as2lib.test.speed.TestResult;
import org.as2lib.test.speed.AbstractTestResult;

/**
 * {@code MethodInvocation} reflects a profiled method invocation.
 * 
 * @author Simon Wacker */
class org.as2lib.test.speed.MethodInvocation extends AbstractTestResult implements TestResult {
	
	/** Designates an unknown type in the type signature. */
	public static var UNKNOWN:String = "[unknown]";
	
	/** Designates type {@code Void} in the type signature. */
	public static var VOID:String = "Void";
	
	/** Invoked method. */
	private var method:MethodInfo;
	
	/** Caller of this method invocation. */
	private var caller:MethodInvocation;
	
	/** Time needed for this method invocation. */
	private var time:Number;
	
	/** Arguments used for this method invocation. */
	private var args:Array;
	
	/** Return value of this method invocation. */
	private var returnValue;
	
	/** Exception thrown during this method invocation. */
	private var exception;
	
	/** The previous method invocation. */
	private var previousMethodInvocation:MethodInvocation;
	
	/**
	 * Constructs a new {@code MethodInvocation} instance.
	 * 
	 * @param method the invoked method
	 * @throws IllegalArgumentException if {@code method} is {@code null} or
	 * {@code undefined}	 */
	public function MethodInvocation(method:MethodInfo) {
		if (!method) {
			throw new IllegalArgumentException("Argument 'method' [" + method + "] must not be 'null' nor 'undefined'.", this, arguments);
		}
		this.method = method;
	}
	
	/**
	 * Returns the invoked method.
	 * 
	 * @return the invoked method
	 */
	public function getMethod(Void):MethodInfo {
		return this.method;
	}
	
	/**
	 * Returns the name of this method invocation. This is the method's name plus the
	 * signature of this method invocation.
	 * 
	 * @return the name of this method invocation
	 * @see #getMethodName
	 * @see #getMethodSignature	 */
	public function getName(Void):String {
		return (getMethodName() + getSignature());
	}
	
	/**
	 * Returns the full name of the invoked method.
	 * 
	 * @return the full name of the invoked method	 */
	public function getMethodName(Void):String {
		return this.method.getFullName();
	}
	
	/**
	 * Returns the signature of this method invocation.
	 * 
	 * <p>If any information needed to generate the signature is not defined,
	 * {@link #UNKNOWN} is used as placeholder.
	 * 
	 * @return this method invocation's signature	 */
	public function getSignature(Void):String {
		var result:String = "(";
		if (this.args.length > 0) {
			for (var i:Number = 0; i < this.args.length; i++) {
				if (i != 0) {
					result += ", ";
				}
				result += getFullTypeName(args[i]);
			}
		} else {
			result += "Void";
		}
		if (this.method instanceof ConstructorInfo) {
			result += ")";
		} else {
			result += "):";
			if (this.returnValue === undefined) {
				result += VOID;
			} else {
				result += getFullTypeName(this.returnValue);
			}
		}
		if (!wasSuccessful()) {
			result += " throws ";
			result += getFullTypeName(this.exception);
		}
		return result;
	}
	
	/**
	 * Returns the fully qualified type name for the passed-in {@code instance}.
	 * 
	 * @param instance the instance to return the type name for
	 * @return the fully qualified type name for the passed-in {@code instance}.	 */
	private function getFullTypeName(instance):String {
		if (instance == null) return UNKNOWN;
		var typeName:String = ClassInfo.forInstance(instance).getFullName();
		if (typeName == null) {
			return UNKNOWN;
		} else {
			return typeName;
		}
	}
	
	/**
	 * Returns the time in milliseconds needed for this method invocation.
	 * 
	 * @return the time in milliseconds needed for this method invocation
	 */
	public function getTime(Void):Number {
		return this.time;
	}
	
	/**
	 * Sets the time in milliseconds needed for this method invocation.
	 * 
	 * @param time the time in milliseconds needed for this method invocation
	 */
	public function setTime(time:Number):Void {
		this.time = time;
	}
	
	/**
	 * Returns the arguments used for this method invocation.
	 * 
	 * @return the arguments used for this method invocation
	 */
	public function getArguments(Void):Array {
		return this.args;
	}
	
	/**
	 * Sets the arguments used for this method invocation.
	 * 
	 * @param args the arguments used for this method invocation
	 */
	public function setArguments(args:Array):Void {
		this.args = args;
	}
	
	/**
	 * Returns this method invocation's return value.
	 * 
	 * @return this method invocation's return value
	 */
	public function getReturnValue(Void) {
		return this.returnValue;
	}
	
	/**
	 * Sets the return value of this method invocation.
	 * 
	 * @param returnValue the return value of this method invocation
	 */
	public function setReturnValue(returnValue):Void {
		this.exception = undefined;
		this.returnValue = returnValue;
	}
	
	/**
	 * Returns the exception thrown during this method invocation.
	 * 
	 * @return the exception thrown during this method invocation
	 */
	public function getException(Void) {
		return this.exception;
	}
	
	/**
	 * Sets the exception thrown during this method invocation.
	 * 
	 * @param exception the exception thrown during this method invocation
	 */
	public function setException(exception):Void {
		this.returnValue = undefined;
		this.exception = exception;
	}
	
	/**
	 * Returns whether this method invocation was successful. Successful means that it
	 * returned a proper return value and did not throw an exception.
	 * 
	 * @return {@code true} if this method invocation was successful else {@code false}
	 */
	public function wasSuccessful(Void):Boolean {
		return (this.exception === undefined);
	}
	
	/**
	 * Returns the method invocation that called the method that resulted in this
	 * method invocation.
	 * 
	 * @return the method invocation that called the method that resulted in this
	 * method.	 */
	public function getCaller(Void):MethodInvocation {
		return this.caller;
	}
	
	/**
	 * Sets the method invocation that called the method that resulted in this method
	 * invocation.
	 * 
	 * @param caller the method invocation that called the method that resulted in this
	 * method invocation.	 */
	public function setCaller(caller:MethodInvocation):Void {
		this.caller = caller;
	}
	
	/**
	 * Returns the previous method invocation.
	 * 
	 * @return the previous method invocation	 */
	public function getPreviousMethodInvocation(Void):MethodInvocation {
		return this.previousMethodInvocation;
	}
	
	/**
	 * Sets the previous method invocation.
	 * 
	 * @param previousMethodInvocation the previous method invocation	 */
	public function setPreviousMethodInvocation(previousMethodInvocation:MethodInvocation):Void {
		this.previousMethodInvocation = previousMethodInvocation;
	}
	
	/**
	 * Checks whether this method invocation was invoked before the passed-in
	 * {@code methodInvocation}.
	 * 
	 * @param methodInvocation the method invocation to make the check upon
	 * @return {@code true} if this method invocation was invoked previously to the
	 * passed-in {@code methodInvocation} else {@code false}	 */
	public function isPreviousMethodInvocation(methodInvocation:MethodInvocation):Boolean {
		if (methodInvocation == this) return false;
		var previousMethodInvocation:MethodInvocation = methodInvocation.getPreviousMethodInvocation();
		while (previousMethodInvocation) {
			if (previousMethodInvocation == this) return true;
			previousMethodInvocation = previousMethodInvocation.getPreviousMethodInvocation();
		}
		return false;
	}
	
	/**
	 * Returns the string representation of this method invocation.
	 * 
	 * @param rootTestResult test result that holds the total values needed for
	 * percentage calculations
	 * @return the string representation of this method invocation
	 */
	public function toString():String {
		var rootTestResult:TestResult = arguments[0];
		if (!rootTestResult) rootTestResult = getThis();
		var result:String = getTimePercentage(rootTestResult.getTime()) + "%";
		result += ", " + getThis().getTime() + " ms";
		result += " - " + getName();
		return result;
	}
	
}