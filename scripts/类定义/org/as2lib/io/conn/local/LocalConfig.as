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
import org.as2lib.io.conn.core.server.ServerRegistry;
import org.as2lib.io.conn.local.server.LocalServerRegistry;

/**
 * {@code LocalConfig} is the basic configuration class of the Local Connection API.
 * 
 * <p>It can be used to configure static parts, that means parts that are shared
 * globally.
 *
 * @author Simon Wacker
 */
class org.as2lib.io.conn.local.LocalConfig extends BasicClass {
	
	/** Stores the server registry. */
	private static var serverRegistry:ServerRegistry;
	
	/**
	 * Private constructor.
	 */
	private function LocalConfig(Void) {
	}
	
	/**
	 * Returns the currently used server registry.
	 *
	 * <p>That is either the server registry set via {@link #setServerRegistry} or the
	 * default on which is an instance of class {@link LocalServerRegistry}.
	 * 
	 * @return the currenlty used server registry
	 * @see #setServerRegistry
	 */
	public static function getServerRegistry(Void):ServerRegistry {
		if (!serverRegistry) serverRegistry = new LocalServerRegistry();
		return serverRegistry;
	}
	
	/**
	 * Sets a new server registry.
	 *
	 * <p>If you set a server registry of value {@code null} or {@code undefined}
	 * {@link #getServerRegistry} will return the default server registry.
	 * 
	 * @param newServerRegistry the new server registry
	 * @see #getServerRegistry
	 */
	public static function setServerRegistry(newServerRegistry:ServerRegistry):Void {
		serverRegistry = newServerRegistry;
	}
	
}