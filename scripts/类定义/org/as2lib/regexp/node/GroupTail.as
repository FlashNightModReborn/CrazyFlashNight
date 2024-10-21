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

/**
 * {@code GroupTail} handles the setting of group beginning and ending
 * locations when groups are successfully matched. It must also be able to
 * unset groups that have to be backed off of.
 *
 * The {@code GroupTail} node is also used when a previous group is referenced,
 * and in that case no group information needs to be set.
 * 
 * @author Igor Sadovskiy
 */
 
class org.as2lib.regexp.node.GroupTail extends Node {
	
    private var localIndex:Number;
    private var groupIndex:Number;
    
    public function GroupTail(localCount:Number, groupCount:Number) {
        localIndex = localCount;
        groupIndex = groupCount + groupCount;
    }
    
    public function match(matcher:Object, i:Number, seq:String):Boolean {
        var tmp:Number = matcher.locals[localIndex];
        if (tmp >= 0) { // This is the normal group case.
            // Save the group so we can unset it if it
            // backs off of a match.
            var groupStart:Number = matcher.groups[groupIndex];
            var groupEnd:Number = matcher.groups[groupIndex+1];

            matcher.groups[groupIndex] = tmp;
            matcher.groups[groupIndex+1] = i;
            if (next.match(matcher, i, seq)) {
                return true;
            }
            matcher.groups[groupIndex] = groupStart;
            matcher.groups[groupIndex+1] = groupEnd;
            return false;
        } else {
            // This is a group reference case. We don't need to save any
            // group info because it isn't really a group.
            matcher.last = i;
            return true;
        }
    }
    
    public function getLocalIndex(Void):Number {
    	return localIndex;
    }
    
    public function getGroupIndex(Void):Number {
    	return groupIndex;
    }    
}

