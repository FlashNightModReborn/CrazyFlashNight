﻿/*
 * Copyright the original author or authors.
 * 
 * Licensed under the Mozilla Public License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.mozilla.org/MPL/2.0/
 *
 * This file may be redistributed under the terms of the GNU General Public License,
 * version 3.0 (GPLv3), or any later version.
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
 
import org.as2lib.regexp.AsciiUtil;
import org.as2lib.regexp.node.Node;
import org.as2lib.regexp.node.Range; 
import org.as2lib.regexp.node.NotRangeA;

/**
 * {@code RangeA} is a node class for matching characters within an explicit 
 * value range in a case insensitive manner.
 * 
 * @author Igor Sadovskiy
 */
 
class org.as2lib.regexp.node.RangeA extends Range {
	
    public function RangeA(n:Number) {
        lower = n >>> 16;
        upper = n & 0xFFFF;
    }
    
    public function dup(flag:Boolean):Node {
        return (flag) ?
            new NotRangeA((lower << 16) + upper) :
            new RangeA((lower << 16) + upper);
    }
    
    public function match(matcher:Object, i:Number, seq:String):Boolean {
        if (i < matcher.to) {
            var ch:Number = seq.charCodeAt(i);
            var m:Boolean = (((ch-lower)|(upper-ch)) >= 0);
            if (!m) {
                ch = AsciiUtil.toUpper(ch);
                m = (((ch-lower)|(upper-ch)) >= 0);
                if (!m) {
                    ch = AsciiUtil.toLower(ch);
                    m = (((ch-lower)|(upper-ch)) >= 0);
                }
            }
            return (m && next.match(matcher, i+1, seq));
        }
        return false;
    }
}

