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
import org.as2lib.io.conn.core.event.MethodInvocationReturnInfo;
import org.as2lib.io.conn.core.event.MethodInvocationErrorInfo;

/**
 * {@code MethodInvocationCallback} awaits the response of a method invocation.
 * 
 * <p>There are two types of responses.
 * <dl>
 *   <dt>Return Response:</dt>
 *   <dd>
 *     Indicates that the method has been invoked successfully without throwing an
 *     exception.
 *   </dd>
 *   <dt>Error Response:</dt>
 *   <dd>
 *     Indicates that an error occured when trying to invoke the method. This error
 *     can for example be an exception the method threw or the unavailability of the
 *     method to invoke. For further details take a look at the '*_Error' constants
 *     declared by {@link MethodInvocationErrorInfo}.
 *   </dd>
 * </dl>
 *
 * <p>Depending on the client and service used, that are responsible for propagating
 * the methods on this callback, there may be other circumstances on which a specific
 * callback method is invoked.
 * 
 * <p>This interface can either be instantiated directly or implemented by a class.
 * If you instantiate it directly you must overwrite the callback methods you wanna
 * be informed of with anonymous functions.
 * 
 * <p>Note that implementing this interface is much cleaner and less error-prone. It
 * is thus recommended to implement this interface whenever possible, instead of
 * overwriting the methods with anonymous functions. Note also that the direct
 * instantiation of interfaces is not permitted in Flex.
 *
 * <code>
 *   var callback:MethodInvocationCallback = new MethodInvocationCallback();
 *   callback.onReturn = function(returnInfo:MethodInvocationReturnInfo):Void) {
 *       trace("Invoked method successfully: " + returnInfo); 
 *   }
 *   callback.onError = function(errorInfo:MethodInvocationErrorInfo):Void {
 *       trace("Error occured when trying to invoke the method: " + errorInfo);
 *   }
 * </code>
 *
 * <p>Implementing the interface by a class is a much neater way. But sometimes it
 * adds unnecessary complexity.
 * 
 * <code>
 *   class MyCallback implements MethodInvocationCallback {
 *       public function onReturn(returnInfo:MethodInvocationReturnInfo):Void {
 *           trace("Invoked method successfully: " + returnInfo); 
 *       }
 *       public function onError(errorInfo:MethodInvocationErrorInfo):Void {
 *           trace("Error occured when trying to invoke the method: " + errorInfo);
 *       }
 *   }
 * </code>
 *
 * @author Simon Wacker
 */
interface org.as2lib.io.conn.core.event.MethodInvocationCallback extends BasicInterface {
	
	/**
	 * Is executed when the return value of the method invocation arrives.
	 *
	 * <p>This indicates that the method was invoked successfully.
	 *
	 * @param returnInfo contains the return value and some other useful information about
	 * the invoked method
	 */
	public function onReturn(returnInfo:MethodInvocationReturnInfo):Void;
	
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