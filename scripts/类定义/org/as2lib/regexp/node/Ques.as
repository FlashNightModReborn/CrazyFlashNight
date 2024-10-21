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
 * {@code Ques} is a node to anchor "?" character. It handles all three
 * kinds of its use.
 * 
 * @author Igor Sadovskiy
 */
 
class org.as2lib.regexp.node.Ques extends Node {
	
    private var atom:Node;
    private var type:Number;
    
    public function Ques(node:Node, type:Number) {
        this.atom = node;
        this.type = type;
    }
    
    public function match(matcher:Object, i:Number, seq:String):Boolean {
        switch (type) {
        case Pattern.GREEDY:
            return (atom.match(matcher, i, seq) && next.match(matcher, matcher.last, seq))
                || next.match(matcher, i, seq);
        case Pattern.LAZY:
            return next.match(matcher, i, seq)
                || (atom.match(matcher, i, seq) && next.match(matcher, matcher.last, seq));
        case Pattern.POSSESSIVE:
            if (atom.match(matcher, i, seq)) i = matcher.last;
            return next.match(matcher, i, seq);
        default:
            return atom.match(matcher, i, seq) && next.match(matcher, matcher.last, seq);
        }
    }
    
    public function study(info:TreeInfo):Boolean {
        if (type != Pattern.INDEPENDENT) {
            var minL:Number = info.minLength;
            atom.study(info);
            info.minLength = minL;
            info.deterministic = false;
            return next.study(info);
        } else {
            atom.study(info);
            return next.study(info);
        }
    }
    
    public function getType(Void):Number {
    	return type;	
    }
}

