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

import org.as2lib.regexp.AsciiUtil;
import org.as2lib.regexp.node.Node; 

/**
 * {@code Bound} handles word boundaries. Includes a field to allow this 
 * one class to deal with the different types of word boundaries we can 
 * match. The word characters include underscores, letters, and digits.
 * 
 * @author Igor Sadovskiy
 */
 
class org.as2lib.regexp.node.Bound extends Node {
	
    public static var LEFT:Number = 0x1;
    public static var RIGHT:Number= 0x2;
    public static var BOTH:Number = 0x3;
    public static var NONE:Number = 0x4;
    
    private var type:Number;
    
    public function Bound(n:Number) {
        type = n;
    }
    
    public function check(matcher:Object, i:Number, seq:String):Number {
        var ch:Number;
        var left:Boolean = false;
        if (i > matcher.from) {
            ch = seq.charCodeAt(i-1);
            left = (ch == 0x5F || AsciiUtil.isLower(ch) || AsciiUtil.isDigit(ch));
        }
        var right:Boolean = false;
        if (i < matcher.to) {
            ch = seq.charCodeAt(i);
            right = (ch == 0x5F || AsciiUtil.isLower(ch) || AsciiUtil.isDigit(ch));
        }
        return ((Number(left) ^ Number(right)) ? (right ? LEFT : RIGHT) : NONE);
    }
    
    public function match(matcher:Object, i:Number, seq:String):Boolean {
        return (check(matcher, i, seq) & type) > 0
            && next.match(matcher, i, seq);
    }
    
}

