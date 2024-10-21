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
 
import org.as2lib.regexp.Pattern;
import org.as2lib.regexp.node.Node; 
import org.as2lib.regexp.node.TreeInfo;

/**
 * {@code GroupCurly} handles the curly-brace style repetition with a 
 * specified minimum and maximum occurrences in deterministic cases. 
 * 
 * This is an iterative optimization over the Prolog and Loop system 
 * which would handle this in a recursive way. The * quantifier is 
 * handled as a special case. This class saves group settings so that 
 * the groups are unset when backing off of a group match.
 * 
 * @author Igor Sadovskiy
 */
 
class org.as2lib.regexp.node.GroupCurly extends Node {
	
    private var atom:Node;
    private var type:Number;
    private var cmin:Number;
    private var cmax:Number;
    private var localIndex:Number;
    private var groupIndex:Number;

    public function GroupCurly(node:Node, cmin:Number, cmax:Number, type:Number, local:Number, group:Number) {
        this.atom = node;
        this.type = type;
        this.cmin = cmin;
        this.cmax = cmax;
        this.localIndex = local;
        this.groupIndex = group;
    }
    
    public function match(matcher:Object, i:Number, seq:String):Boolean {
        var groups:Array = matcher.groups; // of Number
        var locals:Array = matcher.locals; // of Number
        var save0:Number = locals[localIndex];
        var save1:Number = groups[groupIndex];
        var save2:Number = groups[groupIndex+1];

        // Notify GroupTail there is no need to setup group info
        // because it will be set here
        locals[localIndex] = -1;

        var ret:Boolean = true;
        for (var j:Number = 0; j < cmin; j++) {
            if (atom.match(matcher, i, seq)) {
                groups[groupIndex] = i;
                groups[groupIndex+1] = i = matcher.last;
            } else {
                ret = false;
                break;
            }
        }
        if (!ret) {
            ;
        } else if (type == Pattern.GREEDY) {
            ret = match0(matcher, i, cmin, seq);
        } else if (type == Pattern.LAZY) {
            ret = match1(matcher, i, cmin, seq);
        } else {
            ret = match2(matcher, i, cmin, seq);
        }
        if (!ret) {
            locals[localIndex] = save0;
            groups[groupIndex] = save1;
            groups[groupIndex+1] = save2;
        }
        return ret;
    }
    
    // Aggressive group match
    private function match0(matcher:Object, i:Number, j:Number, seq:String):Boolean {
        var groups:Array = matcher.groups; // of Number
        var save0:Number = groups[groupIndex];
        var save1:Number = groups[groupIndex+1];
        while (true) {
            if (j >= cmax)
                break;
            if (!atom.match(matcher, i, seq))
                break;
            var k:Number = matcher.last - i;
            if (k <= 0) {
                groups[groupIndex] = i;
                groups[groupIndex+1] = i = i + k;
                break;
            }
            while (true) {
                groups[groupIndex] = i;
                groups[groupIndex+1] = i = i + k;
                if (++j >= cmax)
                    break;
                if (!atom.match(matcher, i, seq))
                    break;
                if (i + k != matcher.last) {
                    if (match0(matcher, i, j, seq))
                        return true;
                    break;
                }
            }
            while (j > cmin) {
                if (next.match(matcher, i, seq)) {
                    groups[groupIndex+1] = i;
                    groups[groupIndex] = i = i - k;
                    return true;
                }
                // backing off
                groups[groupIndex+1] = i;
                groups[groupIndex] = i = i - k;
                j--;
            }
            break;
        }
        groups[groupIndex] = save0;
        groups[groupIndex+1] = save1;
        return next.match(matcher, i, seq);
    }
    
    // Reluctant matching
    private function match1(matcher:Object, i:Number, j:Number, seq:String):Boolean {
        for (;;) {
            if (next.match(matcher, i, seq))
                return true;
            if (j >= cmax)
                return false;
            if (!atom.match(matcher, i, seq))
                return false;
            if (i == matcher.last)
                return false;

            matcher.groups[groupIndex] = i;
            matcher.groups[groupIndex+1] = i = matcher.last;
            j++;
        }
    }
    // Possessive matching
    private function match2(matcher:Object, i:Number, j:Number, seq:String):Boolean {
        for (; j < cmax; j++) {
            if (!atom.match(matcher, i, seq)) {
                break;
            }
            matcher.groups[groupIndex] = i;
            matcher.groups[groupIndex+1] = matcher.last;
            if (i == matcher.last) {
                break;
            }
            i = matcher.last;
        }
        return next.match(matcher, i, seq);
    }
    
    public function study(info:TreeInfo):Boolean {
        // Save original info
        var minL:Number = info.minLength;
        var maxL:Number = info.maxLength;
        var maxV:Boolean = info.maxValid;
        var detm:Boolean = info.deterministic;
        info.reset();

        atom.study(info);

        var temp:Number = info.minLength * cmin + minL;
        if (temp < minL) {
            temp = 0xFFFFFFF; // Arbitrary large number
        }
        info.minLength = temp;

        if (maxV && info.maxValid) {
            temp = info.maxLength * cmax + maxL;
            info.maxLength = temp;
            if (temp < maxL) {
                info.maxValid = false;
            }
        } else {
            info.maxValid = false;
        }

        if (info.deterministic && cmin == cmax) {
            info.deterministic = detm;
        } else {
            info.deterministic = false;
        }

        return next.study(info);
    }
}

