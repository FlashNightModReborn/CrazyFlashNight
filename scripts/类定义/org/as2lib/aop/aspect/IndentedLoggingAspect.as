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

import org.as2lib.aop.advice.AbstractAdvice;
import org.as2lib.aop.Aspect;
import org.as2lib.aop.aspect.AbstractAspect;
import org.as2lib.aop.JoinPoint;
import org.as2lib.env.except.AbstractOperationException;

/**
 * @author Simon Wacker
 */
class org.as2lib.aop.aspect.IndentedLoggingAspect extends AbstractAspect implements Aspect {
	
	private var indentationLevel:Number = -1;
	
	private function IndentedLoggingAspect(Void) {
		addAdvice(AbstractAdvice.AROUND, getLoggingMethodsPointcut(), aroundLoggingMethodsAdvice);
		addAdvice(AbstractAdvice.BEFORE, getLoggedMethodsPointcut(), beforeLoggedMethodsAdvice);
		addAdvice(AbstractAdvice.AFTER, getLoggedMethodsPointcut(), afterLoggedMethodsAdvice);
	}
	
	private function aroundLoggingMethodsAdvice(joinPoint:JoinPoint, args:Array) {
		var spaces:String = "";
		for (var i:Number = 0; i < indentationLevel; i++) {
			spaces += "  ";
		}
		args[0] = spaces + String(args[0]);
		return joinPoint.proceed(args);
	}
	
	private function beforeLoggedMethodsAdvice(joinPoint:JoinPoint, args:Array):Void {
		indentationLevel++;
	}
	
	private function afterLoggedMethodsAdvice(joinPoint:JoinPoint):Void {
		indentationLevel--;
	}
	
	private function getLoggedMethodsPointcut(Void):String {
		throw new AbstractOperationException("This operation is marked as abstract and must be overridden by a concrete subclasses.", this, arguments);
		return null;
	}
	
	private function getLoggingMethodsPointcut(Void):String {
		throw new AbstractOperationException("This operation is marked as abstract and must be overridden by a concrete subclasses.", this, arguments);
		return null;
	}
	
}