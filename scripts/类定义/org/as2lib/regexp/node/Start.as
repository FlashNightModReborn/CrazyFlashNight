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
 * {@code Start} is used for REs that can start anywhere within the input 
 * string. This basically tries to match repeatedly at each spot in the
 * input string, moving forward after each try. An anchored search
 * or a BnM will bypass this node completely.
 * 
 * @author Igor Sadovskiy
 */

class org.as2lib.regexp.node.Start extends Node {
	
    private var minLength:Number;
    
    public function Start(node:Node) {
        this.next = node;
        var info:TreeInfo = new TreeInfo();
        next.study(info);
        minLength = info.minLength;
    }
    
    public function match(matcher:Object, i:Number, seq:String):Boolean {
        if (i > matcher.to - minLength) return false;
        var ret:Boolean = false;
        var guard:Number = matcher.to - minLength;
        
        for (; i <= guard; i++) {
            if (ret = next.match(matcher, i, seq)) break;
        }
        
        if (ret) {
            matcher.first = i;
            matcher.groups[0] = matcher.first;
            matcher.groups[1] = matcher.last;
        }
        return ret;
    }
    
    public function study(info:TreeInfo):Boolean {
        next.study(info);
        info.maxValid = false;
        info.deterministic = false;
        return false;
    }
}
