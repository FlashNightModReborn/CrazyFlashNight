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
import org.as2lib.io.conn.core.server.ServerRegistry;
import org.as2lib.io.conn.core.server.ReservedHostException;
import org.as2lib.io.conn.local.core.EnhancedLocalConnection;

/**
 * {@code LocalServerRegistry} keeps track of running servers.
 *
 * <p>This means that servers are registered to be aware of all servers that are
 * currently running. The servers are registered in a kind of gloabl registry, even
 * if you instantiate different instances of this class and in different swfs.
 * 
 * <p>Servers are expected to register themselves at this registry when they start
 * running and unregister themselves when they stop running.
 * 
 * <p>Example:
 * <code>
 *   var serverRegistry:LocalServerRegistry = new LocalServerRegistry();
 *   serverRegistry.registerServer("local.as2lib.org");
 *   serverRegistry.containsServer("local.as2lib.org");
 *   serverRegistry.removeServer("local.as2lib.org");
 * </code>
 *
 * <p>As you can see in the above example, not servers are registered but hosts,
 * that represent servers.
 * 
 * @author Simon Wacker
 * @author Christoph Atteneder
 */
class org.as2lib.io.conn.local.server.LocalServerRegistry extends BasicClass implements ServerRegistry {
	
	/** Contains all registered Servers. */
	private var serverRegistry:Object;
	
	/**
	 * Constructs a new {@code LocalServerRegistry} instance.
	 */
	public function LocalServerRegistry(Void) {
		serverRegistry = new Object();
	}
	
	/**
	 * Returns whether a server with the passed-in {@code host} is registered in some
	 * registry.
	 * 
	 * <p>This does not mean that the server is registered in this registry. It can be
	 * registered in another registry, even in another swf.
	 * 
	 * @param host the host that acts as an identifier for the server
	 * @return {@code true} if the server with the given {@code host} is regitered else
	 * {@code false}
	 */
	public function containsServer(host:String):Boolean {
		return EnhancedLocalConnection.connectionExists(host);
	}
	
	/**
	 * Registers the server with the given {@code host} at this server registry.
	 *
	 * <p>The server is registered gloablly, that means that registries in other swfs
	 * can check whether the server is registered.
	 * 
	 * @param host the host that acts as an identifier for the server
	 * @throws IllegalArgumentException if {@code host} is {@code null}, {@code undefined}
	 * or an empty string
	 * @throws ReservedHostException if a server with the passed-in {@code host} is already
	 * running
	 */
	public function registerServer(host:String):Void {
		if (!host) throw new IllegalArgumentException("Host must not be null, undefined or a blank string.", this, arguments);
		var connection:EnhancedLocalConnection = new EnhancedLocalConnection();
		try {
			connection.connect(host);
		} catch(exception:org.as2lib.io.conn.local.core.ReservedConnectionException) {
			// without braces around "new ReservedHostException.." not MTASC compatible
			throw (new ReservedHostException("Server with host [" + host + "] is already running.", this, arguments)).initCause(exception);
		}
		serverRegistry[host] = connection;
	}
	
	/**
	 * Removes the server with the given {@code host} from this server registry.
	 * 
	 * <p>Only servers that have been registered directly at this registry can be removed.
	 * 
	 * @param host the host that acts as an identifier for the server to remove
	 * @throws IllegalArgumentException if you try to unregister a server that has not
	 * been registered directly at this registry but at another one
	 */
	public function removeServer(host:String):Void {
		if (serverRegistry[host]) {
			var connection:EnhancedLocalConnection = serverRegistry[host];
			connection.close();
			serverRegistry[host] = undefined;
			return;
		}
		if (containsServer(host)) {
			throw new IllegalArgumentException("Local server registry can only remove servers that have been registered directly at it. Host [" + host + "] has been registered at another registry.", this, arguments);
		}
	}
	
}