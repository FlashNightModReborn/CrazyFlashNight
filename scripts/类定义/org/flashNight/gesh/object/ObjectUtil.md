import org.flashNight.gesh.object.*;
var test:ObjectUtilTest = new ObjectUtilTest();
test.runTests();



=== ObjectUtil Test Suite Initialized ===
=== Running ObjectUtil Tests ===


--- Test: clone - Simple Object ---
[PASS] Cloned object is a different reference
[PASS] Cloned name property correct
[PASS] Cloned age property correct
[PASS] Clone is independent from original

--- Test: clone - Nested Object ---
[PASS] Nested object is deep cloned
[PASS] Nested property correct
[PASS] Deep clone is independent

--- Test: clone - Array ---
[PASS] Cloned array is different reference
[PASS] Array length preserved
[PASS] Array element correct
[PASS] Nested object in array cloned
[PASS] Nested object is deep cloned

--- Test: clone - Date ---
[PASS] Cloned date is different reference
[PASS] Date time value preserved

--- Test: clone - Circular Reference ---
[PASS] Root property cloned
[PASS] Circular reference preserved in clone
[PASS] Circular reference points to clone, not original

--- Test: clone - Null ---
[PASS] Cloning null returns null

--- Test: clone - Primitives ---
[PASS] Number cloned correctly
[PASS] String cloned correctly
[PASS] Boolean cloned correctly

--- Test: cloneParameters - From Object ---
[PASS] New property added
[PASS] Nested property cloned
[PASS] Existing property preserved

--- Test: cloneParameters - From String ---
[PASS] String property parsed
[PASS] Number value parsed from string

--- Test: cloneParameters - String with Boolean ---
[PASS] Boolean true parsed
[PASS] Boolean false parsed

--- Test: cloneParameters - String with Number ---
[PASS] Integer parsed
[PASS] Float parsed
[PASS] Text preserved as string

--- Test: forEach - Basic ---
[PASS] All values iterated and summed
[PASS] All keys visited

--- Test: forEach - With Null ---
[PASS] Callback not called for null object

--- Test: forEach - Empty Object ---
[PASS] Callback not called for empty object

--- Test: forEach - Ignores Prototype ---
[PASS] Only own properties iterated
[PASS] Own property found

--- Test: compare - Numbers ---
[PASS] 10 < 20
[PASS] 20 > 10
[PASS] 15 == 15

--- Test: compare - Strings ---
[PASS] abc < xyz
[PASS] xyz > abc
[PASS] hello == hello

--- Test: compare - Arrays ---
[PASS] Shorter array < longer array
[PASS] Longer array > shorter array
[PASS] Equal arrays
[PASS] Element comparison

--- Test: compare - Objects ---
[PASS] obj1 < obj2 (different values)
[PASS] obj1 == obj3 (same values)

--- Test: compare - With Null ---
[PASS] null < object
[PASS] object > null
[PASS] null == null

--- Test: compare - Different Types ---
[PASS] Different types are not equal

--- Test: compare - Circular Reference ---
[PASS] Circular references handled in comparison

--- Test: hasProperties - True ---
[PASS] Object with properties returns true

--- Test: hasProperties - False ---
[PASS] Empty object returns false

--- Test: isSimple - Number ---
[PASS] Number is simple
[PASS] Float is simple

--- Test: isSimple - String ---
[PASS] String is simple
[PASS] Empty string is simple

--- Test: isSimple - Boolean ---
[PASS] True is simple
[PASS] False is simple

--- Test: isSimple - Object ---
[PASS] Object is not simple
[PASS] Object with props is not simple

--- Test: isSimple - Array ---
[PASS] Array is not simple
[PASS] Array with elements is not simple

--- Test: toString - Simple Object ---
[PASS] Contains name key
[PASS] Contains name value
[PASS] Contains number value

--- Test: toString - Nested Object ---
[PASS] Contains outer key
[PASS] Contains inner key

