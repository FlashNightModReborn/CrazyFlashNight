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

import org.as2lib.io.conn.core.event.MethodInvocationReturnInfo;

/**
 * {@code MethodInvocationReturnListener} awaits a return value of a method invocation.
 * 
 * <p>This interface can either be instantiated directly or implemented by a class.
 * If you instantiate it directly you must overwrite the event method with an anonymous
 * function.
 *
 * <p>Note that overwriting the event method with a anonymous function is error-prone,
 * because the arguments' types and the return type are not type-checked. Instantiating
 * an interface directly is also not permitted in Flex.
 * 
 * <code>
 *   var listener:MethodInvocationReturnListener = new MethodInvocationReturnListener();
 *   listener.onReturn = function(returnInfo:MethodInvocationReturnInfo):Void) {
 *       trace("Invoked method successfully: " + returnInfo); 
 *   }
 * </code>
 * 
 * <p>Implementing the interface by a class is a much neater way. But sometimes it
 * adds unnecessary complexity.
 * 
 * <code>
 *   class MyListener implements MethodInvocationReturnListener {
 *       public function onReturn(returnInfo:MethodInvocationReturnInfo):Void {
 *           trace("Invoked method successfully: " + returnInfo); 
 *       }
 *   }
 * </code>
 *
 * @author Simon Wacker
 */
interface org.as2lib.io.conn.core.event.MethodInvocationReturnListener {
	
	/**
	 * Is executed when the return value of the method invocation arrives.
	 *
	 * <p>This indicates that the method was invoked successfully.
	 *
	 * @param returnInfo contains the return value and some other useful information about
	 * the invoked method
	 */
	public function onReturn(returnInfo:MethodInvocationReturnInfo):Void;
	
}