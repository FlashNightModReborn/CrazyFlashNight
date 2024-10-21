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
import org.as2lib.regexp.node.NotPosix;
import org.as2lib.regexp.node.TreeInfo;
 
/**
 * {@code Posix} is a node class that matches a POSIX type.
 * 
 * @author Igor Sadovskiy
 */
  
class org.as2lib.regexp.node.Posix extends Node {
	
    private var ctype:Number;
    
    public function Posix(type:Number) {
        ctype = type;
    }
    
    public function dup(flag:Boolean):Node {
        return ((flag) ? new NotPosix(ctype) : new Posix(ctype));
    }
    
    public function match(matcher:Object, i:Number, seq:String):Boolean {
        return (i < matcher.to
            && AsciiUtil.isType(seq.charCodeAt(i), ctype)
            && next.match(matcher, i+1, seq));
    }
    
    public function study(info:TreeInfo):Boolean {
        info.minLength++;
        info.maxLength++;
        return next.study(info);
    }
}

