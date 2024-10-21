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
 
import org.as2lib.regexp.Pattern;
import org.as2lib.env.except.Exception;
import org.as2lib.util.StringUtil;

/**
 * Unchecked exception thrown to indicate a syntax error in a
 * regular-expression pattern.
 *
 * @author Igor Sadovskiy
 */

class org.as2lib.regexp.PatternSyntaxException extends Exception {

    private var description:String;
    private var pattern:String;
    private var index:Number;

	private static var NEW_LINE:String = "\n";

    /**
     * Constructs a new instance of this class.
     *
     * @param description A description of the error
     * @param thrower The erroneous Pattern's instance thrown exception
     * @param args Arguments of the function thrown exception
     * 			

     */
    public function PatternSyntaxException(description:String, thrower:Pattern, args:FunctionArguments) {
		
		super(description, thrower, args);

		this.description = description;
		this.pattern = thrower["pattern"];
		this.index = thrower["cursor"];
    }

    /**
     * Retrieves the error index.
     *
     * @return  The approximate index in the pattern of the error
     */
    public function getIndex(Void):Number {
		return this.index;
    }

    /**
     * Retrieves the description of the error.
     *
     * @return  The description of the error
     */
    public function getDescription(Void):String {
		return this.description;
    }

    /**
     * Retrieves the erroneous regular-expression pattern.
     *
     * @return  The erroneous pattern
     */
    public function getPattern(Void):String {
		return this.pattern;
    }

    /**
     * Returns a multi-line string containing the description of the syntax
     * error and its index, the erroneous regular-expression pattern, and a
     * visual indication of the error index within the pattern.
     *
     * @return  The full detail message
     */
    public function getMessage(Void):String {
        var message:String = description;
		if (index >= 0) {
		    message += " near index " + index + ": ";
		}
        message += NEW_LINE + pattern;
		if (index >= 0) {
		    message += NEW_LINE + StringUtil.multiply(" ", index) + "^";
		}
        return message;
    }

}
