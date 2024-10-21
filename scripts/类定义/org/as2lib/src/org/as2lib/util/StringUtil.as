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
import org.as2lib.env.except.IllegalArgumentException;

/**
 * {@code StringUtil} offers a lot of different methods to work with strings.
 * 
 * @author Martin Heidegger
 * @author Simon Wacker
 * @author Christophe Herreman
 * @author Flashforum.de Community
 */
class org.as2lib.util.StringUtil extends BasicClass {
	
	/**
	 * Replaces all occurencies of the passed-in string {@code what} with the passed-in
	 * string {@code to} in the passed-in string {@code string}.
	 * 
	 * @param string the string to replace the content of
	 * @param what the string to search and replace in the passed-in {@code string}
	 * @param to the string to insert instead of the passed-in string {@code what}
	 * @return the result in which all occurences of the {@code what} string are replaced
	 * by the {@code to} string
	 */
	public static function replace(string:String, what:String, to:String):String {
		return string.split(what).join(to);
	}
	
	/**
	 * Removes all empty characters at the beginning and at the end of the passed-in 
	 * {@code string}.
	 *
	 * <p>Characters that are removed: spaces {@code " "}, line forwards {@code "\n"} 
	 * and extended line forwarding {@code "\t\n"}.
	 * 
	 * @param string the string to trim
	 * @return the trimmed string
	 */
	public static function trim(string:String):String {
		return leftTrim(rightTrim(string));
	}
	
	/**
	 * Removes all empty characters at the beginning of a string.
	 *
	 * <p>Characters that are removed: spaces {@code " "}, line forwards {@code "\n"} 
	 * and extended line forwarding {@code "\t\n"}.
	 * 
	 * @param string the string to trim
	 * @return the trimmed string
	 */
	public static function leftTrim(string:String):String {
		return leftTrimForChars(string, "\n\t\n ");
	}

	/**
	 * Removes all empty characters at the end of a string.
	 * 
	 * <p>Characters that are removed: spaces {@code " "}, line forwards {@code "\n"} 
	 * and extended line forwarding {@code "\t\n"}.
	 * 
	 * @param string the string to trim
	 * @return the trimmed string
	 */	
	public static function rightTrim(string:String):String {
		return rightTrimForChars(string, "\n\t\n ");
	}
	
	/**
	 * Removes all characters at the beginning of the {@code string} that match to the
	 * set of {@code chars}.
	 * 
	 * <p>This method splits all {@code chars} and removes occurencies at the beginning.
	 * 
	 * <p>Example:
	 * <code>
	 *   trace(StringUtil.rightTrimForChars("ymoynkeym", "ym")); // oynkeym
	 *   trace(StringUtil.rightTrimForChars("monkey", "mo")); // nkey
	 *   trace(StringUtil.rightTrimForChars("monkey", "om")); // nkey
	 * </code>
	 * 
	 * @param string the string to trim
	 * @param chars the characters to remove from the beginning of the {@code string}
	 * @return the trimmed string
	 */
	public static function leftTrimForChars(string:String, chars:String):String {
		var from:Number = 0;
		var to:Number = string.length;
		while (from < to && chars.indexOf(string.charAt(from)) >= 0){
			from++;
		}
		return (from > 0 ? string.substr(from, to) : string);
	}
	
	/**
	 * Removes all characters at the end of the {@code string} that match to the set of
	 * {@code chars}.
	 * 
	 * <p>This method splits all {@code chars} and removes occurencies at the end.
	 * 
	 * <p>Example:
	 * <code>
	 *   trace(StringUtil.rightTrimForChars("ymoynkeym", "ym")); // ymoynke
	 *   trace(StringUtil.rightTrimForChars("monkey***", "*y")); // monke
	 *   trace(StringUtil.rightTrimForChars("monke*y**", "*y")); // monke
	 * </code>
	 * 
	 * @param string the string to trim
	 * @param chars the characters to remove from the end of the {@code string}
	 * @return the trimmed string
	 */
	public static function rightTrimForChars(string:String, chars:String):String {
		var from:Number = 0;
		var to:Number = string.length - 1;
		while (from < to && chars.indexOf(string.charAt(to)) >= 0) {
			to--;
		}
		return (to >= 0 ? string.substr(from, to+1) : string);
	}
	
	/**
	 * Removes all characters at the beginning of the {@code string} that matches the
	 * {@code char}.
	 * 
	 * <p>Example:
	 * <code>
	 *   trace(StringUtil.leftTrimForChar("yyyymonkeyyyy", "y"); // monkeyyyy
	 * </code>
	 * 
	 * @param string the string to trim
	 * @param char the character to remove
	 * @return the trimmed string
	 * @throws IllegalArgumentException if you try to remove more than one character
	 */
	public static function leftTrimForChar(string:String, char:String):String {
		if(char.length != 1) {
			throw new IllegalArgumentException("The Second Attribute char [" + char + "] must exactly one character.", 
					eval("th" + "is"), 
					arguments);
		}
		return leftTrimForChars(string, char);
	}
	
