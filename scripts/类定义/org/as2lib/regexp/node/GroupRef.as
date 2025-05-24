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
 
import org.as2lib.regexp.node.Node; 
import org.as2lib.regexp.node.GroupHead;
import org.as2lib.regexp.node.TreeInfo;

/**
 * {@code GroupRef}  is a recursive reference to a group in the regular 
 * expression. It calls matchRef because if the reference fails to match 
 * we would not unset the group.
 * 
 * @author Igor Sadovskiy
 */
 
class org.as2lib.regexp.node.GroupRef extends Node {
	
    private var head:GroupHead;
    
    public function GroupRef(head:GroupHead) {
        this.head = head;
    }
    
    public function match(matcher:Object, i:Number, seq:String):Boolean {
        return head.matchRef(matcher, i, seq)
            && next.match(matcher, matcher.last, seq);
    }
    
    public function study(info:TreeInfo):Boolean {
        info.maxValid = false;
        info.deterministic = false;
        return next.study(info);
    }
}

