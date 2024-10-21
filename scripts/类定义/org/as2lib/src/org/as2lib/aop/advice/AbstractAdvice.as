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
import org.as2lib.env.except.AbstractOperationException;
import org.as2lib.aop.Pointcut;
import org.as2lib.aop.Aspect;
import org.as2lib.aop.JoinPoint;
import org.as2lib.aop.AopConfig;
import org.as2lib.aop.joinpoint.AbstractJoinPoint;
import org.as2lib.env.reflect.MethodInfo;
import org.as2lib.env.reflect.PropertyInfo;

/**
 * {@code AbstractAdvice} implements methods commonly needed by {@link Adivce}
 * implementations.
 * 
 * @author Simon Wacker
 */
class org.as2lib.aop.advice.AbstractAdvice extends BasicClass {
	
	/** Signifies a before advice. */
	public static var BEFORE:Number = 0;
	
	/** Signifies an around advice. */
	public static var AROUND:Number = 1;
	
	/** Signifies an after advice. */
	public static var AFTER:Number = 2;
	
	/** Signifies an after returning advice. */
	public static var AFTER_RETURNING:Number = 3;
	
	/** Signifies an after throwing advice. */
	public static var AFTER_THROWING:Number = 4;
	
	/** The pointcut that is responsible for checking if a join point is captured by this advice. */
	private var pointcut:Pointcut;
	
	/** The aspect that contains this advice. */
	private var aspect:Aspect;
	
	/**
	 * Constructs a new {@code AbstractAdvice} instance.
	 *
	 * @param aspect (optional) the aspect that contains this advice
	 */
	private function AbstractAdvice(aspect:Aspect) {
		this.aspect = aspect;
	}
	
	/**
	 * Returns a proxy method that can be used instead of the original method of the
	 * {@code joinPoint}.
	 * 
	 * <p>The returned proxy invokes the abstract {@code executeJoinPoint} method of
	 * this advice passing an update of the given {@code joinPoint} with the appropriate
	 * logical this and the arguments used for the proxy invocation. Sub-classes are
	 * responsible for implementing this method in the correct way.
	 *
	 * @param joinPoint the join point that represents the original method
	 * @return the proxy method
	 */
	public function getProxy(joinPoint:JoinPoint):Function {
		var owner:AbstractAdvice = this;
		var result:Function = function() {
			// MTASC doesn't allow access to private "executeJoinPoint"
			return owner["executeJoinPoint"](joinPoint.update(this), arguments);
		};
		var method:Function;
		if (joinPoint.getType() == AbstractJoinPoint.METHOD
				|| joinPoint.getType() == AbstractJoinPoint.CONSTRUCTOR) {
			method = MethodInfo(joinPoint.getInfo()).getMethod();
		}
		if (joinPoint.getType() == AbstractJoinPoint.SET_PROPERTY) {
			method = PropertyInfo(joinPoint.getInfo()).getSetter().getMethod();
		}
		if (joinPoint.getType() == AbstractJoinPoint.GET_PROPERTY) {
			method = PropertyInfo(joinPoint.getInfo()).getGetter().getMethod();
		}
		if (method) {
			result.__proto__ = method.__proto__;
			result.prototype = method.prototype;
			result.__constructor__ = method.__constructor__;
			result.constructor = method.constructor;
			// just in case that any state is held in the original method, for classes this
			// may be static variables, methods or properties
			result.__resolve = function(name:String) {
				return method[name];
			};
			// guarantees that the class info for the original class this proxy overwrites
			// can still be found
			result.valueOf = function():Object {
				return method.valueOf();
			};
		}
		return result;
	}
	
	/**
	 * Executes the woven-in code and the join point.
	 * 
	 * @param joinPoint the reached join point
	 * @param args the arguments that were originally passed-to the join point
	 * @return the result to return to the invoker of the given {@code joinPoint}
	 * @throws AbstractOperationException always, because this is an abstract method
	 * that must be overridden by sub-classes
	 */
	private function executeJoinPoint(joinPoint:JoinPoint, args:Array) {
		throw new AbstractOperationException("This method is marked as abstract and must be overwritten.", this, arguments);
	}
	
	/**
	 * Sets the aspect that contains this advice.
	 *
	 * @param aspect the new aspect containing this advice
	 */
	private function setAspect(aspect:Aspect):Void {
		this.aspect = aspect;
	}
	
	/**
	 * Returns the aspect that contains this advice.
	 * 
	 * @return the aspect that contains this advice
	 */
	public function getAspect(Void):Aspect {
		return this.aspect;
	}
	
	/**
	 * @overload #setPointcutByPointcut
	 * @overload #setPointcutByString
	 */
	private function setPointcut() {
		var overload:Overload = new Overload(this);
		overload.addHandler([Pointcut], setPointcutByPointcut);
		overload.addHandler([String], setPointcutByString);
		return overload.forward(arguments);
	}
	
	/**
	 * Sets a new pointcut. The pointcut determines which join points are captured.
	 *
	 * @param pointcut the new pointcut to set
	 */
	private function setPointcutByPointcut(pointcut:Pointcut):Void {
		this.pointcut = pointcut;
	}
	
	/**
	 * Sets the new pointcut by the pointcut's string representation.
	 *
	 * @param pointcut the string representation of the pointcut
	 * @return the actual pointcut set that was created by the given {@code pointcut}
	 * string
	 */
	private function setPointcutByString(pointcut:String):Pointcut {
		var result:Pointcut = AopConfig.getPointcutFactory().getPointcut(pointcut);
		setPointcutByPointcut(result);
		return result;
	}
	
	/**
	 * Returns the set pointcut.
	 * 
	 * @return the set pointcut
	 */
	public function getPointcut(Void):Pointcut {
		return this.pointcut;
	}
	
	/**
	 * Checks whether this advice captures the given {@code joinPoint}. This check is
	 * done with the help of the set pointcut's {@code captures} method.
	 * 
	 * <p>If there is no pointcut set, {@code true} will be returned.
	 * 
	 * @param joinPoint the join point upon which to make the check
	 * @return {@code true} if the given {@code joinPoint} is captured else {@code false}
	 */
	public function captures(joinPoint:JoinPoint):Boolean {
		if (!this.pointcut) return true;
		return this.pointcut.captures(joinPoint);
	}
	
}