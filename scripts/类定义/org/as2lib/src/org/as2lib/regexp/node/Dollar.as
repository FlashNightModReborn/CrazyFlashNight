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
 
import org.as2lib.regexp.node.Node; 
import org.as2lib.regexp.node.TreeInfo;

/**
 * {@code Dollar} is a node to anchor at the end of a line or the 
 * end of input based on the multiline mode.
 *
 * When not in multiline mode, the $ can only match at the very end
 * of the input, unless the input ends in a line terminator in which
 * it matches right before the last line terminator.
 *
 * Note that \r\n is considered an atomic line terminator.
 * 
 * Like ^ the $ operator matches at a position, it does not match the
 * line terminators themselves.
 * 
 * @author Igor Sadovskiy
 */

class org.as2lib.regexp.node.Dollar extends Node {
	
    private var multiline:Boolean;
    
    public function Dollar(mul:Boolean) {
        multiline = mul;
    }
    
    public function match(matcher:Object, i:Number, seq:String):Boolean {
        if (!multiline) {
            if (i < matcher.to - 2)
                return false;
            if (i == matcher.to - 2) {
                var ch:Number = seq.charCodeAt(i);
                if (ch != ord('\r')) return false;
                ch = seq.charCodeAt(i+1);
                if (ch != ord('\n')) return false;
            }
        }
        // Matches before any line terminator; also matches at the
        // end of input
        if (i < matcher.to) {
            var ch:Number = seq.charCodeAt(i);
             if (ch == ord('\n')) {
                 // No match between \r\n
                 if (i > 0 && seq.charAt(i-1) == '\r')
                     return false;
             } else if (ch == ord('\r') || ch == ord('\u0085') ||
                        (ch|1) == ord('\u2029')) {
                 // line terminator; match
             } else { // No line terminator, no match
                 return false;
             }
        }
        return next.match(matcher, i, seq);
    }
    
    public function study(info:TreeInfo):Boolean {
        next.study(info);
        return info.deterministic;
    }
}
