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
 * {@code UnixDollar} is a node to anchor at the end of a line or the end 
 * of input based on the multiline mode when in unix lines mode.
 * 
 * @author Igor Sadovskiy
 */
 
class org.as2lib.regexp.node.UnixDollar extends Node {
	
    private var multiline:Boolean;
    
    public function UnixDollar(mul:Boolean) {
        multiline = mul;
    }
    
    public function match(matcher:Object, i:Number, seq:String):Boolean {
        if (i < matcher.to) {
            var ch:Number = seq.charCodeAt(i);
            if (ch == ord('\n')) {
                // If not multiline, then only possible to
                // match at very end or one before end
                if (multiline == false && i != matcher.to - 1) return false;
            } else {
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