--- Test: toString - Array ---
[PASS] Starts with [
[PASS] Contains first element

--- Test: toString - Circular Reference ---
[PASS] Circular reference marked

--- Test: toString - Max Depth ---
[PASS] Max depth handled

--- Test: toString - Function ---
[PASS] Function formatted with func: prefix

--- Test: toString - Null ---
[PASS] Null converted to 'null' string

--- Test: isInternalKey - True ---
[PASS] __dictUID is internal
[PASS] __proto__ is internal

--- Test: isInternalKey - False ---
[PASS] name is not internal
[PASS] _private is not internal

--- Test: copyProperties - Basic ---
[PASS] Property a copied
[PASS] Property b copied

--- Test: copyProperties - With Null ---
[PASS] Destination unchanged when source is null

--- Test: copyProperties - Ignores Internal Keys ---
[PASS] Normal property copied
[PASS] Internal key not copied

--- Test: getKeys - Basic ---
[PASS] Got 3 keys

--- Test: getKeys - Empty ---
[PASS] Empty object has no keys

--- Test: getKeys - Ignores Internal Keys ---
[PASS] Only normal key returned
[PASS] Correct key returned

--- Test: toArray - With Array ---
[PASS] Array returned as-is

--- Test: toArray - With Object ---
[PASS] Object wrapped in array
[PASS] Object is first element

--- Test: toArray - With Null ---
[PASS] Null returns empty array

--- Test: toArray - With Primitive ---
[PASS] Primitive wrapped in array
[PASS] Primitive is first element

--- Test: equals - Identical ---
[PASS] Same reference equals

--- Test: equals - Different ---
[PASS] Different values not equal

--- Test: equals - Nested Objects ---
[PASS] Equal nested objects
[PASS] Different nested values

--- Test: equals - Arrays ---
[PASS] Equal arrays
[PASS] Different arrays

--- Test: equals - With Null ---
[PASS] null == null
[PASS] null != object
[PASS] object != null

--- Test: equals - Circular Reference ---
[PASS] Equal circular references

--- Test: size - Basic ---
[PASS] Size is 3

--- Test: size - Empty ---
[PASS] Empty object size is 0

--- Test: size - Ignores Internal Keys ---
[PASS] Internal keys not counted

--- Test: deepEquals - Basic ---
[PASS] Deep equals works

--- Test: deepEquals - Nested ---
[PASS] Deep nested equals

--- Test: toJSON - Basic ---
[PASS] JSON string created
[PASS] JSON contains value

--- Test: toJSON - Pretty ---
[PASS] Pretty JSON created

--- Test: fromJSON - Basic ---
[PASS] Object parsed from JSON
[PASS] Name property parsed
[PASS] Value property parsed

--- Test: fromJSON - Invalid ---
ObjectUtil.fromJSON: JSON解析存在错误 - Bad string
[PASS] Invalid JSON returns null

--- Test: JSON - Round Trip ---
[PASS] Round trip preserves name
[PASS] Round trip preserves array
[PASS] Round trip preserves nested

--- Test: toBase64 - Basic ---
RLE 压缩完成。原长度: 26, 压缩后长度: 35
RLE 压缩后的结果: {"name":"T#1;est","valu#1;e":42}#1;
LZW 压缩后的结果: 007B0022006E0061006D00650022003A002200540100003101010065007300740022002C002200760061006C007501030111003A00340032007D0103
LZW 压缩并编码后的结果: {"name":"TĀ1āest","valuăđ:42}ă
[PASS] Base64 string created
[PASS] Base64 string not empty

--- Test: fromBase64 - Basic ---
RLE 压缩完成。原长度: 26, 压缩后长度: 35
RLE 压缩后的结果: {"name":"T#1;est","valu#1;e":42}#1;
LZW 压缩后的结果: 007B0022006E0061006D00650022003A002200540100003101010065007300740022002C002200760061006C007501030111003A00340032007D0103
LZW 压缩并编码后的结果: {"name":"TĀ1āest","valuăđ:42}ă
编码解码后的结果: 007B0022006E0061006D00650022003A002200540100003101010065007300740022002C002200760061006C007501030111003A00340032007D0103
LZW 解压后的结果: {"name":"T#1;est","valu#1;e":42}#1;
RLE 解压缩完成。解压后长度: 26
RLE 解压后的结果: {"name":"Test","value":42}
[PASS] Object parsed from Base64
[PASS] Name property restored

--- Test: Base64 - Round Trip ---
RLE 压缩完成。原长度: 55, 压缩后长度: 73
RLE 压缩后的结果: {"text":"H#1;ello World#1;","number"#1;:123.456,"#1;array":[1,#1;2,3]}#1;
LZW 压缩后的结果: 007B002200740065007800740022003A002200480100003101010065006C006C006F00200057006F0072006C006401030022002C0022006E0075006D00620065007200220103003A003100320033002E00340035003601250103006100720072006100790112005B0031002C01030032002C0033005D007D0103
LZW 压缩并编码后的结果: {"text":"HĀ1āello Worldă","number"ă:123.456ĥăarrayĒ[1,ă2,3]}ă
编码解码后的结果: 007B002200740065007800740022003A002200480100003101010065006C006C006F00200057006F0072006C006401030022002C0022006E0075006D00620065007200220103003A003100320033002E00340035003601250103006100720072006100790112005B0031002C01030032002C0033005D007D0103
LZW 解压后的结果: {"text":"H#1;ello World#1;","number"#1;:123.456,"#1;array":[1,#1;2,3]}#1;
RLE 解压缩完成。解压后长度: 55
RLE 解压后的结果: {"text":"Hello World","number":123.456,"array":[1,2,3]}
[PASS] Base64 round trip preserves data

--- Test: toFNTL - Basic ---
[PASS] FNTL string created

--- Test: fromFNTL - Basic ---
nextChar: 'n' (位置: 1, 行: 1, 列: 2)
FNTLLexer 初始化。文本长度: 25
nextChar: 'a' (位置: 2, 行: 1, 列: 3)
nextChar: 'm' (位置: 3, 行: 1, 列: 4)
nextChar: 'e' (位置: 4, 行: 1, 列: 5)
nextChar: ' ' (位置: 5, 行: 1, 列: 6)
readIdentifier: 'name'
getNextToken: KEY token detected - name
nextChar: '=' (位置: 6, 行: 1, 列: 7)
nextChar: ' ' (位置: 7, 行: 1, 列: 8)
getNextToken: EQUALS token detected.
nextChar: '"' (位置: 8, 行: 1, 列: 9)
nextChar: 'T' (位置: 9, 行: 1, 列: 10)
nextChar: 'e' (位置: 10, 行: 1, 列: 11)
nextChar: 's' (位置: 11, 行: 1, 列: 12)
nextChar: 't' (位置: 12, 行: 1, 列: 13)
nextChar: '"' (位置: 13, 行: 1, 列: 14)
nextChar: '
' (位置: 14, 行: 2, 列: 1)
readString: Single-line string ended.
getNextToken: STRING token detected - Test
nextChar: 'v' (位置: 15, 行: 2, 列: 2)
getNextToken: NEWLINE token detected.
nextChar: 'a' (位置: 16, 行: 2, 列: 3)
nextChar: 'l' (位置: 17, 行: 2, 列: 4)
nextChar: 'u' (位置: 18, 行: 2, 列: 5)
nextChar: 'e' (位置: 19, 行: 2, 列: 6)
nextChar: ' ' (位置: 20, 行: 2, 列: 7)
readIdentifier: 'value'
getNextToken: KEY token detected - value
nextChar: '=' (位置: 21, 行: 2, 列: 8)
nextChar: ' ' (位置: 22, 行: 2, 列: 9)
getNextToken: EQUALS token detected.
nextChar: '4' (位置: 23, 行: 2, 列: 10)
nextChar: '2' (位置: 24, 行: 2, 列: 11)
nextChar: '
' (位置: 25, 行: 3, 列: 1)
getNextToken: INTEGER token detected - 42
nextChar: End of text reached.
getNextToken: NEWLINE token detected.
getNextToken: End of text.
[PASS] Object parsed from FNTL

--- Test: FNTL - Round Trip ---
nextChar: 'i' (位置: 1, 行: 1, 列: 2)
FNTLLexer 初始化。文本长度: 66
nextChar: 't' (位置: 2, 行: 1, 列: 3)
nextChar: 'e' (位置: 3, 行: 1, 列: 4)
nextChar: 'm' (位置: 4, 行: 1, 列: 5)
nextChar: 's' (位置: 5, 行: 1, 列: 6)
nextChar: ' ' (位置: 6, 行: 1, 列: 7)
readIdentifier: 'items'
getNextToken: KEY token detected - items
nextChar: '=' (位置: 7, 行: 1, 列: 8)
nextChar: ' ' (位置: 8, 行: 1, 列: 9)
getNextToken: EQUALS token detected.
nextChar: '[' (位置: 9, 行: 1, 列: 10)
nextChar: '"' (位置: 10, 行: 1, 列: 11)
getNextToken: LBRACKET token detected.
nextChar: 's' (位置: 11, 行: 1, 列: 12)
nextChar: 'w' (位置: 12, 行: 1, 列: 13)
nextChar: 'o' (位置: 13, 行: 1, 列: 14)
nextChar: 'r' (位置: 14, 行: 1, 列: 15)
nextChar: 'd' (位置: 15, 行: 1, 列: 16)
nextChar: '"' (位置: 16, 行: 1, 列: 17)
nextChar: ',' (位置: 17, 行: 1, 列: 18)
readString: Single-line string ended.
getNextToken: STRING token detected - sword
nextChar: ' ' (位置: 18, 行: 1, 列: 19)
getNextToken: COMMA token detected.
nextChar: '"' (位置: 19, 行: 1, 列: 20)
nextChar: 's' (位置: 20, 行: 1, 列: 21)
nextChar: 'h' (位置: 21, 行: 1, 列: 22)
nextChar: 'i' (位置: 22, 行: 1, 列: 23)
nextChar: 'e' (位置: 23, 行: 1, 列: 24)
nextChar: 'l' (位置: 24, 行: 1, 列: 25)
nextChar: 'd' (位置: 25, 行: 1, 列: 26)
nextChar: '"' (位置: 26, 行: 1, 列: 27)
nextChar: ']' (位置: 27, 行: 1, 列: 28)
readString: Single-line string ended.
getNextToken: STRING token detected - shield
nextChar: '
' (位置: 28, 行: 2, 列: 1)
getNextToken: RBRACKET token detected.
nextChar: 'p' (位置: 29, 行: 2, 列: 2)
getNextToken: NEWLINE token detected.
nextChar: 'l' (位置: 30, 行: 2, 列: 3)
nextChar: 'a' (位置: 31, 行: 2, 列: 4)
nextChar: 'y' (位置: 32, 行: 2, 列: 5)
nextChar: 'e' (位置: 33, 行: 2, 列: 6)
nextChar: 'r' (位置: 34, 行: 2, 列: 7)
nextChar: ' ' (位置: 35, 行: 2, 列: 8)
readIdentifier: 'player'
getNextToken: KEY token detected - player
nextChar: '=' (位置: 36, 行: 2, 列: 9)
nextChar: ' ' (位置: 37, 行: 2, 列: 10)
getNextToken: EQUALS token detected.
nextChar: '{' (位置: 38, 行: 2, 列: 11)
nextChar: ' ' (位置: 39, 行: 2, 列: 12)
getNextToken: LBRACE token detected. Entering inline table context.
nextChar: 'l' (位置: 40, 行: 2, 列: 13)
nextChar: 'e' (位置: 41, 行: 2, 列: 14)
nextChar: 'v' (位置: 42, 行: 2, 列: 15)
nextChar: 'e' (位置: 43, 行: 2, 列: 16)
nextChar: 'l' (位置: 44, 行: 2, 列: 17)
nextChar: ' ' (位置: 45, 行: 2, 列: 18)
readIdentifier: 'level'
getNextToken: KEY token detected - level
nextChar: '=' (位置: 46, 行: 2, 列: 19)
nextChar: ' ' (位置: 47, 行: 2, 列: 20)
getNextToken: EQUALS token detected.
nextChar: '1' (位置: 48, 行: 2, 列: 21)
nextChar: '0' (位置: 49, 行: 2, 列: 22)
nextChar: ',' (位置: 50, 行: 2, 列: 23)
getNextToken: INTEGER token detected - 10
nextChar: ' ' (位置: 51, 行: 2, 列: 24)
getNextToken: COMMA token detected.
nextChar: 'n' (位置: 52, 行: 2, 列: 25)
nextChar: 'a' (位置: 53, 行: 2, 列: 26)
nextChar: 'm' (位置: 54, 行: 2, 列: 27)
nextChar: 'e' (位置: 55, 行: 2, 列: 28)
nextChar: ' ' (位置: 56, 行: 2, 列: 29)
readIdentifier: 'name'
getNextToken: KEY token detected - name
nextChar: '=' (位置: 57, 行: 2, 列: 30)
nextChar: ' ' (位置: 58, 行: 2, 列: 31)
getNextToken: EQUALS token detected.
nextChar: '"' (位置: 59, 行: 2, 列: 32)
nextChar: 'H' (位置: 60, 行: 2, 列: 33)
nextChar: 'e' (位置: 61, 行: 2, 列: 34)
nextChar: 'r' (位置: 62, 行: 2, 列: 35)
nextChar: 'o' (位置: 63, 行: 2, 列: 36)
nextChar: '"' (位置: 64, 行: 2, 列: 37)
nextChar: '}' (位置: 65, 行: 2, 列: 38)
readString: Single-line string ended.
getNextToken: STRING token detected - Hero
nextChar: '
' (位置: 66, 行: 3, 列: 1)
getNextToken: RBRACE token detected. Exiting inline table context.
nextChar: End of text reached.
getNextToken: NEWLINE token detected.
getNextToken: End of text.
[PASS] FNTL round trip preserves nested

--- Test: toFNTLSingleLine ---
[PASS] Single line FNTL created
[PASS] Single line format correct

--- Test: toTOML - Basic ---
[PASS] TOML string created

--- Test: fromTOML - Basic ---
[PASS] Object parsed from TOML
[PASS] TOML title parsed
[PASS] TOML count parsed

--- Test: TOML - Round Trip ---
[PASS] TOML round trip preserves string
[PASS] TOML round trip preserves number

--- Test: toCompress - Basic ---
RLE 压缩完成。原长度: 26, 压缩后长度: 35
RLE 压缩后的结果: {"name":"T#1;est","valu#1;e":42}#1;
LZW 压缩后的结果: 007B0022006E0061006D00650022003A002200540100003101010065007300740022002C002200760061006C007501030111003A00340032007D0103
LZW 压缩并编码后的结果: {"name":"TĀ1āest","valuăđ:42}ă
[PASS] Compressed string created

--- Test: fromCompress - Basic ---
RLE 压缩完成。原长度: 26, 压缩后长度: 35
RLE 压缩后的结果: {"name":"T#1;est","valu#1;e":42}#1;
LZW 压缩后的结果: 007B0022006E0061006D00650022003A002200540100003101010065007300740022002C002200760061006C007501030111003A00340032007D0103
LZW 压缩并编码后的结果: {"name":"TĀ1āest","valuăđ:42}ă
编码解码后的结果: 007B0022006E0061006D00650022003A002200540100003101010065007300740022002C002200760061006C007501030111003A00340032007D0103
LZW 解压后的结果: {"name":"T#1;est","valu#1;e":42}#1;
RLE 解压缩完成。解压后长度: 26
RLE 解压后的结果: {"name":"Test","value":42}
[PASS] Object parsed from compressed
[PASS] Name property restored

--- Test: Compress - Round Trip ---
RLE 压缩完成。原长度: 44, 压缩后长度: 59
RLE 压缩后的结果: {"text":"H#1;ello World#1;","numbers#1;":[1,2,3,4#1;,5]}#1;
LZW 压缩后的结果: 007B002200740065007800740022003A002200480100003101010065006C006C006F00200057006F0072006C006401030022002C0022006E0075006D00620065007200730123003A005B0031002C0032002C0033002C00340103002C0035005D007D0103
LZW 压缩并编码后的结果: {"text":"HĀ1āello Worldă","numbersģ:[1,2,3,4ă,5]}ă
编码解码后的结果: 007B002200740065007800740022003A002200480100003101010065006C006C006F00200057006F0072006C006401030022002C0022006E0075006D00620065007200730123003A005B0031002C0032002C0033002C00340103002C0035005D007D0103
LZW 解压后的结果: {"text":"H#1;ello World#1;","numbers#1;":[1,2,3,4#1;,5]}#1;
RLE 解压缩完成。解压后长度: 44
RLE 解压后的结果: {"text":"Hello World","numbers":[1,2,3,4,5]}
[PASS] Compress round trip preserves data

--- Test: Edge Case - Empty Object ---
[PASS] Empty object cloned
[PASS] Empty object toString is {}

--- Test: Edge Case - Deeply Nested ---
[PASS] Deep object cloned - level 0
[PASS] Deep clone preserves all levels

--- Test: Edge Case - Large Object ---
[PASS] Large object cloned completely
[PASS] Large object values correct

--- Test: Edge Case - Special Characters in Keys ---
[PASS] Space in key preserved
[PASS] Dashes in key preserved

--- Test: Edge Case - Unicode Values ---
[PASS] Chinese characters preserved
[PASS] Japanese characters preserved

--- Test: Performance - Clone ---
Clone Performance: 57ms for 1000 iterations
[PASS] Clone performance acceptable

--- Test: Performance - Compare ---
Compare Performance: 130ms for 1000 iterations
[PASS] Compare performance acceptable

--- Test: Performance - ToString ---
ToString Performance: 191ms for 1000 iterations
[PASS] ToString performance acceptable

--- Test: Performance - Serialization ---
JSON Round Trip: 44ms for 100 iterations
[PASS] JSON serialization performance acceptable

=== FINAL TEST REPORT ===
Tests Passed: 155
Tests Failed: 0
Success Rate: 100%
ALL TESTS PASSED! ObjectUtil implementation is robust.

=== TEST COVERAGE ===
- clone: Deep cloning with circular reference handling
- cloneParameters: Object and string parameter parsing
- forEach: Object iteration
- compare: Object comparison
- hasProperties: Property existence check
- isSimple: Type checking
- toString: String representation
- isInternalKey: Internal key detection
- copyProperties: Property copying
- getKeys: Key extraction
- toArray: Array conversion
- equals/deepEquals: Equality checking
- size: Object size calculation
- JSON serialization: toJSON/fromJSON
- Base64 serialization: toBase64/fromBase64
- FNTL serialization: toFNTL/fromFNTL
- TOML serialization: toTOML/fromTOML
- Compress serialization: toCompress/fromCompress
========================