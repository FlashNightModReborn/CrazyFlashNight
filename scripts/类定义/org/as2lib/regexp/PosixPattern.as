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

import org.as2lib.regexp.AsciiUtil;
import org.as2lib.regexp.Pattern;
import org.as2lib.regexp.node.*;

import org.as2lib.util.StringUtil;
import org.as2lib.data.holder.map.HashMap;
/**
 * {@code PosixPattern} provides implementations of the parsing engine for 
 * POSIX character classes and Unicode blocks and categories.
 * 
 * @author Igor Sadovskiy
 * @see org.as2lib.regexp.Matcher
 * @see org.as2lib.regexp.Pattern
 */


class org.as2lib.regexp.PosixPattern extends Pattern {
		
    private static var families:HashMap = null;

    private static var categories:HashMap = null;
	
    private static var familyNames:Array = [ 
        "BasicLatin",
        "Latin-1Supplement",
        "LatinExtended-A",
        "LatinExtended-Bound",
        "IPAExtensions",
        "SpacingModifierLetters",
        "CombiningDiacriticalMarks",
        "Greek",
        "Cyrillic",
        "Armenian",
        "Hebrew",
        "Arabic",
        "Syriac",
        "Thaana",
        "Devanagari",
        "Bengali",
        "Gurmukhi",
        "Gujarati",
        "Oriya",
        "Tamil",
        "Telugu",
        "Kannada",
        "Malayalam",
        "Sinhala",
        "Thai",
        "Lao",
        "Tibetan",
        "Myanmar",
        "Georgian",
        "HangulJamo",
        "Ethiopic",
        "Cherokee",
        "UnifiedCanadianAboriginalSyllabics",
        "Ogham",
        "Runic",
        "Khmer",
        "Mongolian",
        "LatinExtendedAdditional",
        "GreekExtended",
        "GeneralPunctuation",
        "SuperscriptsandSubscripts",
        "CurrencySymbols",
        "CombiningMarksforSymbols",
        "LetterlikeSymbols",
        "NumberForms",
        "Arrows",
        "MathematicalOperators",
        "MiscellaneousTechnical",
        "ControlPictures",
        "OpticalCharacterRecognition",
        "EnclosedAlphanumerics",
        "BoxDrawing",
        "BlockElements",
        "GeometricShapes",
        "MiscellaneousSymbols",
        "Dingbats",
        "BraillePatterns",
        "CJKRadicalsSupplement",
        "KangxiRadicals",
        "IdeographicDescriptionCharacters",
        "CJKSymbolsandPunctuation",
        "Hiragana",
        "Katakana",
        "Bopomofo",
        "HangulCompatibilityJamo",
        "Kanbun",
        "BopomofoExtended",
        "EnclosedCJKLettersandMonths",
        "CJKCompatibility",
        "CJKUnifiedIdeographsExtensionA",
        "CJKUnifiedIdeographs",
        "YiSyllables",
        "YiRadicals",
        "HangulSyllables",
        "HighSurrogates",
        "HighPrivateUseSurrogates",
        "LowSurrogates",
        "PrivateUse",
        "CJKCompatibilityIdeographs",
        "AlphabeticPresentationForms",
        "ArabicPresentationForms-A",
        "CombiningHalfMarks",
        "CJKCompatibilityForms",
        "SmallFormVariants",
        "ArabicPresentationForms-Bound",
        "Specials",
        "HalfwidthandFullwidthForms"
    ];