	/**
	 * Removes all characters at the end of the {@code string} that matches the passed-in
	 * {@code char}.
	 * 
	 * <p>Example:
	 * <code>
	 *   trace(StringUtil.rightTrimForChar("yyyymonkeyyyy", "y"); // yyyymonke
	 * </code>
	 * 
	 * @param string the string to trim
	 * @param char the character to remove
	 * @return the trimmed string
	 * @throws IllegalArgumentException if you try to remove more than one character
	 */
	public static function rightTrimForChar(string:String, char:String):String {
		if(char.length != 1) {
			throw new IllegalArgumentException("The Second Attribute char [" + char + "] must exactly one character.", 
												eval("th" + "is"), 
												arguments);
		}
		return rightTrimForChars(string, char);
	}

	/**
	 * Validates the passed-in {@code email} adress to a predefined email pattern.
	 * 
	 * @param email the email to check whether it is well-formatted
	 * @return {@code true} if the email matches the email pattern else {@code false}
	 */
	public static function checkEmail(email:String):Boolean {
		// The min Size of an Email is 6 Chars "a@b.cc";
		if (email.length < 6) {
			return false;
		}
		// There must be exact one @ in the Content
		if (email.split('@').length > 2 || email.indexOf('@') < 0) {
			return false;
		}
		// There must be min one . in the Content before the last @
		if (email.lastIndexOf('@') > email.lastIndexOf('.')) {
			return false;
		}
		// There must be min two Characters after the last .
		if (email.lastIndexOf('.') > email.length - 3) {
			return false;
		}
		// There must be min two Characters between the @ and the last .
		if (email.lastIndexOf('.') <= email.lastIndexOf('@') + 1) {
			return false;
		}
		return true;
	}
	
	/**
	 * Assures that the passed-in {@code string} is bigger or equal to the passed-in
	 * {@code length}.
	 * 
	 * @param string the string to validate
	 * @param length the length the {@code string} should have
	 * @return {@code true} if the length of {@code string} is bigger or equal to the
	 * expected length else {@code false}
	 * @throws IllegalArgumentException if the expected length is less than 0
	 */
	public static function assureLength(string:String, length:Number):Boolean {
		if (length < 0 || (!length && length !== 0)) {
			throw new IllegalArgumentException("The given length [" + length + "] has to be bigger or equals 0.", 
					eval("th" + "is"), 
					arguments);
		}
		return (string.length >= length);
	}
	
	/**
	 * Evaluates if the passed-in {@code chars} are contained in the passed-in
	 * {@code string}.
	 *
	 * <p>This methods splits the {@code chars} and checks if any character is contained
	 * in the {@code string}.
	 * 
	 * <p>Example:
	 * <code>
	 *   trace(StringUtil.contains("monkey", "kzj0")); // true
	 *   trace(StringUtil.contains("monkey", "yek")); // true
	 *   trace(StringUtil.contains("monkey", "a")); // false
	 * </code>
	 * 
	 * @param string the string to check whether it contains any of the characters
	 * @param chars the characters to look whether any of them is contained in the
	 * {@code string}
	 * @return {@code true} if one of the {@code chars} is contained in the {@code string}
	 */
	public static function contains(string:String, chars:String):Boolean {
		if(chars == null || string == null) {
			return false;
		}
		for (var i:Number = chars.length-1; i >= 0 ; i--) {
			if (string.indexOf(chars.charAt(i)) >= 0) {
				return true;
			}
		}
		return false;
	}
	
	/**
	 * Evaluates if the passed-in {@code stirng} starts with the {@code searchString}.
	 * 
	 * @param string the string to check
	 * @param searchString the search string that may be at the beginning of {@code string}
	 * @return {@code true} if {@code string} starts with {@code searchString} else
	 * {@code false}.
	 */
	public static function startsWith(string:String, searchString:String):Boolean {
		if (string.indexOf(searchString) == 0) {
			return true;
		}
		return false;
	}
	
	/**
	 * Tests whether the {@code string} ends with {@code searchString}.
	 *
	 * @param string the string to check
	 * @param searchString the string that may be at the end of {@code string}
	 * @return {@code true} if {@code string} ends with {@code searchString}
	 */
	public static function endsWith(string:String, searchString:String):Boolean {
		if (string.lastIndexOf(searchString) == (string.length - searchString.length)) {
			return true;
		}
		return false;
	}
	
