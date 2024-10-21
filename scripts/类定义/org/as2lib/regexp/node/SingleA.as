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
import org.as2lib.regexp.node.NotSingleA;
import org.as2lib.regexp.node.TreeInfo;

/**
 * {@code SingleA} is a node class for a single case independent character 
 * value.
 * 
 * @author Igor Sadovskiy
 */
 
class org.as2lib.regexp.node.SingleA extends Node {
	
    private var ch:Number;
    
    public function SingleA(n:Number) {
        ch = AsciiUtil.toLower(n);
    }
    
    public function dup(flag:Boolean):Node {
        return (flag) ? new NotSingleA(ch) : new SingleA(ch);
    }
    
    public function match(matcher:Object, i:Number, seq:String):Boolean {
        if (i < matcher.to) {
            var c:Number = seq.charCodeAt(i);
            if (c == ch || AsciiUtil.toLower(c) == ch) {
                return next.match(matcher, i+1, seq);
            }
        }
        return false;
    }

    public function study(info:TreeInfo):Boolean {
        info.minLength++;
        info.maxLength++;
        return next.study(info);
    }
}
