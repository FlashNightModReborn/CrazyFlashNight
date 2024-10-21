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
import org.as2lib.data.holder.properties.SimpleProperties;
import org.as2lib.data.holder.Properties;
import org.as2lib.data.type.MultilineString;
import org.as2lib.util.StringUtil;

/**
 * {@code PropertiesParser} parses a properties source string into a {@link Properties}
 * instance.
 * 
 * <p>The source string contains simple key-value pairs. Multiple pairs are
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
 */
class org.as2lib.data.holder.properties.PropertiesParser extends BasicClass {
	
	/**
	 * Constructs a new {@code PropertiesParser} instance.
	 */
	public function PropertiesParser(Void) {
	}
	
	/**
	 * Parses the given {@code source} and creates a {@code Properties} instance from
	 * it.
	 * 
	 * @param source the source to parse
	 * @return the properties defined by the given {@code source}
	 */
	public function parseProperties(source:String):Properties {
		var result:Properties = new SimpleProperties();
		var lines:MultilineString = new MultilineString(source);
		var i:Number;
		var c:Number = lines.getLineCount();
		var key:String;
		var value:String;
		var formerKey:String;
		var formerValue:String;
		var useNextLine:Boolean = false;;
		for (i=0; i<c; i++) {
			var line:String = lines.getLine(i);
			// Trim the line
			line = StringUtil.trim(line);
			// Ignore Comments
			if ( line.indexOf("#") != 0 && line.indexOf("!") != 0 && line.length != 0) {
				// Line break processing
				if (useNextLine) {
					key = formerKey;
					value = formerValue+line;
					useNextLine = false;
				} else {
					var sep:Number = getSeperation(line);
					key = StringUtil.rightTrim(line.substr(0,sep));
					value = line.substring(sep+1);
					formerKey = key;
					formerValue = value;
				}
				// Trim the content
				value = StringUtil.leftTrim(value);
				// Allow normal lines
				if (value.charAt(value.length-1) == "\\") {
					formerValue = value =  value.substr(0, value.length-1);
					useNextLine = true;
				} else {
					// Commit Property
					result.setProperty(key, value);
				}
			}
		}
		return result;
	}
	
	/**
	 * Returns the position at which key and value are separated.
	 * 
	 * @param line the line that contains the key-value pair
	 * @return the position at which key and value are separated
	 */
	private function getSeperation(line:String):Number {
		var i:Number;
		var l:Number = line.length;
		for (i=0; i<l; i++) {
			var c:String = line.charAt(i);
			if (c == "'") {
				i++;
			} else {
				if (c == ":" || c == "=" || c == "	") break;
			}
		}
		return ( (i == l) ? line.length : i );
	}
	
}