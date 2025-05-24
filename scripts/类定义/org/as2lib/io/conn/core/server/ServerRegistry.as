﻿/*
 * Copyright the original author or authors.
 * 
 * Licensed under the Mozilla Public License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.mozilla.org/MPL/2.0/
 *
 * This file may be redistributed under the terms of the GNU General Public License,
 * version 3.0 (GPLv3), or any later version.
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
 
import org.as2lib.core.BasicInterface;

/**
 * {@code ServerRegistry} keeps track of running servers.
 * 
 * @author Simon Wacker
 * @author Christoph Atteneder
 */
interface org.as2lib.io.conn.core.server.ServerRegistry extends BasicInterface {
	
	/**
	 * Checks if a server with passed-in {@code host} exists / is registerd.
	 * 
	 * @param host the name of server
	 */
	public function containsServer(host:String):Boolean;
	
	/**
	 * Registers a server with the given {@code host}.
	 * 
	 * @param host the host identifying the server to register
	 */
	public function registerServer(host:String):Void;
	
	/**
	 * Unregisters the server with the given {@code host}.
	 *
	 * @param host the host identifying the server to unregister
	 */
	public function removeServer(host:String):Void;
	
}