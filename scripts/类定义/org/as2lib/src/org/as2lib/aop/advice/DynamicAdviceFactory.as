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
 * {@code DynamicAdviceFactory} acts as a provider of advices based on specific types.
 * 
 * @author Simon Wacker
 */
interface org.as2lib.aop.advice.DynamicAdviceFactory extends BasicInterface {
	
	/**
	 * @overload #getAdviceByTypeAndStringAndCall
	 * @overload #getAdviceByTypeAndPointcutAndCall
	 */
	public function getAdvice():Advice;
	
	/**
	 * Returns the advice corresponding to the given {@code type}. The returned advice
	 * uses the passed-in {@code pointcut} and {@code callback}.
	 * 
	 * <p>The {@code callback} is invoked if the {@code execute} method of the returned
	 * advice is executed.
	 * 
	 * <p>Commonly supported types are defined as constants in the
	 * {@link AbstractAdvice} class.
	 * 
	 * @param type the type of the advice to return
	 * @param pointcut the string representation of a pointcut used by the returned advice
	 * @param callback the callback that is executed if you invoke the {@code execute}
	 * method on the returned advice
	 * @return the advice corresponding to the type and configured with the given
	 * {@code pointcut} and {@code callback}
	 */
	public function getAdviceByTypeAndStringAndCall(type:Number, pointcut:String, callback:Call):Advice;
	
	/**
	 * Returns the advice corresponding to the given {@code type}. The returned advice
	 * uses the passed-in {@code pointcut} and {@code callback}.
	 * 
	 * <p>The {@code callback} is invoked if the {@code execute} method of the returned
	 * advice is executed.
	 * 
	 * <p>Commonly supported types are defined as constants in the
	 * {@link AbstractAdvice} class.
	 *
	 * @param type the type of the advice to return
	 * @param pointcut the pointcut used by the returned advice
	 * @param callback the callback that is executed if you invoke the {@code execute}
	 * method on the returned advice
	 * @return the advice corresponding to the type and configured with the given
	 * {@code pointcut} and {@code callback}
	 */
	public function getAdviceByTypeAndPointcutAndCall(type:Number, pointcut:Pointcut, callback:Call):Advice;
	
}