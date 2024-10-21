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

import org.as2lib.io.conn.core.event.MethodInvocationErrorInfo;

/**
 * {@code MethodInvocationErrorListener} awaits an error response of a method
 * invocation.
 * 
 * <p>When and why the event method is invoked depends on the used client.
 *
 * <p>This interface can either be instantiated directly or implemented by a class.
 * If you instantiate it directly you must overwrite the event methods with
 * anonymous function.
 *
 * <p>Note that overwriting the event method with a anonymous function is error-prone,
 * because the arguments' types and the return type are not type-checked. Instantiating
 * an interface directly is also not permitted in Flex.
 * 
 * <code>
 *   var listener:MethodInvocationErrorListener = new MethodInvocationErrorListener();
 *   listener.onError = function(errorInfo:MethodInvocationErrorInfo):Void {
 *       trace("Error occured when trying to invoke the method: " + errorInfo);
 *   }
 * </code>
 * 
 * <p>Implementing the interface by a class is a much neater way, but sometimes adds
 * unnecessary complexity.
 *
 * <code>
 *   class MyListener implements MethodInvocationErrorListener {
 *       public function onError(errorInfo:MethodInvocationErrorInfo):Void {
 *           trace("Error occured when trying to invoke the method: " + errorInfo);
 *       }
 *   }
 * </code>
 *
 * @author Simon Wacker
 */
interface org.as2lib.io.conn.core.event.MethodInvocationErrorListener {
	
	/**
	 * Is executed when a method invocation fails.
	 *
	 * <p>Known issues are:
	 * <ul>
	 *   <li>The method threw an exception.</li>
	 *   <li>The method does not exist on the remote service.</li>
	 * </ul>
	 *
	 * <p>Remember that not all clients support this functionalities.
	 *
	 * @param errorInfo contains information about the error and some useful information
	 * about the called method
	 */
	public function onError(errorInfo:MethodInvocationErrorInfo):Void;
	
}