	/**
	 * Adds a space indent to the passed-in {@code string}.
	 *
	 * <p>This method is useful for different kind of ASCII output writing. It generates
	 * a dynamic size of space indents in front of every line inside a string.
	 * ################################################################################
	 * <p>Example:
	 * <code>
	 *   var bigText = "My name is pretty important\n"
	 *                 + "because i am a interesting\n"
	 *                 + "small example for this\n"
	 *                 + "documentation.";
	 *   var result = StringUtil.addSpaceIndent(bigText, 3);
	 * </code>
	 * 
	 * <p>Contents of {@code result}:
	 * <pre>
	 *   My name is pretty important
	 *      because i am a interesting
	 *      small example for this
	 *      documentation.
	 * </pre>
	 *
	 * <p>{@code indent} will be floored.
	 * 
	 * @param string the string that contains lines to indent
	 * @param indent the size of the indent
	 * @return the indented string
	 * @throws IllegalArgumentException if the {@code size} is smaller than 0
	 */
	public static function addSpaceIndent(string:String, size:Number):String {
		if (string == null) {
			string = "";
		}
		if (size < 0) {
			throw new IllegalArgumentException("The given size has to be bigger or equals null.", eval("th"+"is"), arguments);
		}
		var indentString:String = multiply(" ", size);
		return indentString+replace(string, "\n", "\n"+indentString);
	}
	
	/**
	 * Multiplies the passed-in {@code string} by the passed-in {@code factor} to create
	 * long string blocks.
	 * 
	 * <p>Example:
	 * <code>
	 *   trace("Result: "+StringUtil.multiply(">", 6); // Result: >>>>>>
	 * </code>
	 *
	 * @param string the source string to multiply
	 * @param factor the number of times to multiply the {@code string}
	 * @result the multiplied string
	 */
	public static function multiply(string:String, factor:Number):String {
		var result:String="";
		for (var i:Number = factor; i > 0; i--) {
			result += string;
		}
		return result;
	}

	/**
	 * Capitalizes the first character of the passed-in {@code string}.
	 * 
	 * @param string the string of which the first character shall be capitalized
	 * @return the passed-in {@code string} with the first character capitalized
	 */
	public static function ucFirst(string:String):String {
		 return string.charAt(0).toUpperCase() + string.substr(1);
	}

	/**
	 * Capitalizes the first character of every word in the passed-in {@code string}.
	 * 
	 * @param string the string of which the first character of every word shall be
	 * capitalized
	 * @return the {@code string} with the first character of every word capitalized
	 */
	public static function ucWords(string:String):String {
		var w:Array = string.split(" ");
		var l:Number = w.length;
		for (var i:Number = 0; i < l; i++){
			w[i] = StringUtil.ucFirst(w[i]);
		}
		return w.join(" ");
	}
	
	/**
	 * Returns the first character of the passed-in {@code string}.
	 * 
	 * @param string the string to return the first character of
	 * @return the first character of the {@code string}
	 */
	public static function firstChar(string:String):String {
		return string.charAt(0);
	}
	
	/**
	 * Returns the last character of the passed-in {@code string}.
	 * 
	 * @param string the string to return the last character of
	 * @return the last character of the {@code string}
	 */
	public static function lastChar(string:String):String {
		return string.charAt(string.length-1);
	}
	
	private static function getCharValue(char:String):Number {
		var code:Number = char.toUpperCase().charCodeAt(0);
		// Number Area
		if (code > 47 && code < 58) return (code-48);
		// String Area
		if (code > 64 && code < 91) return (code-55);
		// Default value
		return 0;
	}
	
	public static var DEFAULT_ESCAPE_MAP:Array = 
		["\\t", "\t", "\\n", "\n", "\\r", "\r", "\\\"", "\"", "\\\\", "\\", "\\'", "\'", "\\f", "\f", "\\b", "\b", "\\", ""];
	
	public static function escape(string:String, keyMap:Array, ignoreUnicode:Boolean):String {
		if (!keyMap) {
			keyMap = DEFAULT_ESCAPE_MAP;
		}
		var i:Number = 0;
		var l:Number = keyMap.length;
		while (i<l) {
			string = string.split(keyMap[i]).join(keyMap[i+1]);
			i+=2;
		}
		if (!ignoreUnicode) {
			i = 0;
			l = string.length;
			while (i<l) {
				if (string.substring(i, i+2) == "\\u") {
					string = 
						string.substring(0,i) + 
						String.fromCharCode(
							parseInt(string.substring(i+2, i+6), 16)
						) +
						string.substring(i+6);
				}
				i++;
			}
		}
		return string;
	}
	
	/**
	 * Private Constructor.
	 */
	private function StringUtil(Void) {
	}
	
}