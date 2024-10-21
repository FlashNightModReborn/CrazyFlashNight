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

import org.as2lib.core.BasicClass;

/**
 * {@code TreeInfo} is used to accumulate information about a subtree of the 
 * object graph so that optimizations can be applied to the subtree.
 * 
 * @author Igor Sadovskiy
 */               
        
class org.as2lib.regexp.node.TreeInfo extends BasicClass {
	
	public var minLength:Number;
	public var maxLength:Number;
	public var maxValid:Boolean;
	public var deterministic:Boolean;

    public function TreeInfo() {
        reset();
    }
    
    public function reset():Void {
        minLength = 0;
        maxLength = 0;
        maxValid = true;
        deterministic = true;
    }
 
}