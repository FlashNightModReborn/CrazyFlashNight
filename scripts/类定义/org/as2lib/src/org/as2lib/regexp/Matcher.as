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
import org.as2lib.core.BasicClass;
import org.as2lib.env.except.Exception;

/**
 * {@code Matcher} provides implementations of the match, search and 
 * replace RegExp routines.
 * 
 * @author Igor Sadovskiy
 * @see org.as2lib.regexp.Pattern
 * @see org.as2lib.regexp.PosixPattern
 */

class org.as2lib.regexp.Matcher extends BasicClass {
	
    /**
     * The Pattern object that created this Matcher.
     */
    private var parentPattern:Pattern;

    /**
     * The storage used by groups. They may contain invalid values if
     * a group was skipped during the matching.
     */
    private var groups:Array;

    /**
     * The range within the string that is to be matched.
     */
    private var from, to:Number;

    /**
     * The original string being matched.
     */
    private var text:String;

    /**
     * Matcher state used by the last node. NOANCHOR is used when a
     * match does not have to consume all of the input. ENDANCHOR is
     * the mode used for matching all the input.
     */
    public static var ENDANCHOR:Number = 1;
    public static var NOANCHOR:Number  = 0;
    
    private var acceptMode:Number = NOANCHOR;

    /**
     * The range of string that last matched the pattern.
     */
    private var first, last:Number;

    /**
     * The end index of what matched in the last match operation.
     */
    private var oldLast:Number;

    /**
     * The index of the last position appended in a substitution.
     */
    private var lastAppendPosition:Number;

    /**
     * Storage used by nodes to tell what repetition they are on in
     * a pattern, and where groups begin. The nodes themselves are stateless,
     * so they rely on this field to hold state during a match.
     */
    private var locals:Array;


    public function Matcher(newParent:Pattern, newText:String) {
    	acceptMode = NOANCHOR;
    	first = -1;
    	last = -1;
    	oldLast = -1;
    	lastAppendPosition = 0;
    	
        parentPattern = newParent;
        text = newText;

        // Allocate state storage
        var parentGroupCount:Number = Math.max(newParent["groupCount"], 10);
        groups = new Array(parentGroupCount * 2);
        locals = new Array(newParent["localCount"]);

        // Put fields into initial states
        reset();
    }

    public function getPattern(Void):Pattern {
        return parentPattern;
    }

    public function reset(input:String):Matcher {
    	if (input != null) text = input;
    	
        first = -1;
        last = -1;
        oldLast = -1;
        for (var i = 0; i < groups.length; i++) {
            groups[i] = -1;
        }
        for (var i = 0; i < locals.length; i++) {
            locals[i] = -1;
        }
        lastAppendPosition = 0;
		return this;
    }

    public function getStartIndex(group:Number):Number {
    	if (first < 0) {
            throw new Exception("No match available", this, arguments);
    	}
    	if (group != null) {
	        if (group > getGroupCount()) {
	            throw new Exception("No group " + group, this, arguments);
	        }
	        return groups[group * 2];
    	} else return first;
    }

    public function getEndIndex(group:Number):Number {
        if (first < 0) {
            throw new Exception("No match available", this, arguments);
		}
        if (group != null) {
	        if (group > getGroupCount()) {
	            throw new Exception("No group " + group, this, arguments);
	        }
	        return groups[group * 2 + 1];
        } else return last;
    }

    public function getGroup(group:Number):String {
        if (first < 0) {
            throw new Exception("No match found", this, arguments);
        }
        if (group == null) group  = 0;
        if (group < 0 || group > getGroupCount()) {
            throw new Exception("No group " + group, this, arguments);
        }
        if ((groups[group*2] == -1) || (groups[group*2+1] == -1)) {
            return null;
        }
        return getSubSequence(groups[group * 2], groups[group * 2 + 1]);
    }

    public function getGroupCount(Void):Number {
        return parentPattern["groupCount"] - 1;
    }

    public function matches(Void):Boolean {
        reset();
        return match(0, getTextLength(), ENDANCHOR);
    }

