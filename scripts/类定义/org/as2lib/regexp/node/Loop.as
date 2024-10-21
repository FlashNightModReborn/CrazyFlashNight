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
import org.as2lib.regexp.node.TreeInfo;

/**
 * {@code Loop} handles the repetition count for a greedy Curly. The 
 * matchInit is called from the Prolog to save the index of where the group
 * beginning is stored. A zero length group check occurs in the
 * normal match but is skipped in the matchInit.
 * 
 * @author Igor Sadovskiy
 */
 
class org.as2lib.regexp.node.Loop extends Node {
	
    private var body:Node;
    private var countIndex:Number; // local count index in matcher locals
    private var beginIndex:Number; // group begining index
    private var cmin, cmax:Number;
    
    public function Loop(countIndex:Number, beginIndex:Number) {
        this.countIndex = countIndex;
        this.beginIndex = beginIndex;
    }
    
    public function match(matcher:Object, i:Number, seq:String):Boolean {
        // Avoid infinite loop in zero-length case.
        if (i > matcher.locals[beginIndex]) {
            var count:Number = matcher.locals[countIndex];

            // This block is for before we reach the minimum
            // iterations required for the loop to match
            if (count < cmin) {
                matcher.locals[countIndex] = count + 1;
                var b:Boolean = body.match(matcher, i, seq);
                // If match failed we must backtrack, so
                // the loop count should NOT be incremented
                if (!b)
                    matcher.locals[countIndex] = count;
                // Return success or failure since we are under
                // minimum
                return b;
            }
            // This block is for after we have the minimum
            // iterations required for the loop to match
            if (count < cmax) {
                matcher.locals[countIndex] = count + 1;
                var b:Boolean = body.match(matcher, i, seq);
                // If match failed we must backtrack, so
                // the loop count should NOT be incremented
                if (!b)
                    matcher.locals[countIndex] = count;
                else
                    return true;
            }
        }
        return next.match(matcher, i, seq);
    }
    
    public function matchInit(matcher:Object, i:Number, seq:String):Boolean {
        var save:Number = matcher.locals[countIndex];
        var ret:Boolean = false;
        if (0 < cmin) {
            matcher.locals[countIndex] = 1;
            ret = body.match(matcher, i, seq);
        } else if (0 < cmax) {
            matcher.locals[countIndex] = 1;
            ret = body.match(matcher, i, seq);
            if (ret == false)
                ret = next.match(matcher, i, seq);
        } else {
            ret = next.match(matcher, i, seq);
        }
        matcher.locals[countIndex] = save;
        return ret;
    }
    
    public function study(info:TreeInfo):Boolean {
        info.maxValid = false;
        info.deterministic = false;
        return false;
    }
    
    public function getCmin(Void):Number {
    	return cmin;	
    }

    public function setCmin(cmin:Number):Void {
    	this.cmin = cmin;
    }
    
    public function getCmax(Void):Number {
    	return cmax;	
    }

    public function setCmax(cmax:Number):Void {
    	this.cmax = cmax;
    }
    
    public function getBody(Void):Node {
    	return body;
    }

    public function setBody(body:Node):Void {
    	this.body = body;
    }
    
}

