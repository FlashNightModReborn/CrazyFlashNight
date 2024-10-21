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
import org.as2lib.regexp.node.TreeInfo;
 
/**
 * {@code SliceU} is a node class for a sequence of case independent 
 * unicode characters.
 * 
 * @author Igor Sadovskiy
 */
 
class org.as2lib.regexp.node.SliceU extends Node {
	
    private var buffer:Array; 
    
    public function SliceU(buf:Array) {
        buffer = buf;
    }
    
    public function match(matcher:Object, i:Number, seq:String):Boolean {
        var buf:Array = buffer;
        var len:Number = buf.length;
        if (i + len > matcher.to) return false;
        
        for (var j:Number = 0; j < len; j++) {
            var c:Number = seq.charCodeAt(i+j);
            c = AsciiUtil.toUpper(c);
            c = AsciiUtil.toLower(c);
            if (buf[j] != c) return false;
        }
        
        return next.match(matcher, i+len, seq);
    }
    
    public function study(info:TreeInfo):Boolean {
        info.minLength += buffer.length;
        info.maxLength += buffer.length;
        return next.study(info);
    }
}

