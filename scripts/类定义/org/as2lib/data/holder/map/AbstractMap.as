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
import org.as2lib.data.holder.map.MapStringifier;

/**
 * {@code AbstractMap} offers implementations of methods needed by most concrete
 * {@link org.as2lib.data.holder.Map} implementations.
 * 
 * @author Simon Wacker
 */
class org.as2lib.data.holder.map.AbstractMap extends BasicClass {
	
	/** Stringifies maps. */
	private static var stringifier:Stringifier;
	
	/**
	 * Returns the stringifier that stringifies maps.
	 *
	 * <p>If no stringifier has been set manually an instance of class {@link MapStringifier}
	 * will be returned.
	 * 
	 * @return the stringifier that stringifies maps
	 */
	public static function getStringifier(Void):Stringifier {
		if (!stringifier) stringifier = new MapStringifier();
		return stringifier;
	}
	
	/**
	 * Sets the new stringifier that stringifies maps.
	 *
	 * <p>If you set a stringifier of value {@code null} or {@code undefined} the static
	 * method {@link #getStringifier} will return the default stringifier.
	 * 
	 * @param mapStringifier the new map stringifier
	 */
	public static function setStringifier(mapStringifier:Stringifier):Void {
		stringifier = mapStringifier;
	}
	
	/**
	 * Constructs a new {@code AbstractMap} instance.
	 */
	private function AbstractMap(Void) {
	}
	
	/**
	 * Populates the map with the content of the passed-in {@code source}.
	 * 
	 * <p>Iterates over the passed-in source with the for..in loop and uses the variables'
	 * names as key and their values as value. Variables that are hidden from for..in
	 * loops will not be added to this map.
	 * 
	 * <p>This method uses the {@code put} method to add the key-value pairs.
	 * 
	 * @param source an object that contains key-value pairs to populate this map with
	 */
	private function populate(source):Void {
		if (source) {
			for (var i:String in source) {
				this["put"](i, source[i]);
			}
		}
	}
	
}