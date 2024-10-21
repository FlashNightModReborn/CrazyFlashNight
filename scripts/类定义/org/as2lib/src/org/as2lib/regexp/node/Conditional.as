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
 * {@code Conditional} is a node class that matches a Condition category.
 * 
 * @author Igor Sadovskiy
 */

class org.as2lib.regexp.node.Conditional extends Node {
	
    private var cond, yes, nope:Node;
    
    public function Conditional(cond:Node, yes:Node, nope:Node) {
        this.cond = cond;
        this.yes = yes;
        this.nope = nope;
    }
    
    public function match(matcher:Object, i:Number, seq:String):Boolean {
        if (cond.match(matcher, i, seq)) {
            return yes.match(matcher, i, seq);
        } else {
            return nope.match(matcher, i, seq);
        }
    }
    
    public function study(info:TreeInfo):Boolean {
        var minL:Number = info.minLength;
        var maxL:Number = info.maxLength;
        var maxV:Boolean = info.maxValid;
        info.reset();
        yes.study(info);

        var minL2:Number = info.minLength;
        var maxL2:Number = info.maxLength;
        var maxV2:Boolean = info.maxValid;
        info.reset();
        nope.study(info);

        info.minLength = minL + Math.min(minL2, info.minLength);
        info.maxLength = maxL + Math.max(maxL2, info.maxLength);
        info.maxValid = (maxV && maxV2 && info.maxValid);
        info.deterministic = false;
        return next.study(info);
    }
}

