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
import org.as2lib.regexp.node.BnM;
import org.as2lib.regexp.node.TreeInfo;

/**
 * {@code First} searches until the next instance of its atom. This is 
 * useful for finding the atom efficiently without passing an instance of it
 * (greedy problem) and without a lot of wasted search time (reluctant
 * problem).
 * 
 * @author Igor Sadovskiy
 */
 
class org.as2lib.regexp.node.First extends Node {
	
    private var atom:Node;
    
    public function First(node:Node) {
        this.atom = BnM.optimize(node);
    }
    
    public function match(matcher:Object, i:Number, seq:String):Boolean {
        if (atom instanceof BnM) {
            return atom.match(matcher, i, seq)
                && next.match(matcher, matcher.last, seq);
        }
        while (true) {
            if (i > matcher.to) {
                return false;
            }
            if (atom.match(matcher, i, seq)) {
                return next.match(matcher, matcher.last, seq);
            }
            i++;
            matcher.first++;
        }
    }
    
    public function study(info:TreeInfo):Boolean {
        atom.study(info);
        info.maxValid = false;
        info.deterministic = false;
        return next.study(info);
    }
}

