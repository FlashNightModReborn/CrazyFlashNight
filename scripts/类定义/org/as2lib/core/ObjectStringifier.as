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
import org.as2lib.util.Stringifier;
import org.as2lib.env.reflect.ReflectUtil;

/**
 * {@code ObjectStringifier} is the most basic stringifier form.
 *
 * <p>It stringifies all kinds of objects, this means classes, instances and 
 * primitives.
 * 
 * @author Simon Wacker
 */
class org.as2lib.core.ObjectStringifier extends BasicClass implements Stringifier {
	
	/**
	 * Returns the string representation of the passed-in {@code target} object.
	 * 
	 * <p>The string representation is composed as follows:
	 * <pre>
	 *   [type theFullQualifiedNameOfTheObjectsType]
	 * </pre>
	 * 
	 * <p>The string representation of the class {@code org.as2lib.core.BasicClass} or
	 * instances of it looks like this:
	 * <pre>
	 *   [type org.as2lib.core.BasicClass]
	 * </pre>
	 *
	 * @param target the target object to stringify
	 * @return the string representation of the passed-in {@code target} object
	 */
	public function execute(target):String {
		return "[type " + ReflectUtil.getTypeName(target) + "]";
	}
	
}