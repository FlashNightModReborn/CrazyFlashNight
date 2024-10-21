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
 * {@code GroupHead} saves the location where the group begins in the 
 * locals and restores them when the match is done.
 *
 * The matchRef is used when a reference to this group is accessed later
 * in the expression. The locals will have a negative value in them to
 * indicate that we do not want to unset the group if the reference
 * doesn't match.
 * 
 * @author Igor Sadovskiy
 */
 
class org.as2lib.regexp.node.GroupHead extends Node {
	
    private var localIndex:Number;
    
    public function GroupHead(localCount:Number) {
        localIndex = localCount;
    }
    
    public function match(matcher:Object, i:Number, seq:String):Boolean {
        var save:Number = matcher.locals[localIndex];
        matcher.locals[localIndex] = i;
        var ret:Boolean = next.match(matcher, i, seq);
        matcher.locals[localIndex] = save;
        return ret;
    }
    
    public function matchRef(matcher:Object, i:Number, seq:String):Boolean {
        var save:Number = matcher.locals[localIndex];
        matcher.locals[localIndex] = ~i; 
        var ret:Boolean = next.match(matcher, i, seq);
        matcher.locals[localIndex] = save;
        return ret;
    }
    
    public function getLocalIndex(Void):Number {
    	return localIndex;
    }
}

