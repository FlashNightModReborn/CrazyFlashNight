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
import org.as2lib.io.conn.core.server.ServerServiceProxy;

/**
 * {@code Server} acts as a composite for many services that are all combined in one
 * domain.
 * 
 * @author Simon Wacker
 * @author Christoph Atteneder
 */
interface org.as2lib.io.conn.core.server.Server extends BasicInterface {
	
	/**
	 * Runs this server and all added services.
	 */
	public function run(Void):Void;
	
	/**
	 * Stops all added services and this server.
	 */
	public function stop(Void):Void;
	
	/**
	 * Puts the passed-in {@code service} to the passed-in {@code path} on this server.
	 *
	 * <p>This means after starting this server you can invoke methods on the passed-in
	 * {@code service} using the server host plus the service {@code path} as url.
	 * 
	 * @param path the path through which the service can be accessed on this server
	 * @param service the actual service which provides the functionalities
	 * @return the service proxy that wraps the passed-in {@code service} and {@code path}
	 * @see #addService
	 */
	public function putService(path:String, service):ServerServiceProxy;
	
	/**
	 * Adds the passed-in {@code serviceProxy} to this server.
	 * 
	 * @param serviceProxy the proxy to add to this server
	 * @see #putService
	 */
	public function addService(serviceProxy:ServerServiceProxy):Void;
	
	/**
	 * Removes the service corresponding to the passed-in {@code path} from this server.
	 * 
	 * @param path the full path of the service to remove
	 * @return a service proxy that wraps the actual service
	 */
	public function removeService(path:String):ServerServiceProxy;
	
	/**
	 * Returns the service corresponding to the passed-in service {@code path}.
	 * 
	 * @param path the full path of the service to return
	 * @return a service proxy wrapping the actual service
	 */
	public function getService(path:String):ServerServiceProxy;
	
	/**
	 * Returns the name of this server.
	 * 
	 * @return the name of this server
	 */
	public function getHost(Void):String;
	
	/**
	 * Returns whether this server is running.
	 * 
	 * @return {@code true} if this server is running else {@code false}
	 */
	public function isRunning(Void):Boolean;
	
}