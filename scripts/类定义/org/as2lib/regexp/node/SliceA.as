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
import org.as2lib.regexp.node.TreeInfo;

/**
 * {@code SliceA} is a node class for a sequence of case independent 
 * literal characters.
 * 
 * @author Igor Sadovskiy
 */
 
class org.as2lib.regexp.node.SliceA extends Node {
	
    private var buffer:Array;
    
    public function SliceA(buf:Array) {
        buffer = buf;
    }
    
    public function match(matcher:Object, i:Number, seq:String):Boolean {
        var buf:Array = buffer;
        var len:Number = buf.length;
        if (i + len > matcher.to) return false;

        for (var j:Number = 0; j < len; j++) {
            var c:Number = AsciiUtil.toLower(seq.charCodeAt(i+j));
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

