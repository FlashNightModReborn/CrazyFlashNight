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
 * {@code Properties} represents a persistent set of properties; simply key-value
 * pairs.
 * 
 * @author Martin Heidegger
 * @author Simon Wacker
 * @version 1.0
 */
interface org.as2lib.data.holder.Properties extends BasicInterface {
	
	/**
	 * Returns the value associated with the given {@code key} if there is one, and the
	 * given {@code defaultValue} otherwise.
	 * 
	 * @param key the key to return the value for
	 * @param defaultValue the default value to return if there is no value mapped to the
	 * given {@code key}
	 * @return the value mapped to the given {@code key} or the given {@code defaultValue}
	 */
	public function getProperty(key:String, defaultValue:String):String;
	
	/**
	 * Sets the given {@code value} for the given {@code key}; the {@code value} is mapped
	 * to the {@code key}.
	 * 
	 * @param key the key to map the {@code value} to
	 * @param value the value to map to the {@code key}
	 */
	public function setProperty(key:String, value:String):Void;
	
}