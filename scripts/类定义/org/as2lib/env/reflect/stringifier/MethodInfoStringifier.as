/*
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

import org.as2lib.core.BasicClass;
import org.as2lib.util.Stringifier;
import org.as2lib.env.reflect.MethodInfo;

/**
 * {@code MethodInfoStringifier} stringifies {@link MethodInfo} instances.
 *
 * @author Simon Wacker
 */
class org.as2lib.env.reflect.stringifier.MethodInfoStringifier extends BasicClass implements Stringifier {
	
	/**
	 * Returns the string representation of the passed-in {@link MethodInfo} instance.
	 * 
	 * <p>The string representation is composed as follows:
	 * <pre>
	 *   fullyQualifiedDeclaringTypeName.methodName
	 * </pre>
	 *
	 * <p>Or if static:
	 * <pre>
	 *   static fullyQualifiedDeclaringTypeName.methodName
	 * </pre>
	 * 
	 * @param target an instance of type {@link MethodInfo} to stringify
	 * @return the string representation of the passed-in {@code target} method info
	 */
	public function execute(target):String {
		var method:MethodInfo = MethodInfo(target);
		var result:String = "";
		if (method.isStatic()) {
			result += "static ";
		}
		result += method.getDeclaringType().getFullName();
		result += "." + method.getName();
		return result;
	}
	
}