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
import org.as2lib.io.conn.core.event.MethodInvocationCallback;

/**
 * {@code AbstractClientServiceProxy} offers default implementations of some methods
 * needed when implemnting the {@link ClientServiceProxy} interface.
 * 
 * @author Simon Wacker
 */
class org.as2lib.io.conn.core.client.AbstractClientServiceProxy extends BasicClass {
	
	/**
	 * Private constructor.
	 */
	private function AbstractClientServiceProxy(Void) {
	}
	
	/**
	 * @overload #invokeByName
	 * @overload #invokeByNameAndArguments
	 * @overload #invokeByNameAndCallback
	 * @overload invokeByNameAndArgumentsAndCallback
	 * @see ClientServiceProxy#invoke
	 */
	public function invoke():MethodInvocationCallback {
		var o:Overload = new Overload(this);
		o.addHandler([String], invokeByName);
		o.addHandler([String, Array], invokeByNameAndArguments);
		o.addHandler([String, MethodInvocationCallback], invokeByNameAndCallback);
		o.addHandler([String, Array, MethodInvocationCallback], this["invokeByNameAndArgumentsAndCallback"]);
		return o.forward(arguments);
	}
	
	/**
	 * Invokes the method with passed-in {@code methodName} on the service.
	 * 
	 * <p>The invocation is done by forwardning to the {@code #invokeByNameAndArgumentsAndCallback}
	 * method passing an empty arguments array.
	 *
	 * @param methodName the name of the method to invoke
	 * @return a callback that can be used to get informed of the response
	 * @see ClientServiceProxy#invokeByName
	 */
	public function invokeByName(methodName:String):MethodInvocationCallback {
		return this["invokeByNameAndArgumentsAndCallback"](methodName, [], null);
	}
	
	/**
	 * Invokes the method with passed-in {@code methodName} and {@code args} on the
	 * service.
	 * 
	 * <p>The response of the method invocation is delegated to the appropriate method
	 * on the returned callback. This is either the {@code onReturn} method when no
	 * error occured. Or the {@code onError} method in case something went wrong.
	 *
	 * <p>The invocation is done by forwardning to the {@code #invokeByNameAndArgumentsAndCallback}
	 * method passing an empty arguments array.
	 *
	 * @param methodName the name of the method to invoke on the service
	 * @param args the arguments that are passed to the method as parameters
	 * @return the callback that handles the response
	 * @see ClientServiceProxy#invokeByNameAndArguments
	 */
	public function invokeByNameAndArguments(methodName:String, args:Array):MethodInvocationCallback {
		return this["invokeByNameAndArgumentsAndCallback"](methodName, args, null);
	}
	
	/**
	 * Invokes the the method with passed-in {@code method} on the service.
	 *
	 * <p>When the response arrives the appropriate callback method is invoked.
	 * 
	 * <p>If the passed-in {@code callback} is not {@code null}, the returned callback
	 * is the same instance.
	 *
	 * <p>The invocation is done by forwardning to the {@code #invokeByNameAndArgumentsAndCallback}
	 * method passing an empty arguments array.
	 * 
	 * @param methodName the name of the method to invoke
	 * @param callback the callback that receives the return value or errors
	 * @return a callback that can be used to get informed of the response
	 * @see ClientServiceProxy#invokeByNameAndCallback
	 */
	public function invokeByNameAndCallback(methodName:String, callback:MethodInvocationCallback):MethodInvocationCallback {
		return this["invokeByNameAndArgumentsAndCallback"](methodName, [], callback);
	}
	
}