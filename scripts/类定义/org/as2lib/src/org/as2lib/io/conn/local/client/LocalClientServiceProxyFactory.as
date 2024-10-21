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

import org.as2lib.env.reflect.ProxyFactory;
import org.as2lib.env.reflect.InterfaceProxyFactory;
import org.as2lib.env.reflect.InvocationHandler;
import org.as2lib.io.conn.core.client.ClientServiceProxy;
import org.as2lib.io.conn.core.client.ClientServiceProxyFactory;
import org.as2lib.io.conn.core.client.AbstractClientServiceProxyFactory;
import org.as2lib.io.conn.local.client.SimpleClientServiceProxyFactory;
import org.as2lib.io.conn.core.event.MethodInvocationCallback;

/**
 * {@code LocalClientServiceProxyFactory} acts as central provider of client service
 * proxies.
 * 
 * <p>This provision is in the simplest case just the returning of a new client 
 * service proxy.
 * <code>
 *   var clientFactory:LocalClientServiceProxyFactory = new LocalClientServiceProxyFactory();
 *   var client:ClientServiceProxy = clientFactory.getClientServiceProxy("local.as2lib.org/myService");
 * </code>
 * 
 * <p>In a more complex case this means creating a client service proxy for a specific
 * type, mostly an interface, that is the same type of the 'remote' service.
 * <code>
 *   var clientFactory:LocalClientServiceProxyFactory = new LocalClientServiceProxyFactory();
 *   var client:MyType = clientFactory.getClientServiceProxy("local.as2lib.org/myService", MyType);
 *   client.myMethod("myArg1", "myArg2");
 * </code>
 * 
 * <p>There is sadly one flaw with the last type of usage. That is that the method
 * cannot response directly due to the asynchronity of the call. To get a response
 * you therefore have to pass a third argument of type {@code MethodInvocationCallback}.
 * <code>
 *   var clientFactory:LocalClientServiceProxyFactory = new LocalClientServiceProxyFactory();
 *   var client:MyType = clientFactory.getClientServiceProxy("local.as2lib.org/myService", MyType);
 *   var callback:MethodInvocationCallback = new MethodInvocationCallback();
 *   client.myMethod("myArg1", "myArg2", callback);
 *   callback.onReturn = function(returnInfo:MethodInvocationReturnInfo):Void {
 *       trace("myMethod - return value: " + returnInfo.getReturnValue());
 *   }
 *   callback.onError = function(errorInfo:MethodInvocationErrorInfo):Void {
 *       trace("myMethod - error: " + errorInfo.getException());
 *   }
 * </code>
 *
 * @author Simon Wacker
 * @author Christoph Atteneder
 * @see org.as2lib.io.conn.core.event.MethodInvocationCallback
 */
class org.as2lib.io.conn.local.client.LocalClientServiceProxyFactory extends AbstractClientServiceProxyFactory implements ClientServiceProxyFactory {
	
	/** The currently used proxy factory to create proxies for a specific type. */
	private var typeProxyFactory:ProxyFactory;
	
	/** Stores the client service proxy factory used to get client service proxy instances. */
	private var clientServiceProxyFactory:ClientServiceProxyFactory;
	
	/**
	 * Constructs a new {@code LocalClientServiceProxyFactory} instance.
	 */
	public function LocalClientServiceProxyFactory(Void) {
	}
	
	/**
	 * Returns the currently used type proxy factory that is used to create proxies for
	 * a specific type.
	 * 
	 * <p>That is either the proxy factory set via {@link #setTypeProxyFactory}
	 * or the default one, which is an instance of type {@link InterfaceProxyFactory}.
	 * 
	 * <p>The default {@link InterfaceProxyFactory} can only be used to create proxies
	 * of interfaces.
	 *
	 * @return the currently used type proxy factory
	 */
	public function getTypeProxyFactory(Void):ProxyFactory {
		if (!typeProxyFactory) typeProxyFactory = new InterfaceProxyFactory();
		return typeProxyFactory;
	}
	
