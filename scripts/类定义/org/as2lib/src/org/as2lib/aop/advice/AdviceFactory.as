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

import org.as2lib.core.BasicInterface;
import org.as2lib.app.exec.Call;
import org.as2lib.aop.Advice;
import org.as2lib.aop.Pointcut;

/**
 * {@code AdviceFactory} acts as provider for instances of type {@link Advice}.
 * 
 * @author Simon Wacker
 */
interface org.as2lib.aop.advice.AdviceFactory extends BasicInterface {
	
	/**
	 * @overload #getAdviceByStringAndCall
	 * @overload #getAdviceByPointcutAndCall
	 */
	public function getAdvice():Advice;
	
	/**
	 * Returns an advice configured for the given {@code pointcut} string and
	 * {@code callback}.
	 *
	 * @param pointcut the string representation of a pointcut used by the returned advice
	 * @param callback the callback that is executed if you invoke the {@code execute}
	 * method on the returned advice
	 * @return an advice that is configured with the given {@code pointcut} and
	 * {@code callback}
	 */
	public function getAdviceByStringAndCall(pointcut:String, callback:Call):Advice;
	
	/**
	 * Returns an advice configured for the given {@code pointcut} and {@code callback}.
	 *
	 * @param pointcut the pointcut used by the returned advice
	 * @param callback the callback that is executed if you invoke the {@code execute}
	 * method on the returned advice
	 * @return an advice that is configured with the given {@code pointcut} and
	 * {@code callback}
	 */
	public function getAdviceByPointcutAndCall(pointcut:Pointcut, callback:Call):Advice;
	
}