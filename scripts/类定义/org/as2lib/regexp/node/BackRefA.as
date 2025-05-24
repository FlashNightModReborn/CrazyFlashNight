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
 * {@code BackRefA} refers to a group in the regular expression 
 * using IGNORE CASE flag. 
 * Attempts to match whatever the group referred to last matched.
 * 
 * @author Igor Sadovskiy
 */

class org.as2lib.regexp.node.BackRefA extends Node {
	
    private var groupIndex:Number;
    
    public function BackRefA(groupCount:Number) {
        super();
        groupIndex = groupCount + groupCount;
    }
    
    public function match(matcher:Object, i:Number, seq:String):Boolean {
        var j:Number = matcher.groups[groupIndex];
        var k:Number = matcher.groups[groupIndex+1];

        var groupSize:Number = k - j;

        // If the referenced group didn't match, neither can this
        if (j < 0) return false;

        // If there isn't enough input left no match
        if (i + groupSize > matcher.to) return false;

        // Check each new char to make sure it matches what the group
        // referenced matched last time around
        for (var index=0; index<groupSize; index++) {
            var c1:Number = seq.charCodeAt(i+index);
            var c2:Number = seq.charCodeAt(j+index);
            if (c1 != c2) {
                c1 = AsciiUtil.toUpper(c1);
                c2 = AsciiUtil.toUpper(c2);
                if (c1 != c2) {
                    c1 = AsciiUtil.toLower(c1);
                    c2 = AsciiUtil.toLower(c2);
                    if (c1 != c2) return false;
                }
            }
        }

        return next.match(matcher, i+groupSize, seq);
    }
    
    public function study(info:TreeInfo):Boolean {
        info.maxValid = false;
        return next.study(info);
    }
}

