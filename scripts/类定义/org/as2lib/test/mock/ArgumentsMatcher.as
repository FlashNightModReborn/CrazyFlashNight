﻿/**
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
 * {@code ArgumentsMatcher} matches a list of expected arguments against a list of
 * actual arguments.
 * 
 * @author Simon Wacker
 */
interface org.as2lib.test.mock.ArgumentsMatcher extends BasicInterface {
	
	/**
	 * Checks if the passed-in {@code expectedArguments} match the
	 * {@code actualArguments}.
	 * 
	 * @param expectedArguments the arguments that are expected
	 * @param actualArguments the actual arguments
	 * @return {@code true} if the arguments match else {@code false}
	 */
	public function matchArguments(expectedArguments:Array, actualArguments:Array):Boolean;
	
}