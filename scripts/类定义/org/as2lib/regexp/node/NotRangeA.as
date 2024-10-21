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
import org.as2lib.regexp.node.NotRange;
import org.as2lib.regexp.node.RangeA;

/**
 * {@code NotRange} is a node class for matching characters without an 
 * explicit case independent value range.
 * 
 * @author Igor Sadovskiy
 */

class org.as2lib.regexp.node.NotRangeA extends NotRange {
	
    private var lower, upper:Number;
    
    public function NotRangeA(n:Number) {
        lower = n >>> 16;
        upper = n & 0xFFFF;
    }
    
    public function dup(flag:Boolean):Node {
        if (flag) {
            return new RangeA((lower << 16) + upper);
        } else {
            return new NotRangeA((lower << 16) + upper);
        }
    }
    
    public function match(matcher:Object, i:Number, seq:String):Boolean {
        if (i < matcher.to) {
            var ch:Number = seq.charCodeAt(i);
            var m:Boolean = (((ch-lower)|(upper-ch)) < 0);
            if (m) {
                ch = AsciiUtil.toUpper(ch);
                m = (((ch-lower)|(upper-ch)) < 0);
                if (m) {
                    ch = AsciiUtil.toLower(ch);
                    m = (((ch-lower)|(upper-ch)) < 0);
                }
            }

            return (m && next.match(matcher, i+1, seq));
        }
        return false;
    }
}

