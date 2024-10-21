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
 * {@code UnixDot} is a node class for the dot metacharacter when dotall is 
 * not enabled but UNIX_LINES is enabled.
 * 
 * @author Igor Sadovskiy
 */
 
class org.as2lib.regexp.node.UnixDot extends Node {
	
    public function UnixDot() {
        super();
    }
    
    public function match(matcher:Object, i:Number, seq:String):Boolean {
        if (i < matcher.to) {
            var ch:Number = seq.charCodeAt(i);
            return (ch != ord('\n') && next.match(matcher, i+1, seq));
        }
        return false;
    }
    
    public function study(info:TreeInfo):Boolean {
        info.minLength++;
        info.maxLength++;
        return next.study(info);
    }
}

