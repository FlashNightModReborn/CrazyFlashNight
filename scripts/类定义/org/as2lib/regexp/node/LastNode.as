/*
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

import org.as2lib.regexp.Matcher;
import org.as2lib.regexp.node.Node; 

class org.as2lib.regexp.node.LastNode extends Node {

    public function match(matcher:Object, i:Number, seq:String):Boolean {
        if (matcher.acceptMode == Matcher.ENDANCHOR && i != matcher.to) return false;
        matcher.last = i;
        matcher.groups[0] = matcher.first;
        matcher.groups[1] = matcher.last;
        return true;
    }
}