    private static var categoryNames:Array = [ 
		"Cn",                   // UNASSIGNED		    	= 0,
		"Lu",                   // UPPERCASE_LETTER	    	= 1,
		"Ll",                   // LOWERCASE_LETTER	    	= 2,
		"Lt",                   // TITLECASE_LETTER	    	= 3,
		"Lm",                   // MODIFIER_LETTER	    	= 4,
		"Lo",                   // OTHER_LETTER		    	= 5,
		"Mn",                   // NON_SPACING_MARK	    	= 6,
		"Me",                   // ENCLOSING_MARK	    	= 7,
		"Mc",                   // COMBINING_SPACING_MARK   = 8,
		"Nd",                   // DECIMAL_DIGIT_NUMBER	    = 9,
		"Nl",                   // LETTER_NUMBER	    	= 10,
		"No",                   // OTHER_NUMBER		    	= 11,
		"Zs",                   // SPACE_SEPARATOR	    	= 12,
		"Zl",                   // LINE_SEPARATOR	    	= 13,
		"Zp",                   // PARAGRAPH_SEPARATOR		= 14,
		"Cc",                   // CNTRL		    		= 15,
		"Cf",                   // FORMAT		    		= 16,
		"Co",                   // PRIVATE_USE		    	= 18,
		"Cs",                   // SURROGATE		    	= 19,
		"Pd",                   // DASH_PUNCTUATION	    	= 20,
		"Ps",                   // START_PUNCTUATION		= 21,
		"Pe",                   // END_PUNCTUATION	    	= 22,
		"Pc",                   // CONNECTOR_PUNCTUATION    = 23,
		"Po",                   // OTHER_PUNCTUATION	    = 24,
		"Sm",                   // MATH_SYMBOL		    	= 25,
		"Sc",                   // CURRENCY_SYMBOL	    	= 26,
		"Sk",                   // MODIFIER_SYMBOL	    	= 27,
		"So",                   // OTHER_SYMBOL		    	= 28;

        "L",                    // LETTER
        "M",                    // MARK
        "N",                    // NUMBER
        "Z",                    // SEPARATOR
        "C",                    // CONTROL
        "P",                    // PUNCTUATION
        "S",                    // SYMBOL

        "LD",                   // LETTER_OR_DIGIT
        "L1",                   // Latin-1

        "all",                  // ALL
        "ASCII",                // ASCII

        "Alnum",                // Alphanumeric characters.
        "Alpha",                // Alphabetic characters.
        "Blank",                // Space and tab characters.
        "Cntrl",                // Control characters.
        "Digit",                // Numeric characters.
        "Graph",                // Characters that are printable and are also visible.
                                // (A space is printable, but "not visible, while an `a' is both.)
        "Lower",                // Lower-case alphabetic characters.
        "Print",                // Printable characters (characters that are not control characters.)
        "Punct",                // Punctuation characters (characters that are not letter,
                                // digits, control charact ers, or space characters).
        "Space",                // Space characters (such as space, tab, and formfeed, to name a few).
        "Upper",                // Upper-case alphabetic characters.
        "XDigit"                // Characters that are hexadecimal digits.
    ];

