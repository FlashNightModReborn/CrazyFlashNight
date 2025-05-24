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
 * {@code InvocationHandler} handles method invocations that took place on dynamic
 * proxies.
 * 
 * <p>It is passed all the needed information to respond appropriately to the
 * incovation.
 *
 * @author Simon Wacker
 * @see org.as2lib.env.reflect.ProxyFactory
 */
interface org.as2lib.env.reflect.InvocationHandler extends BasicInterface {
	
	/**
	 * Is invoked when a method invocation on a proxy took place and returns the result
	 * of the invocation.
	 * 
	 * @param proxy the proxy the {@code method} was invoked on
	 * @param method the method that was invoked
	 * @param args the arguments that were passed to the {@code method} on invocation
	 * @return the result of the method invocation
	 */
	public function invoke(proxy, method:String, args:Array);
	
}