    public function find(newFrom:Number, newTo:Number):Boolean {
    	if (newFrom == null && newTo == null) {
	        if (last == first) {
	           last++;
	        }
	        if (last > to) {
	            for (var i = 0; i < groups.length; i++) {
	                groups[i] = -1;
	            }
	            return false;
	        }
			newFrom = last;
			newTo = getTextLength();
    	} else if (from != null && to == null) {
	        newTo = getTextLength();
	        reset();
    	}
    	
        from   	= newFrom < 0 ? 0 : newFrom;
        to     	= newTo;
        first  	= from;
        last   	= -1;
        oldLast = oldLast < 0 ? from : oldLast;
        for (var i = 0; i < groups.length; i++) {
        	groups[i] = -1;
        }
        acceptMode = NOANCHOR;

        var result:Boolean = parentPattern["root"].match(this, from, text);
        if (!result) first = -1;
        oldLast = last;
        return result;
    }

    public function lookingAt(Void):Boolean {
        reset();
        return match(0, getTextLength(), NOANCHOR);
    }

    public function appendReplacement(source:String, replacement:String):String {

        // If no match, return error
        if (first < 0) {
            throw new Exception("No match available", this, arguments);
        }

        // Process substitution string to replace group references with groups
        var cursor:Number = 0;
        var s:String = replacement;
        var result:String = new String();

        while (cursor < replacement.length) {
            var nextChar:Number = replacement.charCodeAt(cursor);
            if (nextChar == 0x5C) { // check for "\"
                cursor++;
                nextChar = replacement.charCodeAt(cursor);
                result += chr(nextChar);
                cursor++;
            } else if (nextChar == 0x24) { // check for "$"
                // Skip past $
                cursor++;

                // The first number is always a group
                var refNum:Number = replacement.charCodeAt(cursor) - 0x30;
                if ((refNum < 0)||(refNum > 9)) {
                    throw new Exception("Illegal group reference", this, arguments);
                }
                cursor++;

                // Capture the largest legal group string
                var done:Boolean = false;
                while (!done) {
                    if (cursor >= replacement.length) {
                        break;
                    }
                    var nextDigit:Number = replacement.charCodeAt(cursor) - 0x30;
                    if ((nextDigit < 0) || (nextDigit > 9)) { // not a number
                        break;
                    }
                    var newRefNum:Number = (refNum * 10) + nextDigit;
                    if (getGroupCount() < newRefNum) {
                        done = true;
                    } else {
                        refNum = newRefNum;
                        cursor++;
                    }
                }

                // Append group
                if (getGroup(refNum) != null) {
                    result += String(getGroup(refNum));
                }
            } else {
                result += chr(nextChar);
                cursor++;
            }
        }

        // Append the intervening text
        source += getSubSequence(lastAppendPosition, first);
        // Append the match substitution
        source += result;

        lastAppendPosition = last;
		return source;
    }

    public function appendTail(source:String):String {
        return (source + getSubSequence(lastAppendPosition, getTextLength()));
    }

    public function replaceAll(replacement:String):String {
        reset();
        var result:Boolean = find();
        if (result) {
            var temp:String = new String();
            do {
                appendReplacement(temp, replacement);
                result = find();
            } while (result);
            appendTail(temp);
            return temp;
        }
        return text;
    }

    public function replaceFirst(replacement:String):String {
        var temp:String = new String();
        reset();
        if (find()) appendReplacement(temp, replacement);
        appendTail(temp);
        return temp;
    }

    private function match(newFrom:Number, newTo:Number, anchor:Number):Boolean {
        from 	= newFrom < 0 ? 0 : newFrom;
        to 		= newTo;
        first 	= from;
        last 	= -1;
        oldLast = oldLast < 0 ? from : oldLast;
        for (var i = 0; i < groups.length; i++) {
            groups[i] = -1;
        }
        acceptMode = anchor;

        var result:Boolean = parentPattern["matchRoot"].match(this, from, text);
        if (!result) first = -1;
        oldLast = last;
        return result;
    }

    private function getTextLength(Void):Number {
        return text.length;
    }

    private function getSubSequence(beginIndex:Number, endIndex:Number):String {
        return text.substring(beginIndex, endIndex);
    }

}