    private static var familyNodes:Array = [ 
        new Range(0x0000007F),      // Basic Latin
        new Range(0x008000FF),      // Latin-1 Supplement
        new Range(0x0100017F),      // Latin Extended-A
        new Range(0x0180024F),      // Latin Extended-Bound
        new Range(0x025002AF),      // IPA Extensions
        new Range(0x02B002FF),      // Spacing Modifier Letters
        new Range(0x0300036F),      // Combining Diacritical Marks
        new Range(0x037003FF),      // Greek
        new Range(0x040004FF),      // Cyrillic
        new Range(0x0530058F),      // Armenian
        new Range(0x059005FF),      // Hebrew
        new Range(0x060006FF),      // Arabic
        new Range(0x0700074F),      // Syriac
        new Range(0x078007BF),      // Thaana
        new Range(0x0900097F),      // Devanagari
        new Range(0x098009FF),      // Bengali
        new Range(0x0A000A7F),      // Gurmukhi
        new Range(0x0A800AFF),      // Gujarati
        new Range(0x0B000B7F),      // Oriya
        new Range(0x0B800BFF),      // Tamil
        new Range(0x0C000C7F),      // Telugu
        new Range(0x0C800CFF),      // Kannada
        new Range(0x0D000D7F),      // Malayalam
        new Range(0x0D800DFF),      // Sinhala
        new Range(0x0E000E7F),      // Thai
        new Range(0x0E800EFF),      // Lao
        new Range(0x0F000FFF),      // Tibetan
        new Range(0x1000109F),      // Myanmar
        new Range(0x10A010FF),      // Georgian
        new Range(0x110011FF),      // Hangul Jamo
        new Range(0x1200137F),      // Ethiopic
        new Range(0x13A013FF),      // Cherokee
        new Range(0x1400167F),      // Unified Canadian Aboriginal Syllabics
        new Range(0x1680169F),      // Ogham
        new Range(0x16A016FF),      // Runic
        new Range(0x178017FF),      // Khmer
        new Range(0x180018AF),      // Mongolian
        new Range(0x1E001EFF),      // Latin Extended Additional
        new Range(0x1F001FFF),      // Greek Extended
        new Range(0x2000206F),      // General Punctuation
        new Range(0x2070209F),      // Superscripts and Subscripts
        new Range(0x20A020CF),      // Currency Symbols
        new Range(0x20D020FF),      // Combining Marks for Symbols
        new Range(0x2100214F),      // Letterlike Symbols
        new Range(0x2150218F),      // Number Forms
        new Range(0x219021FF),      // Arrows
        new Range(0x220022FF),      // Mathematical Operators
        new Range(0x230023FF),      // Miscellaneous Technical
        new Range(0x2400243F),      // Control Pictures
        new Range(0x2440245F),      // Optical Character Recognition
        new Range(0x246024FF),      // Enclosed Alphanumerics
        new Range(0x2500257F),      // Box Drawing
        new Range(0x2580259F),      // Block Elements
        new Range(0x25A025FF),      // Geometric Shapes
        new Range(0x260026FF),      // Miscellaneous Symbols
        new Range(0x270027BF),      // Dingbats
        new Range(0x280028FF),      // Braille Patterns
        new Range(0x2E802EFF),      // CJK Radicals Supplement
        new Range(0x2F002FDF),      // Kangxi Radicals
        new Range(0x2FF02FFF),      // Ideographic Description Characters
        new Range(0x3000303F),      // CJK Symbols and Punctuation
        new Range(0x3040309F),      // Hiragana
        new Range(0x30A030FF),      // Katakana
        new Range(0x3100312F),      // Bopomofo
        new Range(0x3130318F),      // Hangul Compatibility Jamo
        new Range(0x3190319F),      // Kanbun
        new Range(0x31A031BF),      // Bopomofo Extended
        new Range(0x320032FF),      // Enclosed CJK Letters and Months
        new Range(0x330033FF),      // CJK Compatibility
        new Range(0x34004DB5),      // CJK Unified Ideographs Extension A
        new Range(0x4E009FFF),      // CJK Unified Ideographs
        new Range(0xA000A48F),      // Yi Syllables
        new Range(0xA490A4CF),      // Yi Radicals
        new Range(0xAC00D7A3),      // Hangul Syllables
        new Range(0xD800DB7F),      // High Surrogates
        new Range(0xDB80DBFF),      // High Private Use Surrogates
        new Range(0xDC00DFFF),      // Low Surrogates
        new Range(0xE000F8FF),      // Private Use
        new Range(0xF900FAFF),      // CJK Compatibility Ideographs
        new Range(0xFB00FB4F),      // Alphabetic Presentation Forms
        new Range(0xFB50FDFF),      // Arabic Presentation Forms-A
        new Range(0xFE20FE2F),      // Combining Half Marks
        new Range(0xFE30FE4F),      // CJK Compatibility Forms
        new Range(0xFE50FE6F),      // Small Form Variants
        new Range(0xFE70FEFE),      // Arabic Presentation Forms-Bound
        new Specials(),             // Specials
        new Range(0xFF00FFEF)       // Halfwidth and Fullwidth Forms
    ];

