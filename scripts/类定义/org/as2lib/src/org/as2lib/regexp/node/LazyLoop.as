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
 
import org.as2lib.regexp.node.Loop; 
import org.as2lib.regexp.node.TreeInfo;

/**
 * {@code LazyLoop} handles the repetition count for a reluctant Curly. 
 * The matchInit is called from the Prolog to save the index of where 
 * the group beginning is stored. A zero length group check occurs in the
 * normal match but is skipped in the matchInit.
 * 
 * @author Igor Sadovskiy
 */
 
class org.as2lib.regexp.node.LazyLoop extends Loop {
	
    public function LazyLoop(countIndex:Number, beginIndex:Number) {
        super(countIndex, beginIndex);
    }
    
    public function match(matcher:Object, i:Number, seq:String):Boolean {
        // Check for zero length group
        if (i > matcher.locals[beginIndex]) {
            var count:Number = matcher.locals[countIndex];
            if (count < cmin) {
                matcher.locals[countIndex] = count + 1;
                var result:Boolean = body.match(matcher, i, seq);
                // If match failed we must backtrack, so
                // the loop count should NOT be incremented
                if (!result)
                    matcher.locals[countIndex] = count;
                return result;
            }
            if (next.match(matcher, i, seq))
                return true;
            if (count < cmax) {
                matcher.locals[countIndex] = count + 1;
                var result:Boolean = body.match(matcher, i, seq);
                // If match failed we must backtrack, so
                // the loop count should NOT be incremented
                if (!result)
                    matcher.locals[countIndex] = count;
                return result;
            }
            return false;
        }
        return next.match(matcher, i, seq);
    }
    
    public function matchInit(matcher:Object, i:Number, seq:String):Boolean {
        var save:Number = matcher.locals[countIndex];
        var ret:Boolean = false;
        if (0 < cmin) {
            matcher.locals[countIndex] = 1;
            ret = body.match(matcher, i, seq);
        } else if (next.match(matcher, i, seq)) {
            ret = true;
        } else if (0 < cmax) {
            matcher.locals[countIndex] = 1;
            ret = body.match(matcher, i, seq);
        }
        matcher.locals[countIndex] = save;
        return ret;
    }
    
    public function study(info:TreeInfo):Boolean {
        info.maxValid = false;
        info.deterministic = false;
        return false;
    }
}

