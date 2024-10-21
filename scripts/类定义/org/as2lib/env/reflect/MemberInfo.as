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

/**
 * {@code MemberInfo} represents a member in the Flash environment.
 * 
 * <p>Members are basically every constructs of ActionScript. Members are for
 * example methods, properties, variables, classes, interfaces and packages.
 *
 * @author Simon Wacker
 */
interface org.as2lib.env.reflect.MemberInfo extends BasicInterface {
	
	/**
	 * Returns the name of this member.
	 *
	 * <p>The name of this member does not include its preceding package structure when
	 * talking of interfaces, classes or packages.
	 * 
	 * @return this member's name
	 */
	public function getName(Void):String;
	
	/**
	 * Returns the name of this member plus the name of the member that contains this
	 * member.
	 * 
	 * @return this member's full name	 */
	public function getFullName(Void):String;
	
}