    private static var categoryNodes:Array = [ 
		new Category(1<<0),         // UNASSIGNED           	= 0,
		new Category(1<<1),         // UPPERCASE_LETTER	    	= 1,
		new Category(1<<2),         // LOWERCASE_LETTER	    	= 2,
		new Category(1<<3),         // TITLECASE_LETTER	    	= 3,
		new Category(1<<4),         // MODIFIER_LETTER      	= 4,
		new Category(1<<5),         // OTHER_LETTER         	= 5,
		new Category(1<<6),         // NON_SPACING_MARK	    	= 6,
		new Category(1<<7),         // ENCLOSING_MARK	    	= 7,
		new Category(1<<8),         // COMBINING_SPACING_MARK	= 8,
		new Category(1<<9),         // DECIMAL_DIGIT_NUMBER 	= 9,
		new Category(1<<10),        // LETTER_NUMBER	    	= 10,
		new Category(1<<11),        // OTHER_NUMBER         	= 11,
		new Category(1<<12),        // SPACE_SEPARATOR	    	= 12,
		new Category(1<<13),        // LINE_SEPARATOR	    	= 13,
		new Category(1<<14),        // PARAGRAPH_SEPARATOR  	= 14,
		new Category(1<<15),        // CNTRL		    		= 15,
		new Category(1<<16),        // FORMAT		    		= 16,
		new Category(1<<18),        // PRIVATE_USE          	= 18,
		new Category(1<<19),        // SURROGATE            	= 19,
		new Category(1<<20),        // DASH_PUNCTUATION	    	= 20,
		new Category(1<<21),        // START_PUNCTUATION    	= 21,
		new Category(1<<22),        // END_PUNCTUATION	    	= 22,
		new Category(1<<23),        // CONNECTOR_PUNCTUATION	= 23,
		new Category(1<<24),        // OTHER_PUNCTUATION    	= 24,
		new Category(1<<25),        // MATH_SYMBOL          	= 25,
		new Category(1<<26),        // CURRENCY_SYMBOL	    	= 26,
		new Category(1<<27),        // MODIFIER_SYMBOL	    	= 27,
		new Category(1<<28),        // OTHER_SYMBOL         	= 28;

        new Category(0x0000003E),   // LETTER
        new Category(0x000001C0),   // MARK
        new Category(0x00000E00),   // NUMBER
        new Category(0x00007000),   // SEPARATOR
        new Category(0x000D8000),   // CONTROL
        new Category(0x01F00000),   // PUNCTUATION
        new Category(0x1E000000),   // SYMBOL

        new Category(0x0000023E),   // LETTER_OR_DIGIT
        new Range(0x000000FF),      // Latin-1

        new All(),                  // ALL
        new Range(0x0000007F),      // ASCII

        new Posix(AsciiUtil.ALNUM),     	// Alphanumeric characters.
        new Posix(AsciiUtil.ALPHA),     	// Alphabetic characters.
        new Posix(AsciiUtil.BLANK),     	// Space and tab characters.
        new Posix(AsciiUtil.CNTRL),     	// Control characters.
        new Range((0x30<<16)|0x39),			// Numeric characters.
        new Posix(AsciiUtil.GRAPH),     	// Characters that are printable and are also visible.
                                    		// (A space is printable, but "not visible, while an `a' is both.)
        new Range((0x61<<16)|0x7A), 		// Lower-case alphabetic characters.
        new Range(0x0020007E),      		// Printable characters (characters that are not control characters.)
        new Posix(AsciiUtil.PUNCT),     	// Punctuation characters (characters that are not letter,
                                    		// digits, control charact ers, or space characters).
        new Posix(AsciiUtil.SPACE),     	// Space characters (such as space, tab, and formfeed, to name a few).
        new Range((0x41<<16)|0x5A),			// Upper-case alphabetic characters.
        new Posix(AsciiUtil.XDIGIT)     	// Characters that are hexadecimal digits.
    ];
	
	
    private function parseFamily(flag:Boolean, singleLetter:Boolean):Node {
        nextChar();
        var name: String;

        if (singleLetter) {
            name = chr(temp[cursor]);
            readChar();
        } else {
            var i:Number = cursor;
            markChar(0x7D);
            while(readChar() != 0x7D) {
            	// stuff
            }
            markChar(0);
            var j:Number = cursor;
            if (j > patternLength) {
                throwError("Unclosed character family", arguments);
            }
            if (i + 1 >= j) {
                throwError("Empty character family", arguments);
            }
            name = fromCharCodeArray(temp.slice(i, j-1));
        }

        if (StringUtil.startsWith(name, "In")) {
            name = name.substring(2, name.length);
            return getFamilyNode(name).dup(flag);
        }
        if (StringUtil.startsWith(name, "Is")) {
            name = name.substring(2, name.length);
        }
        return getCategoryNode(name).dup(flag);
    }
	
    private function getFamilyNode(name:String):Node {
        if (families == null) {
            var fns:Number = familyNodes.length;
            families = new HashMap();
            for (var x=0; x<fns; x++) {
                families.put(familyNames[x], familyNodes[x]);
            }
        }
        var n:Node = Node(families.get(name));
        if (n != null) return n;

        throwFamilyError(name, "Unknown character family", arguments);
    }	
	
    private function getCategoryNode(name:String):Node {
        if (categories == null) {
            var cns:Number = categoryNodes.length;
            categories = new HashMap();
            for (var x=0; x<cns; x++) {
                categories.put(categoryNames[x], categoryNodes[x]);
            }
        }
        var n:Node = Node(categories.get(name));
        if (n != null) return n;

        throwFamilyError(name, "Unknown character category", arguments);
    }

    private function throwFamilyError(name:String, type:String, args:FunctionArguments):Void {
        throwError(type + " " + chr(0x7B) + name + chr(0x7D), args);
    }
	
	public function PosixPattern(newPattern:String, newFlags:Number) {
		super(newPattern, newFlags);
	}
	
}