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
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.data.holder.Map;
import org.as2lib.data.holder.map.PrimitiveTypeMap;
import org.as2lib.io.conn.core.server.Server;
import org.as2lib.io.conn.core.server.ServerServiceProxy;
import org.as2lib.io.conn.core.server.ServerRegistry;
import org.as2lib.io.conn.local.server.LocalServerServiceProxy;
import org.as2lib.io.conn.local.LocalConfig;

/**
 * {@code LocalServer} acts as a composite for many services that are all combined
 * in one domain.
 * 
 * <p>Example:
 * <code>
 *   var server:LocalServer = new LocalServer("local.as2lib.org");
 *   server.putService("myServiceOne", new MyServiceOne());
 *   server.putService("myServiceTwo", new MyServiceTwo());
 *   server.run();
 * </code>
 *
 * @author Simon Wacker
 * @author Christoph Atteneder
 */
class org.as2lib.io.conn.local.server.LocalServer extends BasicClass implements Server {
	
	/** Name of this server. */
	private var host:String;
	
	/** All services. */
	private var services:Map;
	
	/** Server status. */
	private var running:Boolean;
	
	/** Stores the server registry. */
	private var serverRegistry:ServerRegistry;
	
	/**
	 * Constructs a new {@code LocalServer} instance.
	 *
	 * @param host the name of this server
	 * @throws IllegalArgumentException if the passed-in {@code host} is {@code null},
	 * {@code undefined} or an empty string
	 */
	public function LocalServer(host:String) {
		if (!host) throw new IllegalArgumentException("Argument 'host' must not be null, undefined or a blank string.", this, arguments);
		this.host = host;
		services = new PrimitiveTypeMap();
		running = false;
	}
	
	/**
	 * Returns the currently used server registry.
	 *
	 * <p>This is either the server registry set via {@link #setServerRegistry} or the
	 * default registry returned by the {@link LocalConfig#getServerRegistry} method.
	 * 
	 * @return the currently used server registry
	 */
	public function getServerRegistry(Void):ServerRegistry {
		if (!serverRegistry) serverRegistry = LocalConfig.getServerRegistry();
		return serverRegistry;
	}
	
	/**
	 * Sets a new server registry.
	 *
	 * <p>If {@code serverRegistry} is {@code null} or {@code undefined} the
	 * {@link #getServerRegistry} method will return the default server registry.
	 * 
	 * @param serverRegistry the new server registry
	 */
	public function setServerRegistry(serverRegistry:ServerRegistry):Void {
		this.serverRegistry = serverRegistry;
	}
	
	/**
	 * Runs this server.
	 *
	 * <p>This involves registering itself at the server registry and running all added
	 * services with this host.
	 * 
	 * <p>If this server is already running a restart will be made. This means it will
	 * be stopped and run again.
	 */
	public function run(Void):Void {
		if (isRunning()) this.stop();
		getServerRegistry().registerServer(getHost());
		if (services.size() > 0) {
			var serviceArray:Array = services.getValues();
			for (var i:Number = 0; i < serviceArray.length; i++) {
				ServerServiceProxy(serviceArray[i]).run(host);
			}
		}
		running = true;
	}
	
	/**
	 * Stops this server.
	 * 
	 * <p>This involves stopping all services and removing itself from the server registry.
	 */
	public function stop(Void):Void {
		if (services.size() > 0) {
			var serviceArray:Array = services.getValues();
			for (var i:Number = 0; i < serviceArray.length; i++) {
				ServerServiceProxy(serviceArray[i]).stop();
			}
		}
		if (getServerRegistry().containsServer(getHost())) {
			getServerRegistry().removeServer(getHost());
		}
		running = false;
	}
	
	/**
	 * Puts the passed-in {@code service} to the passed-in {@code path} on this server.
	 * 
	 * <p>{@code service} and {@code path} are wrapped in a {@link ServerServiceProxy}
	 * instance.
	 *
	 * @param path that path to the service on the host
	 * @param service the service to make locally available
	 * @return the newly created server service proxy that wraps {@code service} and 
	 * {@code path}
	 * @throws IllegalArgumentException if the passed-in {@code path} is {@code null}, 
	 * {@code undefined} or an empty string or if the passed-in {@code service} is
	 * {@code null} or {@code undefined}
	 * @see #addService
	 */
	public function putService(path:String, service):ServerServiceProxy {
		// source out instantiation
		var proxy:ServerServiceProxy = new LocalServerServiceProxy(path, service);
		addService(proxy);
		return proxy;
	}
	
	/**
	 * Adds the passed-in {@code serviceProxy} to this service.
	 *
	 * <p>If this server is running, the {@code serviceProxy} will be run immediately
	 * too.
	 * 
	 * @param serviceProxy the proxy that wraps the actual service
	 * @throws IllegalArgumentException if the passed-in {@code serviceProxy} is
	 * {@code null} or {@code undefined} or if the path of the passed-in {@code serviceProxy}
	 * is {@code null}, {@code undefined} or an empty string or if the path of the passed-in
	 * {@code serviceProxy} is already in use
	 * @see #putService
	 */
	public function addService(serviceProxy:ServerServiceProxy):Void {
		if (!serviceProxy) throw new IllegalArgumentException("Service proxy must not be null or undefined.", this, arguments);
		var path:String = serviceProxy.getPath();
		if (!path) throw new IllegalArgumentException("Service proxy's path must not be null, undefined or a blank string.", this, arguments);
		if (services.containsKey(path)) throw new IllegalArgumentException("Service proxy with proxy path [" + path + "] is already in use.", this, arguments);
		services.put(path, serviceProxy);
		if (isRunning()) {
			serviceProxy.run(host);
		}
	}
	
	/**
	 * Removes the service registered wiht the passed-in {@code path}.
	 * 
	 * <p>If the service is running it will be stopped.
	 *
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>The passed-in {@code path} is {@code null} or an empty string.</li>
	 *   <li>There is no registered service with the passed-in {@code path}.</li>
	 * </ul>
	 *
	 * @param path the path of the service to remove
	 * @return the removed server service proxy wrapping the actual service
	 */
	public function removeService(path:String):ServerServiceProxy {
		if (!path) return null;
		var service:ServerServiceProxy = services.remove(path);
		if (service.isRunning()) service.stop();
		return service;
	}
	
	/**
	 * Returns the service registered with the passed-in {@code path}.
	 * 
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>The passed-in {@code path} is {@code null} or an empty string.</li>
	 *   <li>There is no service registered with the passed-in {@code path}.</li>
	 * </ul>
	 *
	 * @param path the path of the service to return
	 * @return the server service proxy wrapping the actual service
	 */
	public function getService(path:String):ServerServiceProxy {
		if (!path) return null;
		return services.get(path);
	}
	
	/**
	 * Returns whether this server is running.
	 *
	 * <p>This server is by default not running. It runs as soon as you call the
	 * {@link #run} method. And stops when you call the {@ink #stop} method.
	 * 
	 * @return {@code true} if this server is running else {@code false}
	 */
	public function isRunning(Void):Boolean {
		return running;
	}
	
	/**
	 * Returns the host of this server.
	 *
	 * @return this host of this server
	 */
	public function getHost(Void):String {
		return host;
	}
	
}