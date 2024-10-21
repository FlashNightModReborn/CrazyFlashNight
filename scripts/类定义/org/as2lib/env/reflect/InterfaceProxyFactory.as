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
import org.as2lib.env.reflect.ProxyFactory;
import org.as2lib.env.reflect.InvocationHandler;

/**
 * {@code InterfaceProxyFacotry} creates proxies for interfaces. It can only be
 * used in conjunction with interfaces, not classes.
 * 
 * <p>It offers a higher performance than the {@code TypeProxyFactory} which can
 * also be used with classes.
 *
 * @author Simon Wacker
 * @see org.as2lib.env.reflect.TypeProxyFactory
 */
class org.as2lib.env.reflect.InterfaceProxyFactory extends BasicClass implements ProxyFactory {
	
	/**
	 * Creates proxies for interfaces.
	 *
	 * <p>You can cast the returned proxy to the passed-in {@code interfaze}.
	 * 
	 * <p>{@code null} will be returned if the passed-in {@code interfaze} is {@code null}
	 * or {@code undefined}.
	 * 
	 * <p>The returned proxy catches method invocations by using {@code __resolve}.
	 *
	 * <p>Note that also methods that are not declared on the passed-in {@code interfaze}
	 * but that are invoked on the returned proxy, get forwarded to the passed-in
	 * {@code handler}.
	 * 
	 * @param interfaze the interface to create the proxy for
	 * @param handler the handler to invoke on method invocations on the returned proxy
	 * @return the created interface proxy
	 */
	public function createProxy(interfaze:Function, handler:InvocationHandler) {
		if (!interfaze) return null;
		var result:Object = new Object();
		result.__proto__ = interfaze.prototype;
		result.__constructor__ = interfaze;
		result.__resolve = function(methodName:String):Function {
			return (function() {
				return handler.invoke(this, methodName, arguments);
			});
		};
		return result;
	}
	
}