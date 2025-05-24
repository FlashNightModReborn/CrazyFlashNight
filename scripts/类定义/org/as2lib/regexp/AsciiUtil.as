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

import org.as2lib.core.BasicClass;

/**
 * {@code AsciiUtil} provides common routines for ASCII char validations and
 * conversations.
 * 
 * @author Igor Sadovskiy
 */

class org.as2lib.regexp.AsciiUtil extends BasicClass {
    
    public static var UPPER:Number   = 0x00000100;
    
    public static var LOWER:Number   = 0x00000200;
    
    public static var DIGIT:Number   = 0x00000400;
    
    public static var SPACE:Number   = 0x00000800;
    
    public static var PUNCT:Number   = 0x00001000;
    
    public static var CNTRL:Number   = 0x00002000;
    
    public static var BLANK:Number   = 0x00004000;
    
    public static var HEX:Number     = 0x00008000;
    
    public static var UNDER:Number   = 0x00010000;
    
    public static var ASCII:Number   = 0x0000FF00;

    public static var ALPHA:Number   = (UPPER|LOWER);

    public static var ALNUM:Number   = (UPPER|LOWER|DIGIT);

    public static var GRAPH:Number   = (PUNCT|UPPER|LOWER|DIGIT);

    public static var WORD:Number    = (UPPER|LOWER|UNDER|DIGIT);

    public static var XDIGIT:Number  = HEX;

    private static var charTypes:Array = [
        CNTRL,                  /* 00 (NUL) */
        CNTRL,                  /* 01 (SOH) */
        CNTRL,                  /* 02 (STX) */
        CNTRL,                  /* 03 (ETX) */
        CNTRL,                  /* 04 (EOT) */
        CNTRL,                  /* 05 (ENQ) */
        CNTRL,                  /* 06 (ACK) */
        CNTRL,                  /* 07 (BEL) */
        CNTRL,                  /* 08 (BS)  */
        SPACE+CNTRL+BLANK,      /* 09 (HT)  */
        SPACE+CNTRL,            /* 0A (LF)  */
        SPACE+CNTRL,            /* 0B (VT)  */
        SPACE+CNTRL,            /* 0C (FF)  */
        SPACE+CNTRL,            /* 0D (CR)  */
        CNTRL,                  /* 0E (SI)  */
        CNTRL,                  /* 0F (SO)  */
        CNTRL,                  /* 10 (DLE) */
        CNTRL,                  /* 11 (DC1) */
        CNTRL,                  /* 12 (DC2) */
        CNTRL,                  /* 13 (DC3) */
        CNTRL,                  /* 14 (DC4) */
        CNTRL,                  /* 15 (NAK) */
        CNTRL,                  /* 16 (SYN) */
        CNTRL,                  /* 17 (ETB) */
        CNTRL,                  /* 18 (CAN) */
        CNTRL,                  /* 19 (EM)  */
        CNTRL,                  /* 1A (SUB) */
        CNTRL,                  /* 1B (ESC) */
        CNTRL,                  /* 1C (FS)  */
        CNTRL,                  /* 1D (GS)  */
        CNTRL,                  /* 1E (RS)  */
        CNTRL,                  /* 1F (US)  */
        SPACE+BLANK,            /* 20 SPACE */
        PUNCT,                  /* 21 !     */
        PUNCT,                  /* 22 "     */
        PUNCT,                  /* 23 #     */
        PUNCT,                  /* 24 $     */
        PUNCT,                  /* 25 %     */
        PUNCT,                  /* 26 &     */
        PUNCT,                  /* 27 '     */
        PUNCT,                  /* 28 (     */
        PUNCT,                  /* 29 )     */
        PUNCT,                  /* 2A *     */
        PUNCT,                  /* 2B +     */
        PUNCT,                  /* 2C ,     */
        PUNCT,                  /* 2D -     */
        PUNCT,                  /* 2E .     */
        PUNCT,                  /* 2F /     */
        DIGIT+HEX+0,            /* 30 0     */
        DIGIT+HEX+1,            /* 31 1     */
        DIGIT+HEX+2,            /* 32 2     */
        DIGIT+HEX+3,            /* 33 3     */
        DIGIT+HEX+4,            /* 34 4     */
        DIGIT+HEX+5,            /* 35 5     */
        DIGIT+HEX+6,            /* 36 6     */
        DIGIT+HEX+7,            /* 37 7     */
        DIGIT+HEX+8,            /* 38 8     */
        DIGIT+HEX+9,            /* 39 9     */
        PUNCT,                  /* 3A :     */
        PUNCT,                  /* 3B ;     */
        PUNCT,                  /* 3C <     */
        PUNCT,                  /* 3D =     */
        PUNCT,                  /* 3E >     */
        PUNCT,                  /* 3F ?     */
        PUNCT,                  /* 40 @     */
        UPPER+HEX+10,           /* 41 A     */
        UPPER+HEX+11,           /* 42 B     */
        UPPER+HEX+12,           /* 43 C     */
        UPPER+HEX+13,           /* 44 D     */
        UPPER+HEX+14,           /* 45 E     */
        UPPER+HEX+15,           /* 46 F     */
        UPPER+16,               /* 47 G     */
        UPPER+17,               /* 48 H     */
        UPPER+18,               /* 49 I     */
        UPPER+19,               /* 4A J     */
        UPPER+20,               /* 4B K     */
        UPPER+21,               /* 4C L     */
        UPPER+22,               /* 4D M     */
        UPPER+23,               /* 4E N     */
        UPPER+24,               /* 4F O     */
        UPPER+25,               /* 50 P     */
        UPPER+26,               /* 51 Q     */
        UPPER+27,               /* 52 R     */
        UPPER+28,               /* 53 S     */
        UPPER+29,               /* 54 T     */
        UPPER+30,               /* 55 U     */
        UPPER+31,               /* 56 V     */
        UPPER+32,               /* 57 W     */
        UPPER+33,               /* 58 X     */
        UPPER+34,               /* 59 Y     */
        UPPER+35,               /* 5A Z     */
        PUNCT,                  /* 5B [     */
        PUNCT,                  /* 5C \     */
        PUNCT,                  /* 5D ]     */
        PUNCT,                  /* 5E ^     */
        PUNCT|UNDER,            /* 5F _     */
        PUNCT,                  /* 60 `     */
        LOWER+HEX+10,           /* 61 a     */
        LOWER+HEX+11,           /* 62 b     */
        LOWER+HEX+12,           /* 63 c     */
        LOWER+HEX+13,           /* 64 d     */
        LOWER+HEX+14,           /* 65 e     */
        LOWER+HEX+15,           /* 66 f     */
        LOWER+16,               /* 67 g     */
        LOWER+17,               /* 68 h     */
        LOWER+18,               /* 69 i     */
        LOWER+19,               /* 6A j     */
        LOWER+20,               /* 6B k     */
        LOWER+21,               /* 6C l     */
        LOWER+22,               /* 6D m     */
        LOWER+23,               /* 6E n     */
        LOWER+24,               /* 6F o     */
        LOWER+25,               /* 70 p     */
        LOWER+26,               /* 71 q     */
        LOWER+27,               /* 72 r     */
        LOWER+28,               /* 73 s     */
        LOWER+29,               /* 74 t     */
        LOWER+30,               /* 75 u     */
        LOWER+31,               /* 76 v     */
        LOWER+32,               /* 77 w     */
        LOWER+33,               /* 78 x     */
        LOWER+34,               /* 79 y     */
        LOWER+35,               /* 7A z     */
        PUNCT,                  /* 7B {     */
        PUNCT,                  /* 7C |     */
        PUNCT,                  /* 7D }     */
        PUNCT,                  /* 7E ~     */
        CNTRL                   /* 7F (DEL) */
    ]; 
    
