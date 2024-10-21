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
import org.as2lib.regexp.node.Not;
import org.as2lib.regexp.node.TreeInfo;

class org.as2lib.regexp.node.Specials extends Node {
	
    public function Specials() {
    }
    
    public function dup(flag:Boolean):Node {
        return (flag) ? new Not(this) : new Specials();
    }
    
    public function match(matcher:Object, i:Number, seq:String):Boolean {
        if (i < matcher.to) {
            var ch:Number = seq.charCodeAt(i);;
            return (((ch-0xFFF0) | (0xFFFD-ch)) >= 0 || ch == 0xFEFF)
                && next.match(matcher, i+1, seq);
        }
        return false;
    }
    
    public function study(info:TreeInfo):Boolean {
        info.minLength++;
        info.maxLength++;
        return next.study(info);
    }
}

