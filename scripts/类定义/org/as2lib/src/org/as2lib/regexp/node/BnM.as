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
import org.as2lib.regexp.node.Slice;
import org.as2lib.regexp.node.TreeInfo;
 
/**
 * {@code BnM} attempts to match a slice in the input using the Boyer-Moore 
 * string matching algorithm. The algorithm is based on the idea that the
 * pattern can be shifted farther ahead in the search text if it is
 * matched right to left.
 * 
 * The pattern is compared to the input one character at a time, from
 * the rightmost character in the pattern to the left. If the characters
 * all match the pattern has been found. If a character does not match,
 * the pattern is shifted right a distance that is the maximum of two
 * functions, the bad character shift and the good suffix shift. This
 * shift moves the attempted match position through the input more
 * quickly than a naive one postion at a time check.
 * 
 * The bad character shift is based on the character from the text that
 * did not match. If the character does not appear in the pattern, the
 * pattern can be shifted completely beyond the bad character. If the
 * character does occur in the pattern, the pattern can be shifted to
 * line the pattern up with the next occurrence of that character.
 * 
 * The good suffix shift is based on the idea that some subset on the right
 * side of the pattern has matched. When a bad character is found, the
 * pattern can be shifted right by the pattern length if the subset does
 * not occur again in pattern, or by the amount of distance to the
 * next occurrence of the subset in the pattern.
 *
 * @author Igor Sadovskiy
 */
 
class org.as2lib.regexp.node.BnM extends Node {
	
    private var buffer:Array; 
    private var lastOcc:Array;
    private var optoSft:Array;

    public static function optimize(node:Node):Node {
        if (!(node instanceof Slice)) return node;
        
        var src:Array = Slice(node).getBuffer(); 
        var patternLength:Number = src.length;
        
        // The BM algorithm requires a bit of overhead;
        // If the pattern is short don't use it, since
        // a shift larger than the pattern length cannot
        // be used anyway.
        if (patternLength < 4) return node;
        
        var i, j:Number;
        var lastOcc:Array = Array(128); 
        var optoSft:Array = Array(patternLength);
        
        // Precalculate part of the bad character shift
        // It is a table for where in the pattern each
        // lower 7-bit value occurs
        for (i = 0; i < patternLength; i++) {
            lastOcc[src[i] & 0x7F] = i + 1;
        }
        
        // Precalculate the good suffix shift
        // i is the shift amount being considered
		for (i = patternLength; i > 0; i--) {
            // j is the beginning index of suffix being considered
            var f:Boolean = false;
	        for (j = patternLength - 1; j >= i; j--) {
	            // Testing for good suffix
	            if (src[j] == src[j-i]) {
	                // src[j..len] is a good suffix
	                optoSft[j-1] = i;
	            } else {
	                // No match. The array has already been
	                // filled up with correct values before.
	                f = true;
	                break;
	            }
	        }
	        if (f) continue;
	        // This fills up the remaining of optoSft
	        // any suffix can not have larger shift amount
	        // then its sub-suffix. Why???
	        while (j > 0) {
	            optoSft[--j] = i;
	        }
        }
        // Set the guard value because of unicode compression
        optoSft[patternLength-1] = 1;
        return new BnM(src, lastOcc, optoSft, node.next);
    }
    
    public function BnM(src:Array, lastOcc:Array, optoSft:Array, next:Node) {
        this.buffer = src;
        this.lastOcc = lastOcc;
        this.optoSft = optoSft;
        this.next = next;
    }
    
    public function match(matcher:Object, i:Number, seq:String):Boolean {
        var src:Array = buffer; // of char
        var patternLength:Number = src.length;
        var last:Number = matcher.to - patternLength;

        // Loop over all possible match positions in text
		while (i <= last) {
            // Loop over pattern from right to left
            var f:Boolean = false;
            for (var j = patternLength - 1; j >= 0; j--) {
                var ch:Number = seq.charCodeAt(i+j);
                if (src[j] != ch) {
                    // Shift search to the right by the maximum of the
                    // bad character shift and the good suffix shift
                    i += Math.max(j + 1 - lastOcc[ch&0x7F], optoSft[j]);
                    f = true;
                    break;
                }
            }
            if (f) continue;
            // Entire pattern matched starting at i
            matcher.first = i;
            var ret:Boolean = next.match(matcher, i + patternLength, seq);
            if (ret) {
                matcher.first = i;
                matcher.groups[0] = matcher.first;
                matcher.groups[1] = matcher.last;
                return true;
            }
            i++;
        }
        return false;
    }
    
    public function study(info:TreeInfo):Boolean {
        info.minLength += buffer.length;
        info.maxValid = false;
        return next.study(info);
    }
    
}