	private function AsciiUtil(Void) {
		super();
	}

    public static function getType(ch:Number):Number {
        return ((ch & 0xFFFFFF80) == 0 ? charTypes[ch] : 0);
    }

    public static function isType(ch:Number, type:Number):Boolean {
        return (getType(ch) & type) != 0;
    }

    public static function isAscii(ch:Number):Boolean {
        return ((ch & 0xFFFFFF80) == 0);
    }

    public static function isAlpha(ch:Number):Boolean {
        return isType(ch, ALPHA);
    }

    public static function isDigit(ch:Number):Boolean {
        return ((ch - 0x30) | (0x39 - ch)) >= 0;
    }

    public static function isAlnum(ch:Number):Boolean {
        return isType(ch, ALNUM);
    }

    public static function isGraph(ch:Number):Boolean {
        return isType(ch, GRAPH);
    }

    public static function isPrint(ch:Number):Boolean {
        return ((ch - 0x20) | (0x7E - ch)) >= 0;
    }

    public static function isPunct(ch:Number):Boolean {
        return isType(ch, PUNCT);
    }

    public static function isSpace(ch:Number):Boolean {
        return isType(ch, SPACE);
    }

    public static function isHexDigit(ch:Number):Boolean {
        return isType(ch, HEX);
    }

    public static function isOctDigit(ch:Number):Boolean {
        return ((ch - 0x30) | (0x37 - ch)) >= 0;
    }

    public static function isCntrl(ch:Number):Boolean {
        return isType(ch, CNTRL);
    }

    public static function isLower(ch:Number):Boolean {
        return ((ch - 0x61) | (0x7A - ch)) >= 0;
    }

    public static function isUpper(ch:Number):Boolean {
        return ((ch - 0x41) | (0x5A - ch)) >= 0;
    }

    public static function isWord(ch:Number):Boolean {
        return isType(ch, WORD);
    }

    public static function toDigit(ch:Number):Number {
        return (charTypes[ch & 0x7F] & 0x3F);
    }

    public static function toLower(ch:Number):Number {
        return isUpper(ch) ? (ch + 0x20) : ch;
    }

    public static function toUpper(ch:Number):Number {
        return isLower(ch) ? (ch - 0x20) : ch;
    }

}