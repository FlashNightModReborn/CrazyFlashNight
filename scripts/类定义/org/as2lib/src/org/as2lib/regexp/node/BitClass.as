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
import org.as2lib.regexp.Pattern;
import org.as2lib.regexp.node.Node;
import org.as2lib.regexp.node.TreeInfo;

/**
 *  {@code BitClass} creates a bit vector for matching ASCII values.
 *  
 *  @author Igor Sadovskiy
 */
 
class org.as2lib.regexp.node.BitClass extends Node {
	
    private var bits:Array; 
    private var complementMe:Boolean;
    
    public function BitClass(flag:Boolean, newBits:Array) {
    	complementMe = (flag != null) ? flag : false; 
    	bits = (newBits != null) ? newBits : new Array(256);
    }
    
    public function addChar(c:Number, f:Number):Node {
        if ((f & Pattern.CASE_INSENSITIVE) == 0) {
            bits[c] = true;
            return this;
        }
        if (c < 128) {
            bits[c] = true;
            if (AsciiUtil.isUpper(c)) {
                c += 0x20;
                bits[c] = true;
            } else if (AsciiUtil.isLower(c)) {
                c -= 0x20;
                bits[c] = true;
            }
            return this;
        }
        c = AsciiUtil.toLower(c);
        bits[c] = true;
        c = AsciiUtil.toUpper(c);
        bits[c] = true;
        return this;
    }
    
    public function dup(flag:Boolean):Node {
        return new BitClass(flag, bits);
    }
    
    public function match(matcher:Object, i:Number, seq:String):Boolean {
        if (i >= matcher.to) return false;
        var c:Number = seq.charCodeAt(i);
        var charMatches:Boolean = (c > 255) ? 
        	complementMe : Boolean(Number(bits[c]) ^ Number(complementMe));
        return charMatches && next.match(matcher, i+1, seq);
    }
    
    public function study(info:TreeInfo):Boolean {
        info.minLength++;
        info.maxLength++;
        return next.study(info);
    }
}
