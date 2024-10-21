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

import org.as2lib.data.type.Byte;
import org.as2lib.io.file.SimpleTextFile;
import org.as2lib.data.holder.Properties;
import org.as2lib.data.holder.properties.PropertiesParser;

/**
 * {@code PropertiesFile} represents a file of properties.
 * 
 * <p>A properties file contains simple key-value pairs. Multiple pairs are
 * separated by line terminators (\n or \r or \r\n). Keys are separated from
 * values with the characters '=', ':' or a white space character.
 * 
 * <p>Comments are also supported. Just add a '#' or '!' character at the
 * beginning of your comment-line.
 * 
 * <p>If you want to use any of the special characters in your key or value you
 * must escape it with a back-slash character '\'.
 * 
 * <p>The key contains all of the characters in a line starting from the first
 * non-white space character up to, but not including, the first unescaped
 * key-value-separator.
 * 
 * <p>The value contains all of the characters in a line starting from the first
 * non-white space character after the key-value-separator up to the end of the
 * line. You may of course also escape the line terminator and create a value
 * across multiple lines.
 * 
 * @author Martin Heidegger
 * @author Simon Wacker
 * @version 1.0
 * @see PropertiesParser
 */
class org.as2lib.io.file.PropertiesFile extends SimpleTextFile {
	
	/** The data structure representation of this properties file. */
	private var properties:Properties;
	
	/**
	 * Constructs a new {@code PropertiesFile} instance.
	 * 
	 * <p>For information on how the source must look like take a look at this class's
	 * class documentation.
	 * 
	 * @param source the content of the properties file
	 * @param size the size in bytes of the properties file
	 * @param uri the URI to the properties file
	 */
	public function PropertiesFile(source:String, size:Byte, uri:String) {
		super(source, size, uri);
	}
	
	/**
	 * Returns the data structure representaton of this properties file.
	 * 
	 * @return this properties file data structure representation
	 */
	public function getProperties(Void):Properties {
		if (!properties) {
			properties = (new PropertiesParser()).parseProperties(source);
		}
		return properties;
	}
	
}