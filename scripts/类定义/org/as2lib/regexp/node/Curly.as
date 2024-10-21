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
import org.as2lib.regexp.node.Node; 
import org.as2lib.regexp.node.TreeInfo;

/**
 * {@code Curly} class handles the curly-brace style repetition with a 
 * specified minimum and maximum occurrences. The * quantifier is handled 
 * as a special case. This class handles the three types.
 * 
 * @author Igor Sadovskiy
 */
 
class org.as2lib.regexp.node.Curly extends Node {
	
    private var atom:Node;
    private var type:Number;
    private var cmin:Number;
    private var cmax:Number;

    public function Curly(node:Node, cmin:Number, cmax:Number, type:Number) {
        this.atom = node;
        this.type = type;
        this.cmin = cmin;
        this.cmax = cmax;
    }
    
    public function match(matcher:Object, i:Number, seq:String):Boolean {
        var j:Number;
        for (j = 0; j < cmin; j++) {
            if (atom.match(matcher, i, seq)) {
                i = matcher.last;
                continue;
            }
            return false;
        }
        if (type == Pattern.GREEDY)
            return match0(matcher, i, j, seq);
        else if (type == Pattern.LAZY)
            return match1(matcher, i, j, seq);
        else
            return match2(matcher, i, j, seq);
    }
    
    // Greedy match.
    // i is the index to start matching at
    // j is the number of atoms that have matched
    private function match0(matcher:Object, i:Number, j:Number, seq:String):Boolean {
        if (j >= cmax) {
            // We have matched the maximum... continue with the rest of
            // the regular expression
            return next.match(matcher, i, seq);
        }
        var backLimit:Number = j;
        while (atom.match(matcher, i, seq)) {
            // k is the length of this match
            var k:Number = matcher.last - i;
            
            // Zero length match
            if (k == 0) break;
            
            // Move up index and number matched
            i = matcher.last;
            j++;
            
            // We are greedy so match as many as we can
            while (j < cmax) {
                if (!atom.match(matcher, i, seq)) break;
                if (i + k != matcher.last) {
                    if (match0(matcher, matcher.last, j+1, seq)) return true;
                    break;
                }
                i += k;
                j++;
            }
            
            // Handle backing off if match fails
            while (j >= backLimit) {
               if (next.match(matcher, i, seq))
                    return true;
                i -= k;
                j--;
            }
            return false;
        }
        return next.match(matcher, i, seq);
    }
    
    // Reluctant match. At this point, the minimum has been satisfied.
    // i is the index to start matching at
    // j is the number of atoms that have matched
    private function match1(matcher:Object, i:Number, j:Number, seq:String):Boolean {
        while (true) {
            // Try finishing match without consuming any more
            if (next.match(matcher, i, seq))
                return true;
            // At the maximum, no match found
            if (j >= cmax)
                return false;
            // Okay, must try one more atom
            if (!atom.match(matcher, i, seq))
                return false;
            // If we haven't moved forward then must break out
            if (i == matcher.last)
                return false;
            // Move up index and number matched
            i = matcher.last;
            j++;
        }
    }
    
    private function match2(matcher:Object, i:Number, j:Number, seq:String):Boolean {
        for (; j < cmax; j++) {
            if (!atom.match(matcher, i, seq)) 
            	break;
            if (i == matcher.last) 
            	break;
            i = matcher.last;
        }
        return next.match(matcher, i, seq);
    }
    
    public function study(info:TreeInfo):Boolean {
        // Save original info
        var minL:Number = info.minLength;
        var maxL:Number = info.maxLength;
        var maxV:Boolean = info.maxValid;
        var detm:Boolean = info.deterministic;
        info.reset();

        atom.study(info);

        var temp:Number = info.minLength * cmin + minL;
        if (temp < minL) {
            temp = 0xFFFFFFF; // arbitrary large number
        }
        info.minLength = temp;

        if (maxV && info.maxValid) {
            temp = info.maxLength * cmax + maxL;
            info.maxLength = temp;
            if (temp < maxL) {
                info.maxValid = false;
            }
        } else {
            info.maxValid = false;
        }

        if (info.deterministic && cmin == cmax)
            info.deterministic = detm;
        else
            info.deterministic = false;

        return next.study(info);
    }
    
    public function getType(Void):Number {
    	return type;
    }

    public function getAtom(Void):Node {
    	return atom;
    }
    
    public function getCmin(Void):Number {
    	return cmin;
    }
    
    public function getCmax(Void):Number {
    	return cmax;
    }
    
}

