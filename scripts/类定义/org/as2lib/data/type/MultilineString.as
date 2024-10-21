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
import org.as2lib.data.holder.Iterator;
import org.as2lib.data.holder.array.ArrayIterator;
import org.as2lib.Config;

/**
 * {@code MultilineString} is a extension for {@code String} that allows to access
 * all lines seperatly.
 * 
 * <p>To not have to deal with different forms of line breaks (Windows/Apple/Unix)
 * {@code MultilineString} automatically standarizes them to the {@code \n} character.
 * So the passed-in {@code string} will always get standardized.
 * 
 * <p>If you need to access the orignal {@code string} you can use
 * {@code getOriginalString}.
 * 
 * @author Martin Heidegger
 * @version 1.0
 */
class org.as2lib.data.type.MultilineString extends String implements BasicInterface {
	
	/** Character code for the WINDOWS line break. */
	private static var WIN_BREAK = String.fromCharCode(13)+String.fromCharCode(10);
	
	/** Character code for the APPLE line break. */
	private static var MAC_BREAK = String.fromCharCode(13);
	
	/** Original content without standardized line breaks. */
	private var original:String;
	
	/** Seperation of all lines for the string. */
	private var lines:Array;
	
	/**
	 * Constructs a new {@code MultilineString}.
	 * 
	 * @param string {@code String} to be handled as multiline
	 */
	public function MultilineString(string:String) {
		super(setString(string));
		lines = new Array();
		lines = split("\n");
	}
	
	/**
	 * Standardizes the passed-in string to have {@code \n} line breaks and saves
	 * the original content.
	 * 
	 * @param string {@code String} to be used
	 * @return {@code String} that contains no special line breaks
	 */
	private function setString(string:String):String {
		original = string;
		return string.split(WIN_BREAK).join("\n").split(MAC_BREAK).join("\n");
	}
	
	/**
	 * Returns the original used string (without line break standarisation).
	 * 
	 * @return the original used string
	 */
	public function getOriginalString(Void):String {
		return original;
	}
	
	/**
	 * Returns a specific line within the {@code MultilineString}.
	 * 
	 * <p>It will return {@code undefined} if the line does not exist.
	 * 
	 * <p>The line does not contain the line break.
	 * 
	 * <p>The counting of lines startes with {@code 0}.
	 * 
	 * @param line number of the line to get the content of
	 * @return content of the line
	 */
	public function getLine(line:Number):String {
		return lines[line];
	}
	
	/**
	 * Returns the content as array that contains each line.
	 * 
	 * @return content split into lines
	 */
	public function getLines(Void):Array {
		return lines.concat();
	}
	
	/**
	 * Returns the amount of lines in the content.
	 * 
	 * @return amount of lines within the content
	 */
	public function getLineCount(Void):Number {
		return lines.length;
	}
	
	/**
	 * Returns a {@link Iterator} to iterate through all lines of the content.
	 * 
	 * @return {@code Iterator} for all lines of the content
	 */
	public function lineIterator(Void):Iterator {
		return (new ArrayIterator(lines));
	}

    /**
     * Extended {@code .toString} implementation.
     * 
     * @return this instance as string
     */
	public function toString():String {
		return Config.getObjectStringifier().execute(this);
	}
}