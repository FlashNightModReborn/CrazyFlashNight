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
import org.as2lib.core.ObjectStringifier;
import org.as2lib.util.Stringifier;

/**
 * {@code Config} is the basic configuration class of the as2lib framework.
 * 
 * <p>It lets you configure global behavior of key features like the stringification
 * of classes and instances.
 * 
 * @author Martin Heidegger
 * @author Simon Wacker
 */
class org.as2lib.Config extends BasicClass {
	
	/** Stringifier used to stringify objects. */
	private static var objectStringifier:Stringifier;
	
	/**
	 * Private constructor.
	 */
	private function Config(Void) {
	}
	
	/**
	 * Sets a new stringifier used to stringify objects.
	 *
	 * <p>If {@code newStringifier} is {@code null} or {@code undefined}
	 * {@link #getObjectStringifier} will return the default stringifier.
	 * 
	 * @param newStringifier the new object stringifier
	 */
	public static function setObjectStringifier(newStringifier:Stringifier):Void {
		objectStringifier = newStringifier;
	}
	
	/**
	 * Returns the stringifier used to stringify objects.
	 *
	 * <p>If no stringifier is set the default stringifier will be returned. This is an
	 * instance of class {@link ObjectStringifier}.
	 * 
	 * @return the currently used object stringifier
	 */
	public static function getObjectStringifier(Void):Stringifier {
		if (!objectStringifier) objectStringifier = new ObjectStringifier();
		return objectStringifier;
	}
	
}