	/**
	 * Sets the new type proxy factory that is used to create proxies for a specific type.
	 * 
	 * <p>If you set a type proxy factory of value {@code null}, {@link #getTypeProxyFactory}
	 * will return the default factory.
	 *
	 * @param proxyFactory the new type proxy factory
	 */
	public function setTypeProxyFactory(typeServiceProxyFactory:ProxyFactory):Void {
		this.typeProxyFactory = typeServiceProxyFactory;
	}
	
	/**
	 * Returns the client service proxy factory used to create client service proxy
	 * instances.
	 * 
	 * <p>The returned factory is either the one set via {@link #setClientServiceProxyFactory}
	 * or the default one which is an instance of {@link SimpleClientServiceProxyFactory}.
	 *
	 * @return the currently used client service proxy factory
	 */
	public function getClientServiceProxyFactory(Void):ClientServiceProxyFactory {
		if (!clientServiceProxyFactory) clientServiceProxyFactory = new SimpleClientServiceProxyFactory();
		return clientServiceProxyFactory;
	}
	
	/**
	 * Sets a new client service proxy factory used to get client service
	 * proxy instances.
	 *
	 * <p>If you set a new factory of value null or undefined {@link #getClientServiceProxyFactory}
	 * will return the default factory.
	 *
	 * @param clientServiceProxyFactory the new client service proxy factory
	 */
	public function setClientServiceProxyFactory(clientServiceProxyFactory:ClientServiceProxyFactory):Void {
		this.clientServiceProxyFactory = clientServiceProxyFactory;
	}
	
	/**
	 * Returns a client service proxy for the service specified by the passed-in
	 * {@code url}.
	 * 
	 * <p>You can use the returned proxy to invoke methods on the 'remote' service and
	 * to handle responses.
	 * 
	 * @param url the url of the 'remote' service
	 * @return a client service proxy to invoke methods on the 'remote' service
	 */
	public function getClientServiceProxyByUrl(url:String):ClientServiceProxy {
		return getClientServiceProxyFactory().getClientServiceProxy(url);
	}
	
	/**
	 * Returns a client service proxy that can be typed to the passed-in {@code type}
	 * (class or interface).
	 * 
	 * <p>The type is therefore normally the type of the 'remote' service you wanna
	 * invoke methods on.
	 * 
	 * <p>If {@code type} is {@code null}, an instance of type {@link ClientServiceProxy}
	 * will be returned. That means this method will then do the same as the
	 * {@link #getClientServiceProxyByUrl} method.
	 *
	 * <p>Note that with the default configuration only interfaces can be used as
	 * {@code type}. You can edit this behavior through the {@link #setTypeProxyFactory}.
	 * method.
	 * 
	 * @param url the url of the 'remote' service
	 * @param type the type of the 'remote' service
	 * @return a client service proxy that can be casted to the passed-in {@code type}
	 */
	public function getClientServiceProxyByUrlAndType(url:String, type:Function) {
		var serviceProxy:ClientServiceProxy = getClientServiceProxyByUrl(url);
		if (!type) return serviceProxy;
		var handler:InvocationHandler = getBlankInvocationHandler();
		handler.invoke = function(proxy, methodName:String, args:Array) {
			if (args[args.length-1] instanceof MethodInvocationCallback) {
				var callback:MethodInvocationCallback = MethodInvocationCallback(args.pop());
				return serviceProxy.invokeByNameAndArgumentsAndCallback(methodName, args, callback);
			} else {
				return serviceProxy.invokeByNameAndArguments(methodName, args);
			}
		};
		return getTypeProxyFactory().createProxy(type, handler);
	}
	
	/**
	 * Returns a blank invocation handler. This is a handler with no methods implemented.
	 * 
	 * @return a blank invocation handler
	 */
	private function getBlankInvocationHandler(Void):InvocationHandler {
		var result = new Object();
		result.__proto__ = InvocationHandler["prototype"];
		result.__constructor__ = InvocationHandler;
		return result;
	}
	
}