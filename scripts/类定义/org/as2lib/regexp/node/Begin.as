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

import org.as2lib.regexp.node.Node;

/**
 * {@code Begin} as a node to anchor at the beginning of input. 
 * This object implements the match for a "\A" sequence, and the 
 * caret anchor will use this if not in multiline mode.
 * 
 * @author Igor Sadovskiy
 */
 
class org.as2lib.regexp.node.Begin extends Node {
	
    public function match(matcher:Object, i:Number, seq:String):Boolean {
        if (i == matcher.from && next.match(matcher, i, seq)) {
            matcher.first = i;
            matcher.groups[0] = i;
            matcher.groups[1] = matcher.last;
            return true;
        } else {
            return false;
        }
    }
}
