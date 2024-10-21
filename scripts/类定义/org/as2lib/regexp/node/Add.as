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
 * {@code Add} is an object added to the tree when a character class has 
 * an additional range added to it.
 * 
 * @author Igor Sadovskiy
 */

class org.as2lib.regexp.node.Add extends Node {
	
    private var lhs, rhs:Node;
    
    public function Add(lhs:Node, rhs:Node) {
        this.lhs = lhs;
        this.rhs = rhs;
    }
    
    public function match(matcher:Object, i:Number, seq:String):Boolean {
        if (i < matcher.to) {
        	return ((lhs.match(matcher, i, seq) || rhs.match(matcher, i, seq))
            	&& next.match(matcher, matcher.last, seq));
        }
        return false;
    }
    
    public function study(info:TreeInfo):Boolean {
        var maxV:Boolean = info.maxValid;
        var detm:Boolean = info.deterministic;

        var minL:Number = info.minLength;
        var maxL:Number = info.maxLength;
        lhs.study(info);

        var minL2:Number = info.minLength;
        var maxL2:Number = info.maxLength;

        info.minLength = minL;
        info.maxLength = maxL;
        rhs.study(info);

        info.minLength = Math.min(minL2, info.minLength);
        info.maxLength = Math.max(maxL2, info.maxLength);
        info.maxValid = maxV;
        info.deterministic = detm;

        return next.study(info);
    }
}

