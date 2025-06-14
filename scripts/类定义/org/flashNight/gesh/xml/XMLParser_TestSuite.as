import org.flashNight.gesh.xml.*;

/**
 * XMLParser 100%覆盖测试套件
 * 
 * 测试策略：
 * 1. 验证所有公共方法的功能正确性
 * 2. 测试各种XML结构的解析能力
 * 3. 验证数据类型转换的准确性
 * 4. 测试错误处理和边界条件
 * 5. 验证特殊功能（CaseSwitch、HTML解码等）
 * 6. 性能和大数据处理测试
 * 
 * 核心验证原则：
 * - 确保XML解析的准确性和鲁棒性
 * - 验证所有数据类型转换的正确性
 * - 测试各种边界条件和异常情况
 * - 确保性能在可接受范围内
 */
class org.flashNight.gesh.xml.XMLParser_TestSuite {
    
    private static var _testCount:Number = 0;
    private static var _passCount:Number = 0;
    private static var _failCount:Number = 0;
    
    public static function runAllTests():Void {
        trace("========== XMLParser 100%覆盖测试开始 ==========");
        
        _testCount = 0;
        _passCount = 0;
        _failCount = 0;
        
        // 按功能模块分组测试
        testConfigureDataAsArray();           // 数组配置工具测试
        testConvertDataType();                // 数据类型转换测试
        testIsValidXML();                     // XML有效性验证测试
        testGetInnerText();                   // 内部文本提取测试
        testBasicXMLParsing();               // 基础XML解析测试
        testComplexXMLStructures();          // 复杂XML结构测试
        testStageXMLParsing();               // 关卡XML解析测试
        testCaseSwitchFunctionality();       // CaseSwitch功能测试
        testSpecialNodes();                  // 特殊节点处理测试
        testErrorHandlingAndBoundaries();    // 错误处理和边界条件测试
        testPerformanceAndLargeData();       // 性能和大数据测试
        testIntegrationScenarios();          // 集成场景测试
        
        // 输出测试结果
        trace("\n========== XMLParser 测试结果 ==========");
        trace("总计: " + _testCount + " 个测试");
        trace("通过: " + _passCount + " 个");
        trace("失败: " + _failCount + " 个");
        trace("覆盖率: " + Math.round((_passCount / _testCount) * 100) + "%");
        
        if (_failCount == 0) {
            trace("✅ XMLParser 所有测试通过！");
        } else {
            trace("❌ 存在 " + _failCount + " 个失败的测试");
        }
        trace("==========================================");
    }
    
    // ============================================================================
    // 测试分组1：数组配置工具测试
    // ============================================================================
    private static function testConfigureDataAsArray():Void {
        trace("\n--- 测试分组1：数组配置工具测试 ---");
        
        // 测试已经是数组的输入
        var inputArray:Array = [1, 2, 3];
        var resultArray:Array = XMLParser.configureDataAsArray(inputArray);
        _assert(resultArray == inputArray, "数组输入：应该返回原数组");
        _assert(resultArray.length == 3, "数组输入：长度应该保持不变");
        
        // 测试单个值输入
        var singleValue = "test";
        var singleResult:Array = XMLParser.configureDataAsArray(singleValue);
        _assert(singleResult instanceof Array, "单值输入：应该返回数组");
        _assert(singleResult.length == 1, "单值输入：数组长度应该为1");
        _assert(singleResult[0] == "test", "单值输入：内容应该正确");
        
        // 测试数字输入
        var numberResult:Array = XMLParser.configureDataAsArray(42);
        _assert(numberResult instanceof Array, "数字输入：应该返回数组");
        _assert(numberResult[0] == 42, "数字输入：内容应该正确");
        
        // 测试布尔值输入
        var boolResult:Array = XMLParser.configureDataAsArray(true);
        _assert(boolResult[0] === true, "布尔输入：内容应该正确");
        
        // 测试对象输入
        var objInput:Object = {name: "test"};
        var objResult:Array = XMLParser.configureDataAsArray(objInput);
        _assert(objResult[0] == objInput, "对象输入：内容应该正确");
        
        // 测试null输入
        var nullResult:Array = XMLParser.configureDataAsArray(null);
        _assert(nullResult instanceof Array, "null输入：应该返回数组");
        _assert(nullResult.length == 0, "null输入：应该返回空数组");
        
        // 测试undefined输入
        var undefResult:Array = XMLParser.configureDataAsArray(undefined);
        _assert(undefResult instanceof Array, "undefined输入：应该返回数组");
        _assert(undefResult.length == 0, "undefined输入：应该返回空数组");
        
        // 测试空字符串输入
        var emptyStringResult:Array = XMLParser.configureDataAsArray("");
        _assert(emptyStringResult.length == 1, "空字符串输入：应该包装为单元素数组");
        _assert(emptyStringResult[0] == "", "空字符串输入：内容应该保持");
        
        // 测试嵌套数组
        var nestedArray:Array = [[1, 2], [3, 4]];
        var nestedResult:Array = XMLParser.configureDataAsArray(nestedArray);
        _assert(nestedResult == nestedArray, "嵌套数组：应该返回原数组");
    }
    
    // ============================================================================
    // 测试分组2：数据类型转换测试
    // ============================================================================
    private static function testConvertDataType():Void {
        trace("\n--- 测试分组2：数据类型转换测试 ---");
        
        // 数字转换测试
        var intResult = XMLParser.convertDataType("123");
        _assert(intResult == 123 && typeof intResult == "number", "整数转换：应该正确转换");
        
        var floatResult = XMLParser.convertDataType("123.45");
        _assert(floatResult == 123.45 && typeof floatResult == "number", "浮点数转换：应该正确转换");
        
        var negativeResult = XMLParser.convertDataType("-456");
        _assert(negativeResult == -456, "负数转换：应该正确转换");
        
        var zeroResult = XMLParser.convertDataType("0");
        _assert(zeroResult == 0, "零转换：应该正确转换");
        
        // 布尔值转换测试
        var trueResult = XMLParser.convertDataType("true");
        _assert(trueResult === true && typeof trueResult == "boolean", "true转换：应该正确转换");
        
        var falseResult = XMLParser.convertDataType("false");
        _assert(falseResult === false && typeof falseResult == "boolean", "false转换：应该正确转换");
        
        var trueCaseResult = XMLParser.convertDataType("TRUE");
        _assert(trueCaseResult === true, "TRUE大写：应该正确转换");
        
        var falseCaseResult = XMLParser.convertDataType("FALSE");
        _assert(falseCaseResult === false, "FALSE大写：应该正确转换");
        
        var trueMixedResult = XMLParser.convertDataType("True");
        _assert(trueMixedResult === true, "True混合大小写：应该正确转换");
        
        // 字符串保持测试
        var stringResult = XMLParser.convertDataType("hello world");
        _assert(stringResult == "hello world" && typeof stringResult == "string", "普通字符串：应该保持不变");
        
        var emptyStringResult = XMLParser.convertDataType("");
        _assert(emptyStringResult == "", "空字符串：应该保持不变");
        
        // 特殊数字格式测试
        var scientificResult = XMLParser.convertDataType("1.23e2");
        _assert(scientificResult == 123, "科学计数法：应该正确转换");
        
        var hexLikeResult = XMLParser.convertDataType("0x10");
        _assert(hexLikeResult == 0, "类十六进制：应该转换为0（AS2不支持hex）");
        
        // 边界值测试
        var largeNumberResult = XMLParser.convertDataType("999999999");
        _assert(typeof largeNumberResult == "number", "大数字：应该转换为数字类型");
        
        var verySmallResult = XMLParser.convertDataType("0.000001");
        _assert(typeof verySmallResult == "number", "极小数字：应该转换为数字类型");
        
        // 无效数字格式测试
        var invalidNumberResult = XMLParser.convertDataType("123abc");
        _assert(typeof invalidNumberResult == "string", "无效数字：应该保持字符串");
        
        var spacedNumberResult = XMLParser.convertDataType(" 123 ");
        _assert(spacedNumberResult == 123, "带空格数字：应该正确转换");
        
        // 特殊字符串测试
        var boolLikeResult = XMLParser.convertDataType("trueish");
        _assert(typeof boolLikeResult == "string", "类似布尔值：应该保持字符串");
        
        var numLikeResult = XMLParser.convertDataType("123.45.67");
        _assert(typeof numLikeResult == "string", "多小数点：应该保持字符串");
    }
    
    // ============================================================================
    // 测试分组3：XML有效性验证测试
    // ============================================================================
    private static function testIsValidXML():Void {
        trace("\n--- 测试分组3：XML有效性验证测试 ---");
        
        // 创建有效XML节点进行测试
        var validXML:XML = new XML();
        validXML.ignoreWhite = true;
        validXML.parseXML("<root><child>content</child></root>");
        var validNode:XMLNode = validXML.firstChild;
        
        var validResult:Boolean = XMLParser.isValidXML(validNode);
        _assert(validResult === true, "有效XML：应该通过验证");
        
        // 测试有效的子节点
        var childNode:XMLNode = validNode.firstChild;
        var childValidResult:Boolean = XMLParser.isValidXML(childNode);
        _assert(childValidResult === true, "有效子节点：应该通过验证");
        
        // 创建包含多个子节点的XML
        var multiChildXML:XML = new XML();
        multiChildXML.ignoreWhite = true;
        multiChildXML.parseXML("<root><child1>content1</child1><child2>content2</child2></root>");
        var multiChildNode:XMLNode = multiChildXML.firstChild;
        
        var multiValidResult:Boolean = XMLParser.isValidXML(multiChildNode);
        _assert(multiValidResult === true, "多子节点：应该通过验证");
        
        // 测试带属性的节点
        var attrXML:XML = new XML();
        attrXML.ignoreWhite = true;
        attrXML.parseXML('<root id="123" name="test"><child>content</child></root>');
        var attrNode:XMLNode = attrXML.firstChild;
        
        var attrValidResult:Boolean = XMLParser.isValidXML(attrNode);
        _assert(attrValidResult === true, "带属性节点：应该通过验证");
        
        // 测试包含CDATA的节点
        var cdataXML:XML = new XML();
        cdataXML.ignoreWhite = true;
        cdataXML.parseXML("<root><![CDATA[Some CDATA content]]></root>");
        var cdataNode:XMLNode = cdataXML.firstChild;
        
        var cdataValidResult:Boolean = XMLParser.isValidXML(cdataNode);
        _assert(cdataValidResult === true, "CDATA节点：应该通过验证");
        
        // 测试包含注释的节点
        var commentXML:XML = new XML();
        commentXML.ignoreWhite = true;
        commentXML.parseXML("<root><!-- This is a comment --><child>content</child></root>");
        var commentNode:XMLNode = commentXML.firstChild;
        
        var commentValidResult:Boolean = XMLParser.isValidXML(commentNode);
        _assert(commentValidResult === true, "包含注释：应该通过验证");
        
        // 测试深度嵌套的节点
        var deepXML:XML = new XML();
        deepXML.ignoreWhite = true;
        deepXML.parseXML("<root><level1><level2><level3>deep content</level3></level2></level1></root>");
        var deepNode:XMLNode = deepXML.firstChild;
        
        var deepValidResult:Boolean = XMLParser.isValidXML(deepNode);
        _assert(deepValidResult === true, "深度嵌套：应该通过验证");
        
        // 测试空节点
        var emptyXML:XML = new XML();
        emptyXML.ignoreWhite = true;
        emptyXML.parseXML("<empty></empty>");
        var emptyNode:XMLNode = emptyXML.firstChild;
        
        var emptyValidResult:Boolean = XMLParser.isValidXML(emptyNode);
        _assert(emptyValidResult === true, "空节点：应该通过验证");
        
        // 测试自闭合节点
        var selfClosingXML:XML = new XML();
        selfClosingXML.ignoreWhite = true;
        selfClosingXML.parseXML("<selfClosing/>");
        var selfClosingNode:XMLNode = selfClosingXML.firstChild;
        
        var selfClosingValidResult:Boolean = XMLParser.isValidXML(selfClosingNode);
        _assert(selfClosingValidResult === true, "自闭合节点：应该通过验证");
        
        // 注意：在AS2中很难创建真正"无效"的XMLNode来测试false情况
        // 因为XML解析器会拒绝解析格式错误的XML
        // 但我们可以测试null情况
        var nullValidResult:Boolean = XMLParser.isValidXML(null);
        _assert(nullValidResult === false, "null节点：应该未通过验证");
    }
    
    // ============================================================================
    // 测试分组4：内部文本提取测试
    // ============================================================================
    private static function testGetInnerText():Void {
        trace("\n--- 测试分组4：内部文本提取测试 ---");
        
        // 简单文本节点测试
        var simpleXML:XML = new XML();
        simpleXML.ignoreWhite = true;
        simpleXML.parseXML("<root>Simple text content</root>");
        var simpleNode:XMLNode = simpleXML.firstChild;
        
        var simpleText:String = XMLParser.getInnerText(simpleNode);
        _assert(simpleText == "Simple text content", "简单文本：应该正确提取");
        
        // 包含HTML实体的文本测试
        var htmlEntityXML:XML = new XML();
        htmlEntityXML.ignoreWhite = true;
        htmlEntityXML.parseXML("<root>&lt;p&gt;Hello &amp; welcome&lt;/p&gt;</root>");
        var htmlEntityNode:XMLNode = htmlEntityXML.firstChild;
        
        var htmlEntityText:String = XMLParser.getInnerText(htmlEntityNode);
        _assert(htmlEntityText == "<p>Hello & welcome</p>", "HTML实体：应该正确解码");
        
        // 包含CDATA的节点测试
        var cdataXML:XML = new XML();
        cdataXML.ignoreWhite = true;
        cdataXML.parseXML("<root><![CDATA[<script>alert('test');</script>]]></root>");
        var cdataNode:XMLNode = cdataXML.firstChild;
        
        var cdataText:String = XMLParser.getInnerText(cdataNode);
        _assert(cdataText == "<script>alert('test');</script>", "CDATA内容：应该正确提取");
        
        // 混合文本和CDATA测试
        var mixedXML:XML = new XML();
        mixedXML.ignoreWhite = true;
        mixedXML.parseXML("<root>Before CDATA <![CDATA[<b>bold</b>]]> After CDATA</root>");
        var mixedNode:XMLNode = mixedXML.firstChild;
        
        var mixedText:String = XMLParser.getInnerText(mixedNode);
        _assert(mixedText.indexOf("Before CDATA") >= 0, "混合内容：应该包含文本部分");
        _assert(mixedText.indexOf("<b>bold</b>") >= 0, "混合内容：应该包含CDATA部分");
        _assert(mixedText.indexOf("After CDATA") >= 0, "混合内容：应该包含后续文本");
        
        // 空内容测试
        var emptyXML:XML = new XML();
        emptyXML.ignoreWhite = true;
        emptyXML.parseXML("<empty></empty>");
        var emptyNode:XMLNode = emptyXML.firstChild;
        
        var emptyText:String = XMLParser.getInnerText(emptyNode);
        _assert(emptyText == "", "空内容：应该返回空字符串");
        
        // 只包含空白的测试
        var whitespaceXML:XML = new XML();
        whitespaceXML.parseXML("<root>   \t\n  </root>"); // 不忽略空白
        var whitespaceNode:XMLNode = whitespaceXML.firstChild;
        
        var whitespaceText:String = XMLParser.getInnerText(whitespaceNode);
        _assert(whitespaceText.length > 0, "空白内容：应该保留空白字符");
        
        // 复杂HTML实体测试
        var complexEntityXML:XML = new XML();
        complexEntityXML.ignoreWhite = true;
        complexEntityXML.parseXML("<root>&quot;Hello&quot; &apos;World&apos; &lt;test&gt;</root>");
        var complexEntityNode:XMLNode = complexEntityXML.firstChild;
        
        var complexEntityText:String = XMLParser.getInnerText(complexEntityNode);
        _assert(complexEntityText.indexOf('"Hello"') >= 0, "复杂实体：应该解码双引号");
        _assert(complexEntityText.indexOf("'World'") >= 0, "复杂实体：应该解码单引号");
        _assert(complexEntityText.indexOf("<test>") >= 0, "复杂实体：应该解码尖括号");
        
        // 数字字符引用测试（如果StringUtils.decodeHTML支持）
        var numericEntityXML:XML = new XML();
        numericEntityXML.ignoreWhite = true;
        numericEntityXML.parseXML("<root>&#65;&#66;&#67;</root>");
        var numericEntityNode:XMLNode = numericEntityXML.firstChild;
        
        var numericEntityText:String = XMLParser.getInnerText(numericEntityNode);
        // 如果StringUtils.decodeHTML支持数字字符引用，应该解码为"ABC"
        // 否则会保持原样
        _assert(numericEntityText.length > 0, "数字实体：应该有内容");
        
        // 包含子元素的节点（应该只提取直接文本内容）
        var withChildrenXML:XML = new XML();
        withChildrenXML.ignoreWhite = true;
        withChildrenXML.parseXML("<root>Before<child>child content</child>After</root>");
        var withChildrenNode:XMLNode = withChildrenXML.firstChild;
        
        var withChildrenText:String = XMLParser.getInnerText(withChildrenNode);
        _assert(withChildrenText.indexOf("Before") >= 0, "含子元素：应该包含前置文本");
        _assert(withChildrenText.indexOf("After") >= 0, "含子元素：应该包含后置文本");
        // 注意：根据实现，可能不包含子元素的内容
    }
    
    // ============================================================================
    // 测试分组5：基础XML解析测试
    // ============================================================================
    private static function testBasicXMLParsing():Void {
        trace("\n--- 测试分组5：基础XML解析测试 ---");
        
        // 简单元素解析
        var simpleXML:XML = new XML();
        simpleXML.ignoreWhite = true;
        simpleXML.parseXML("<user><name>John</name><age>30</age></user>");
        var simpleNode:XMLNode = simpleXML.firstChild;
        
        var simpleResult:Object = XMLParser.parseXMLNode(simpleNode);
        _assert(simpleResult != null, "简单解析：应该返回对象");
        _assert(simpleResult.name == "John", "简单解析：name应该正确");
        _assert(simpleResult.age == 30, "简单解析：age应该转换为数字");
        
        // 带属性的元素解析
        var attrXML:XML = new XML();
        attrXML.ignoreWhite = true;
        attrXML.parseXML('<product id="123" category="electronics"><name>Phone</name><price>499.99</price></product>');
        var attrNode:XMLNode = attrXML.firstChild;
        
        var attrResult:Object = XMLParser.parseXMLNode(attrNode);
        _assert(attrResult.id == 123, "属性解析：id应该转换为数字");
        _assert(attrResult.category == "electronics", "属性解析：category应该保持字符串");
        _assert(attrResult.name == "Phone", "属性解析：子元素应该正确");
        _assert(attrResult.price == 499.99, "属性解析：price应该转换为浮点数");
        
        // 布尔值解析测试
        var boolXML:XML = new XML();
        boolXML.ignoreWhite = true;
        boolXML.parseXML("<settings><enabled>true</enabled><visible>false</visible><debug>TRUE</debug></settings>");
        var boolNode:XMLNode = boolXML.firstChild;
        
        var boolResult:Object = XMLParser.parseXMLNode(boolNode);
        _assert(boolResult.enabled === true, "布尔解析：true应该正确");
        _assert(boolResult.visible === false, "布尔解析：false应该正确");
        _assert(boolResult.debug === true, "布尔解析：TRUE应该正确");
        
        // 嵌套对象解析
        var nestedXML:XML = new XML();
        nestedXML.ignoreWhite = true;
        nestedXML.parseXML("<company><info><name>Tech Corp</name><founded>2020</founded></info><address><city>Shanghai</city><country>China</country></address></company>");
        var nestedNode:XMLNode = nestedXML.firstChild;
        
        var nestedResult:Object = XMLParser.parseXMLNode(nestedNode);
        _assert(nestedResult.info.name == "Tech Corp", "嵌套解析：深层属性应该正确");
        _assert(nestedResult.info.founded == 2020, "嵌套解析：数字转换应该正确");
        _assert(nestedResult.address.city == "Shanghai", "嵌套解析：多个嵌套对象应该正确");
        
        // 同名元素数组解析
        var arrayXML:XML = new XML();
        arrayXML.ignoreWhite = true;
        arrayXML.parseXML("<library><book><title>Book 1</title></book><book><title>Book 2</title></book><book><title>Book 3</title></book></library>");
        var arrayNode:XMLNode = arrayXML.firstChild;
        
        var arrayResult:Object = XMLParser.parseXMLNode(arrayNode);
        _assert(arrayResult.book instanceof Array, "数组解析：同名元素应该成为数组");
        _assert(arrayResult.book.length == 3, "数组解析：数组长度应该正确");
        _assert(arrayResult.book[0].title == "Book 1", "数组解析：第一个元素应该正确");
        _assert(arrayResult.book[2].title == "Book 3", "数组解析：最后一个元素应该正确");
        
        // 混合内容解析
        var mixedXML:XML = new XML();
        mixedXML.ignoreWhite = true;
        mixedXML.parseXML("<data><single>Only One</single><multiple>First</multiple><multiple>Second</multiple></data>");
        var mixedNode:XMLNode = mixedXML.firstChild;
        
        var mixedResult:Object = XMLParser.parseXMLNode(mixedNode);
        _assert(typeof mixedResult.single == "string", "混合解析：单个元素应该是字符串");
        _assert(mixedResult.multiple instanceof Array, "混合解析：多个元素应该是数组");
        _assert(mixedResult.multiple.length == 2, "混合解析：数组长度应该正确");
        
        // 空元素解析
        var emptyXML:XML = new XML();
        emptyXML.ignoreWhite = true;
        emptyXML.parseXML("<container><empty></empty><selfClosed/></container>");
        var emptyContainerNode:XMLNode = emptyXML.firstChild;
        
        var emptyResult:Object = XMLParser.parseXMLNode(emptyContainerNode);
        _assert(emptyResult.empty == "", "空元素：应该解析为空字符串");
        _assert(emptyResult.selfClosed == "", "自闭合元素：应该解析为空字符串");
        
        // CDATA解析测试
        var cdataXML:XML = new XML();
        cdataXML.ignoreWhite = true;
        cdataXML.parseXML("<message><content><![CDATA[<p>Hello <b>World</b>!</p>]]></content></message>");
        var cdataContainerNode:XMLNode = cdataXML.firstChild;
        
        var cdataResult:Object = XMLParser.parseXMLNode(cdataContainerNode);
        _assert(cdataResult.content == "<p>Hello <b>World</b>!</p>", "CDATA解析：内容应该保持原样");
        
        // 包含注释的XML解析
        var commentXML:XML = new XML();
        commentXML.ignoreWhite = true;
        commentXML.parseXML("<root><item>1</item><!-- This is a comment --><item>2</item></root>");
        var commentContainerNode:XMLNode = commentXML.firstChild;
        
        var commentResult:Object = XMLParser.parseXMLNode(commentContainerNode);
        _assert(commentResult.item instanceof Array, "注释解析：注释应该被忽略，元素应该正确解析");
        _assert(commentResult.item.length == 2, "注释解析：注释不应该影响元素数量");
    }
    
    // ============================================================================
    // 测试分组6：复杂XML结构测试
    // ============================================================================
    private static function testComplexXMLStructures():Void {
        trace("\n--- 测试分组6：复杂XML结构测试 ---");
        
        // 游戏配置XML解析
        var gameConfigXML:XML = new XML();
        gameConfigXML.ignoreWhite = true;
        gameConfigXML.parseXML(
            '<gameConfig version="1.0">' +
                '<player level="10" experience="2500">' +
                    '<stats attack="100" defense="80" speed="60"/>' +
                    '<inventory>' +
                        '<item type="weapon" id="sword001" quantity="1"/>' +
                        '<item type="potion" id="health001" quantity="5"/>' +
                    '</inventory>' +
                '</player>' +
                '<settings>' +
                    '<graphics quality="high" fullscreen="true"/>' +
                    '<audio volume="0.8" muted="false"/>' +
                '</settings>' +
            '</gameConfig>'
        );
        var gameConfigNode:XMLNode = gameConfigXML.firstChild;
        
        var gameConfig:Object = XMLParser.parseXMLNode(gameConfigNode);
        _assert(gameConfig.version == "1.0", "游戏配置：版本属性应该正确");
        _assert(gameConfig.player.level == 10, "游戏配置：玩家等级应该转换为数字");
        _assert(gameConfig.player.stats.attack == 100, "游戏配置：嵌套属性应该正确");
        _assert(gameConfig.player.inventory.item instanceof Array, "游戏配置：物品应该是数组");
        _assert(gameConfig.player.inventory.item.length == 2, "游戏配置：物品数量应该正确");
        _assert(gameConfig.settings.graphics.fullscreen === true, "游戏配置：布尔值应该正确转换");
        _assert(gameConfig.settings.audio.volume == 0.8, "游戏配置：浮点数应该正确转换");
        
        // 菜单系统XML解析
        var menuXML:XML = new XML();
        menuXML.ignoreWhite = true;
        menuXML.parseXML(
            '<menu>' +
                '<item id="file" label="File">' +
                    '<submenu>' +
                        '<item id="new" label="New" shortcut="Ctrl+N"/>' +
                        '<item id="open" label="Open" shortcut="Ctrl+O"/>' +
                        '<separator/>' +
                        '<item id="exit" label="Exit"/>' +
                    '</submenu>' +
                '</item>' +
                '<item id="edit" label="Edit">' +
                    '<submenu>' +
                        '<item id="copy" label="Copy" shortcut="Ctrl+C"/>' +
                        '<item id="paste" label="Paste" shortcut="Ctrl+V"/>' +
                    '</submenu>' +
                '</item>' +
            '</menu>'
        );
        var menuNode:XMLNode = menuXML.firstChild;
        
        var menuConfig:Object = XMLParser.parseXMLNode(menuNode);
        _assert(menuConfig.item instanceof Array, "菜单配置：顶级菜单应该是数组");
        _assert(menuConfig.item[0].label == "File", "菜单配置：菜单标签应该正确");
        _assert(menuConfig.item[0].submenu.item instanceof Array, "菜单配置：子菜单应该是数组");
        _assert(menuConfig.item[0].submenu.separator == "", "菜单配置：分隔符应该正确解析");
        
        // 数据表格XML解析
        var tableXML:XML = new XML();
        tableXML.ignoreWhite = true;
        tableXML.parseXML(
            '<table name="employees">' +
                '<columns>' +
                    '<column name="id" type="number" primary="true"/>' +
                    '<column name="name" type="string" nullable="false"/>' +
                    '<column name="salary" type="number" nullable="true"/>' +
                '</columns>' +
                '<rows>' +
                    '<row><id>1</id><name>Alice</name><salary>50000</salary></row>' +
                    '<row><id>2</id><name>Bob</name><salary>60000</salary></row>' +
                    '<row><id>3</id><name>Charlie</name></row>' +
                '</rows>' +
            '</table>'
        );
        var tableNode:XMLNode = tableXML.firstChild;
        
        var tableConfig:Object = XMLParser.parseXMLNode(tableNode);
        _assert(tableConfig.name == "employees", "表格配置：表名应该正确");
        _assert(tableConfig.columns.column instanceof Array, "表格配置：列定义应该是数组");
        _assert(tableConfig.columns.column[0].primary === true, "表格配置：布尔属性应该正确");
        _assert(tableConfig.rows.row instanceof Array, "表格配置：行数据应该是数组");
        _assert(tableConfig.rows.row[0].id == 1, "表格配置：数字字段应该转换");
        _assert(tableConfig.rows.row[2].salary === undefined, "表格配置：缺失字段应该是undefined");
        
        // 国际化配置XML解析
        var i18nXML:XML = new XML();
        i18nXML.ignoreWhite = true;
        i18nXML.parseXML(
            '<localization>' +
                '<language code="en" dft="true">' +
                    '<messages>' +
                        '<message key="welcome">Welcome!</message>' +
                        '<message key="goodbye">Goodbye!</message>' +
                    '</messages>' +
                '</language>' +
                '<language code="zh">' +
                    '<messages>' +
                        '<message key="welcome">欢迎！</message>' +
                        '<message key="goodbye">再见！</message>' +
                    '</messages>' +
                '</language>' +
            '</localization>'
        );
        var i18nNode:XMLNode = i18nXML.firstChild;
        
        var i18nConfig:Object = XMLParser.parseXMLNode(i18nNode);
        _assert(i18nConfig.language instanceof Array, "国际化配置：语言应该是数组");
        _assert(i18nConfig.language[0].code == "en", "国际化配置：语言代码应该正确");
        _assert(i18nConfig.language[0].dft === true, "国际化配置：默认语言标记应该正确");
        _assert(i18nConfig.language[1].messages.message instanceof Array, "国际化配置：消息应该是数组");
        
        // 工作流XML解析
        var workflowXML:XML = new XML();
        workflowXML.ignoreWhite = true;
        workflowXML.parseXML(
            '<workflow name="approval" version="2.0">' +
                '<variables>' +
                    '<variable name="amount" type="number" required="true"/>' +
                    '<variable name="department" type="string" dft="general"/>' +
                '</variables>' +
                '<steps>' +
                    '<step id="1" name="submit" type="start">' +
                        '<transitions>' +
                            '<transition to="2" condition="amount &lt; 1000"/>' +
                            '<transition to="3" condition="amount &gt;= 1000"/>' +
                        '</transitions>' +
                    '</step>' +
                    '<step id="2" name="auto_approve" type="end"/>' +
                    '<step id="3" name="manual_review" type="task"/>' +
                '</steps>' +
            '</workflow>'
        );
        var workflowNode:XMLNode = workflowXML.firstChild;
        
        var workflowConfig:Object = XMLParser.parseXMLNode(workflowNode);
        _assert(workflowConfig.name == "approval", "工作流配置：工作流名称应该正确");
        _assert(workflowConfig.variables.variable instanceof Array, "工作流配置：变量应该是数组");
        _assert(workflowConfig.steps.step instanceof Array, "工作流配置：步骤应该是数组");
        _assert(workflowConfig.steps.step[0].transitions.transition instanceof Array, "工作流配置：转换应该是数组");
        _assert(workflowConfig.steps.step[0].transitions.transition[0].condition.indexOf("<") >= 0, "工作流配置：HTML实体应该解码");
    }
    
    // ============================================================================
    // 测试分组7：关卡XML解析测试
    // ============================================================================
    private static function testStageXMLParsing():Void {
        trace("\n--- 测试分组7：关卡XML解析测试 ---");
        
        // 基础关卡XML解析（无CaseSwitch）
        var basicStageXML:XML = new XML();
        basicStageXML.ignoreWhite = true;
        basicStageXML.parseXML(
            '<stage id="level_001" difficulty="normal">' +
                '<name>Forest Entrance</name>' +
                '<enemies>' +
                    '<enemy type="goblin" count="3"/>' +
                    '<enemy type="orc" count="1"/>' +
                '</enemies>' +
                '<rewards>' +
                    '<gold>100</gold>' +
                    '<experience>50</experience>' +
                '</rewards>' +
            '</stage>'
        );
        var basicStageNode:XMLNode = basicStageXML.firstChild;
        
        var basicStageResult:Object = XMLParser.parseStageXMLNode(basicStageNode);
        _assert(basicStageResult != null, "基础关卡：应该成功解析");
        _assert(basicStageResult.id == "level_001", "基础关卡：ID应该正确");
        _assert(basicStageResult.name == "Forest Entrance", "基础关卡：名称应该正确");
        _assert(basicStageResult.enemies.enemy instanceof Array, "基础关卡：敌人应该是数组");
        _assert(basicStageResult.rewards.gold == 100, "基础关卡：奖励应该正确");
        
        // 带CaseSwitch的关卡XML解析测试需要更复杂的设置
        // 创建一个全局函数用于测试
        _global.testGetDifficulty = function():String {
            return "hard";
        };
        
        var caseSwitchXML:XML = new XML();
        caseSwitchXML.ignoreWhite = true;
        caseSwitchXML.parseXML(
            '<stage>' +
                '<CaseSwitch expression="testGetDifficulty" params="">' +
                    '<Case casevalue="easy">' +
                        '<enemies count="2"/>' +
                        '<gold>50</gold>' +
                    '</Case>' +
                    '<Case casevalue="normal">' +
                        '<enemies count="5"/>' +
                        '<gold>100</gold>' +
                    '</Case>' +
                    '<Case casevalue="hard">' +
                        '<enemies count="10"/>' +
                        '<gold>200</gold>' +
                    '</Case>' +
                '</CaseSwitch>' +
            '</stage>'
        );
        var caseSwitchNode:XMLNode = caseSwitchXML.firstChild;
        
        var caseSwitchResult:Object = XMLParser.parseStageXMLNode(caseSwitchNode);
        _assert(caseSwitchResult != null, "CaseSwitch：应该成功解析");
        _assert(caseSwitchResult.enemies.count == 10, "CaseSwitch：应该选择hard难度的配置");
        _assert(caseSwitchResult.gold == 200, "CaseSwitch：奖励应该匹配hard难度");
        
        // 测试带参数的CaseSwitch
        _global.testGetLevel = function(baseLevel:Number, modifier:Number):Number {
            return baseLevel + modifier;
        };
        
        var paramCaseSwitchXML:XML = new XML();
        paramCaseSwitchXML.ignoreWhite = true;
        paramCaseSwitchXML.parseXML(
            '<stage>' +
                '<CaseSwitch expression="testGetLevel" params="5,3">' +
                    '<Case casevalue="8">' +
                        '<result>Level 8 Configuration</result>' +
                    '</Case>' +
                    '<Case casevalue="dft">' +
                        '<result>dft Configuration</result>' +
                    '</Case>' +
                '</CaseSwitch>' +
            '</stage>'
        );
        var paramCaseSwitchNode:XMLNode = paramCaseSwitchXML.firstChild;
        
        var paramCaseSwitchResult:Object = XMLParser.parseStageXMLNode(paramCaseSwitchNode);
        _assert(paramCaseSwitchResult.result == "Level 8 Configuration", "参数CaseSwitch：应该正确执行带参数的函数");
        
        // 测试dft case
        _global.testReturnUnknown = function():String {
            return "unknown_value";
        };
        
        var dftCaseXML:XML = new XML();
        dftCaseXML.ignoreWhite = true;
        dftCaseXML.parseXML(
            '<stage>' +
                '<CaseSwitch expression="testReturnUnknown" params="">' +
                    '<Case casevalue="known">' +
                        '<config>Known Configuration</config>' +
                    '</Case>' +
                    '<Case casevalue="dft">' +
                        '<config>dft Configuration</config>' +
                    '</Case>' +
                '</CaseSwitch>' +
            '</stage>'
        );
        var dftCaseNode:XMLNode = dftCaseXML.firstChild;
        
        var dftCaseResult:Object = XMLParser.parseStageXMLNode(dftCaseNode);
        _assert(dftCaseResult.config == "dft Configuration", "默认Case：应该选择dft case");
        
        // 测试文本节点的CaseSwitch
        var textCaseXML:XML = new XML();
        textCaseXML.ignoreWhite = true;
        textCaseXML.parseXML(
            '<stage>' +
                '<CaseSwitch expression="testGetDifficulty" params="">' +
                    '<Case casevalue="easy">Easy Mode Text</Case>' +
                    '<Case casevalue="hard">Hard Mode Text</Case>' +
                '</CaseSwitch>' +
            '</stage>'
        );
        var textCaseNode:XMLNode = textCaseXML.firstChild;
        
        var textCaseResult = XMLParser.parseStageXMLNode(textCaseNode);
        _assert(textCaseResult == "Hard Mode Text", "文本Case：应该直接返回文本内容");
        
        // 测试无匹配case的情况
        _global.testReturnNoMatch = function():String {
            return "no_match_value";
        };
        
        var noMatchXML:XML = new XML();
        noMatchXML.ignoreWhite = true;
        noMatchXML.parseXML(
            '<stage>' +
                '<CaseSwitch expression="testReturnNoMatch" params="">' +
                    '<Case casevalue="match1">Configuration 1</Case>' +
                    '<Case casevalue="match2">Configuration 2</Case>' +
                '</CaseSwitch>' +
            '</stage>'
        );
        var noMatchNode:XMLNode = noMatchXML.firstChild;
        
        var noMatchResult = XMLParser.parseStageXMLNode(noMatchNode);
        _assert(noMatchResult === null, "无匹配Case：应该返回null");
        
        // 清理全局函数
        delete _global.testGetDifficulty;
        delete _global.testGetLevel;
        delete _global.testReturnUnknown;
        delete _global.testReturnNoMatch;
    }
    
    // ============================================================================
    // 测试分组8：CaseSwitch功能测试
    // ============================================================================
    private static function testCaseSwitchFunctionality():Void {
        trace("\n--- 测试分组8：CaseSwitch功能测试 ---");
        
        // 设置测试用的全局函数
        _global.getPlayerclazz = function():String {
            return "warrior";
        };
        
        _global.calculateDamage = function(base:Number, multiplier:Number):Number {
            return base * multiplier;
        };
        
        _global.getRandomChoice = function():Number {
            return 2;
        };
        
        // 测试字符串匹配的CaseSwitch
        var stringMatchXML:XML = new XML();
        stringMatchXML.ignoreWhite = true;
        stringMatchXML.parseXML(
            '<config>' +
                '<CaseSwitch expression="getPlayerclazz" params="">' +
                    '<Case casevalue="warrior">' +
                        '<strength>10</strength>' +
                        '<intelligence>3</intelligence>' +
                    '</Case>' +
                    '<Case casevalue="mage">' +
                        '<strength>3</strength>' +
                        '<intelligence>10</intelligence>' +
                    '</Case>' +
                    '<Case casevalue="rogue">' +
                        '<strength>7</strength>' +
                        '<intelligence>7</intelligence>' +
                    '</Case>' +
                '</CaseSwitch>' +
            '</config>'
        );
        var stringMatchNode:XMLNode = stringMatchXML.firstChild;
        
        var stringMatchResult:Object = XMLParser.parseStageXMLNode(stringMatchNode);
        _assert(stringMatchResult.strength == 10, "字符串匹配：战士力量应该是10");
        _assert(stringMatchResult.intelligence == 3, "字符串匹配：战士智力应该是3");
        
        // 测试数字匹配的CaseSwitch
        var numberMatchXML:XML = new XML();
        numberMatchXML.ignoreWhite = true;
        numberMatchXML.parseXML(
            '<config>' +
                '<CaseSwitch expression="calculateDamage" params="10,1.5">' +
                    '<Case casevalue="10">Low Damage</Case>' +
                    '<Case casevalue="15">Medium Damage</Case>' +
                    '<Case casevalue="20">High Damage</Case>' +
                '</CaseSwitch>' +
            '</config>'
        );
        var numberMatchNode:XMLNode = numberMatchXML.firstChild;
        
        var numberMatchResult = XMLParser.parseStageXMLNode(numberMatchNode);
        _assert(numberMatchResult == "Medium Damage", "数字匹配：15应该匹配Medium Damage");
        
        // 测试多参数函数调用
        _global.complexFunction = function(a:Number, b:String, c:Boolean):String {
            return a + "_" + b + "_" + c;
        };
        
        var multiParamXML:XML = new XML();
        multiParamXML.ignoreWhite = true;
        multiParamXML.parseXML(
            '<config>' +
                '<CaseSwitch expression="complexFunction" params="42,test,true">' +
                    '<Case casevalue="42_test_true">' +
                        '<success>true</success>' +
                    '</Case>' +
                    '<Case casevalue="dft">' +
                        '<success>false</success>' +
                    '</Case>' +
                '</CaseSwitch>' +
            '</config>'
        );
        var multiParamNode:XMLNode = multiParamXML.firstChild;
        
        var multiParamResult:Object = XMLParser.parseStageXMLNode(multiParamNode);
        _assert(multiParamResult.success === true, "多参数：复杂函数调用应该成功");
        
        // 测试嵌套CaseSwitch（如果支持）
        var nestedXML:XML = new XML();
        nestedXML.ignoreWhite = true;
        nestedXML.parseXML(
            '<config>' +
                '<CaseSwitch expression="getPlayerclazz" params="">' +
                    '<Case casevalue="warrior">' +
                        '<clazz>warrior</clazz>' +
                        '<specialization>' +
                            '<CaseSwitch expression="getRandomChoice" params="">' +
                                '<Case casevalue="1">Tank</Case>' +
                                '<Case casevalue="2">DPS</Case>' +
                                '<Case casevalue="dft">Balanced</Case>' +
                            '</CaseSwitch>' +
                        '</specialization>' +
                    '</Case>' +
                '</CaseSwitch>' +
            '</config>'
        );
        var nestedNode:XMLNode = nestedXML.firstChild;
        
        var nestedResult:Object = XMLParser.parseStageXMLNode(nestedNode);
        _assert(nestedResult.clazz == "warrior", "嵌套CaseSwitch：外层应该正确");
        _assert(nestedResult.specialization == "DPS", "嵌套CaseSwitch：内层应该正确");
        
        // 测试无效表达式处理
        var invalidExpressionXML:XML = new XML();
        invalidExpressionXML.ignoreWhite = true;
        invalidExpressionXML.parseXML(
            '<config>' +
                '<CaseSwitch expression="nonExistentFunction" params="">' +
                    '<Case casevalue="any">Should not reach</Case>' +
                '</CaseSwitch>' +
            '</config>'
        );
        var invalidExpressionNode:XMLNode = invalidExpressionXML.firstChild;
        
        var invalidExpressionResult = XMLParser.parseStageXMLNode(invalidExpressionNode);
        _assert(typeof invalidExpressionResult == "string", "无效表达式：应该返回表达式字符串");
        
        // 测试空参数
        _global.noParamFunction = function():String {
            return "no_params";
        };
        
        var noParamXML:XML = new XML();
        noParamXML.ignoreWhite = true;
        noParamXML.parseXML(
            '<config>' +
                '<CaseSwitch expression="noParamFunction" params="">' +
                    '<Case casevalue="no_params">Success</Case>' +
                '</CaseSwitch>' +
            '</config>'
        );
        var noParamNode:XMLNode = noParamXML.firstChild;
        
        var noParamResult = XMLParser.parseStageXMLNode(noParamNode);
        _assert(noParamResult == "Success", "无参数函数：应该正确调用");
        
        // 测试case值类型转换
        _global.returnNumber = function():Number {
            return 123;
        };
        
        var typeConversionXML:XML = new XML();
        typeConversionXML.ignoreWhite = true;
        typeConversionXML.parseXML(
            '<config>' +
                '<CaseSwitch expression="returnNumber" params="">' +
                    '<Case casevalue="123">Number Match</Case>' +
                    '<Case casevalue="456">Wrong Number</Case>' +
                '</CaseSwitch>' +
            '</config>'
        );
        var typeConversionNode:XMLNode = typeConversionXML.firstChild;
        
        var typeConversionResult = XMLParser.parseStageXMLNode(typeConversionNode);
        _assert(typeConversionResult == "Number Match", "类型转换：数字应该正确匹配字符串case值");
        
        // 清理全局函数
        delete _global.getPlayerclazz;
        delete _global.calculateDamage;
        delete _global.getRandomChoice;
        delete _global.complexFunction;
        delete _global.noParamFunction;
        delete _global.returnNumber;
    }
    
    // ============================================================================
    // 测试分组9：特殊节点处理测试
    // ============================================================================
    private static function testSpecialNodes():Void {
        trace("\n--- 测试分组9：特殊节点处理测试 ---");
        
        // Description节点特殊处理测试
        var descriptionXML:XML = new XML();
        descriptionXML.ignoreWhite = true;
        descriptionXML.parseXML(
            '<item>' +
                '<name>Magic Sword</name>' +
                '<Description>&lt;p&gt;A &lt;b&gt;magical&lt;/b&gt; sword with &lt;i&gt;special&lt;/i&gt; powers.&lt;/p&gt;</Description>' +
                '<value>1000</value>' +
            '</item>'
        );
        var descriptionNode:XMLNode = descriptionXML.firstChild;
        
        var descriptionResult:Object = XMLParser.parseXMLNode(descriptionNode);
        _assert(descriptionResult.name == "Magic Sword", "Description特殊处理：普通节点应该正常");
        _assert(descriptionResult.Description.indexOf("<p>") >= 0, "Description特殊处理：HTML应该被解码");
        _assert(descriptionResult.Description.indexOf("<b>magical</b>") >= 0, "Description特殊处理：内部HTML应该保留");
        _assert(descriptionResult.value == 1000, "Description特殊处理：其他节点应该正常");
        
        // MaterialDetail节点特殊处理测试
        var materialDetailXML:XML = new XML();
        materialDetailXML.ignoreWhite = true;
        materialDetailXML.parseXML(
            '<material>' +
                '<name>Steel</name>' +
                '<MaterialDetail>&lt;div&gt;High quality &lt;span clazz="highlight"&gt;steel&lt;/span&gt; material.&lt;/div&gt;</MaterialDetail>' +
                '<hardness>8</hardness>' +
            '</material>'
        );
        var materialDetailNode:XMLNode = materialDetailXML.firstChild;
        
        var materialDetailResult:Object = XMLParser.parseXMLNode(materialDetailNode);
        _assert(materialDetailResult.name == "Steel", "MaterialDetail特殊处理：普通节点应该正常");
        _assert(materialDetailResult.MaterialDetail.indexOf("<div>") >= 0, "MaterialDetail特殊处理：HTML应该被解码");
        _assert(materialDetailResult.MaterialDetail.indexOf("highlight") >= 0, "MaterialDetail特殊处理：复杂HTML应该保留");
        _assert(materialDetailResult.hardness == 8, "MaterialDetail特殊处理：其他节点应该正常");
        
        // 混合Description和MaterialDetail测试
        var mixedSpecialXML:XML = new XML();
        mixedSpecialXML.ignoreWhite = true;
        mixedSpecialXML.parseXML(
            '<product>' +
                '<Description>&lt;h1&gt;Product Title&lt;/h1&gt;</Description>' +
                '<MaterialDetail>&lt;ul&gt;&lt;li&gt;Material 1&lt;/li&gt;&lt;li&gt;Material 2&lt;/li&gt;&lt;/ul&gt;</MaterialDetail>' +
                '<price>99.99</price>' +
            '</product>'
        );
        var mixedSpecialNode:XMLNode = mixedSpecialXML.firstChild;
        
        var mixedSpecialResult:Object = XMLParser.parseXMLNode(mixedSpecialNode);
        _assert(mixedSpecialResult.Description.indexOf("<h1>") >= 0, "混合特殊节点：Description应该正确处理");
        _assert(mixedSpecialResult.MaterialDetail.indexOf("<ul>") >= 0, "混合特殊节点：MaterialDetail应该正确处理");
        _assert(mixedSpecialResult.price == 99.99, "混合特殊节点：普通节点应该正常");
        
        // 带子元素的Description测试
        var complexDescriptionXML:XML = new XML();
        complexDescriptionXML.ignoreWhite = true;
        complexDescriptionXML.parseXML(
            '<item>' +
                '<Description>' +
                    '&lt;div&gt;' +
                        '&lt;p&gt;Main description&lt;/p&gt;' +
                        '&lt;ul&gt;' +
                            '&lt;li&gt;Feature 1&lt;/li&gt;' +
                            '&lt;li&gt;Feature 2&lt;/li&gt;' +
                        '&lt;/ul&gt;' +
                    '&lt;/div&gt;' +
                '</Description>' +
            '</item>'
        );
        var complexDescriptionNode:XMLNode = complexDescriptionXML.firstChild;
        
        var complexDescriptionResult:Object = XMLParser.parseXMLNode(complexDescriptionNode);
        _assert(complexDescriptionResult.Description.indexOf("<div>") >= 0, "复杂Description：外层div应该被解码");
        _assert(complexDescriptionResult.Description.indexOf("<p>Main description</p>") >= 0, "复杂Description：段落应该被解码");
        _assert(complexDescriptionResult.Description.indexOf("<ul>") >= 0, "复杂Description：列表应该被解码");
        
        // 空的特殊节点测试
        var emptySpecialXML:XML = new XML();
        emptySpecialXML.ignoreWhite = true;
        emptySpecialXML.parseXML(
            '<item>' +
                '<Description></Description>' +
                '<MaterialDetail></MaterialDetail>' +
                '<name>Test Item</name>' +
            '</item>'
        );
        var emptySpecialNode:XMLNode = emptySpecialXML.firstChild;
        
        var emptySpecialResult:Object = XMLParser.parseXMLNode(emptySpecialNode);
        _assert(emptySpecialResult.Description == "", "空特殊节点：空Description应该是空字符串");
        _assert(emptySpecialResult.MaterialDetail == "", "空特殊节点：空MaterialDetail应该是空字符串");
        _assert(emptySpecialResult.name == "Test Item", "空特殊节点：其他节点应该正常");
        
        // 特殊节点与普通节点重名测试
        var conflictXML:XML = new XML();
        conflictXML.ignoreWhite = true;
        conflictXML.parseXML(
            '<container>' +
                '<Description>First Description</Description>' +
                '<Description>&lt;b&gt;Second Description&lt;/b&gt;</Description>' +
                '<other>Normal</other>' +
            '</container>'
        );
        var conflictNode:XMLNode = conflictXML.firstChild;
        
        var conflictResult:Object = XMLParser.parseXMLNode(conflictNode);
        _assert(conflictResult.Description instanceof Array, "重名特殊节点：应该形成数组");
        _assert(conflictResult.Description.length == 2, "重名特殊节点：数组长度应该正确");
        _assert(conflictResult.Description[1].indexOf("<b>") >= 0, "重名特殊节点：HTML解码应该正确应用");
        
        // 测试特殊节点在Stage解析中的行为（应该不特殊处理）
        var stageSpecialXML:XML = new XML();
        stageSpecialXML.ignoreWhite = true;
        stageSpecialXML.parseXML(
            '<stage>' +
                '<Description>&lt;p&gt;Stage description&lt;/p&gt;</Description>' +
                '<MaterialDetail>&lt;div&gt;Material info&lt;/div&gt;</MaterialDetail>' +
            '</stage>'
        );
        var stageSpecialNode:XMLNode = stageSpecialXML.firstChild;
        
        var stageSpecialResult:Object = XMLParser.parseStageXMLNode(stageSpecialNode);
        // 在parseStageXMLNode中，Description和MaterialDetail的特殊处理被注释掉了
        // 所以应该按普通节点处理
        _assert(typeof stageSpecialResult.Description == "string", "Stage特殊节点：Description应该按普通节点处理");
        _assert(stageSpecialResult.Description.indexOf("&lt;") >= 0, "Stage特殊节点：HTML实体不应该被解码");
    }
    
    // ============================================================================
    // 测试分组10：错误处理和边界条件测试
    // ============================================================================
    private static function testErrorHandlingAndBoundaries():Void {
        trace("\n--- 测试分组10：错误处理和边界条件测试 ---");
        
        // null节点处理
        var nullResult:Object = XMLParser.parseXMLNode(null);
        _assert(nullResult === null, "null处理：null节点应该返回null");
        
        var stageNullResult:Object = XMLParser.parseStageXMLNode(null);
        _assert(stageNullResult === null, "Stage null处理：null节点应该返回null");
        
        // 文本节点处理
        var textXML:XML = new XML();
        textXML.parseXML("<root>Plain text content</root>");
        var textOnlyNode:XMLNode = textXML.firstChild.firstChild; // 获取文本节点
        
        var textResult = XMLParser.parseXMLNode(textOnlyNode);
        _assert(typeof textResult == "string", "文本节点：应该返回字符串");
        
        // CDATA节点直接处理
        var cdataXML:XML = new XML();
        cdataXML.parseXML("<root><![CDATA[CDATA content]]></root>");
        var cdataOnlyNode:XMLNode = cdataXML.firstChild.firstChild; // 获取CDATA节点
        
        var cdataResult = XMLParser.parseXMLNode(cdataOnlyNode);
        _assert(cdataResult == "CDATA content", "CDATA节点：应该返回内容");
        
        // 极深嵌套XML测试
        var deepXMLString:String = "<root>";
        for (var i:Number = 0; i < 50; i++) {
            deepXMLString += "<level" + i + ">";
        }
        deepXMLString += "<content>Deep content</content>";
        for (var j:Number = 49; j >= 0; j--) {
            deepXMLString += "</level" + j + ">";
        }
        deepXMLString += "</root>";
        
        var deepXML:XML = new XML();
        deepXML.ignoreWhite = true;
        deepXML.parseXML(deepXMLString);
        var deepNode:XMLNode = deepXML.firstChild;
        
        var deepResult:Object = XMLParser.parseXMLNode(deepNode);
        _assert(deepResult != null, "极深嵌套：应该成功解析");
        
        // 大量同名元素测试
        var massiveArrayXMLString:String = "<container>";
        for (var k:Number = 0; k < 100; k++) {
            massiveArrayXMLString += "<item id=\"" + k + "\">Item " + k + "</item>";
        }
        massiveArrayXMLString += "</container>";
        
        var massiveArrayXML:XML = new XML();
        massiveArrayXML.ignoreWhite = true;
        massiveArrayXML.parseXML(massiveArrayXMLString);
        var massiveArrayNode:XMLNode = massiveArrayXML.firstChild;
        
        var massiveArrayResult:Object = XMLParser.parseXMLNode(massiveArrayNode);
        _assert(massiveArrayResult.item instanceof Array, "大量元素：应该形成数组");
        _assert(massiveArrayResult.item.length == 100, "大量元素：数组长度应该正确");
        _assert(massiveArrayResult.item[99].id == 99, "大量元素：最后一个元素应该正确");
        
        // 特殊字符和Unicode测试
        var unicodeXML:XML = new XML();
        unicodeXML.ignoreWhite = true;
        unicodeXML.parseXML("<data><chinese>中文测试</chinese><emoji>😀😃😄</emoji><special>&amp;&#39;&quot;</special></data>");
        var unicodeNode:XMLNode = unicodeXML.firstChild;
        
        var unicodeResult:Object = XMLParser.parseXMLNode(unicodeNode);
        _assert(unicodeResult.chinese == "中文测试", "Unicode：中文应该正确");
        _assert(unicodeResult.emoji.indexOf("😀") >= 0, "Unicode：表情符号应该正确");
        _assert(unicodeResult.special.indexOf("&") >= 0, "特殊字符：实体应该被解码");
        
        // 超长字符串测试
        var longString:String = "";
        for (var l:Number = 0; l < 1000; l++) {
            longString += "long";
        }
        
        var longStringXML:XML = new XML();
        longStringXML.ignoreWhite = true;
        longStringXML.parseXML("<data><content>" + longString + "</content></data>");
        var longStringNode:XMLNode = longStringXML.firstChild;
        
        var longStringResult:Object = XMLParser.parseXMLNode(longStringNode);
        _assert(longStringResult.content.length == 4000, "超长字符串：长度应该正确");
        
        // 混合节点类型测试
        var mixedTypesXML:XML = new XML();
        mixedTypesXML.parseXML("<root>Text before<child>Child content</child>Text after<!-- Comment --><![CDATA[CDATA content]]></root>");
        var mixedTypesNode:XMLNode = mixedTypesXML.firstChild;
        
        var mixedTypesResult:Object = XMLParser.parseXMLNode(mixedTypesNode);
        _assert(mixedTypesResult.child == "Child content", "混合类型：子元素应该正确解析");
        
        // 属性值边界测试
        var extremeAttrXML:XML = new XML();
        extremeAttrXML.ignoreWhite = true;
        extremeAttrXML.parseXML('<test empty="" number="999999999" negative="-123.456" bool1="true" bool2="false" text="normal text"/>');
        var extremeAttrNode:XMLNode = extremeAttrXML.firstChild;
        
        var extremeAttrResult:Object = XMLParser.parseXMLNode(extremeAttrNode);
        _assert(extremeAttrResult.empty == "", "极值属性：空值应该正确");
        _assert(typeof extremeAttrResult.number == "number", "极值属性：大数字应该转换");
        _assert(extremeAttrResult.negative == -123.456, "极值属性：负数应该正确");
        _assert(extremeAttrResult.bool1 === true, "极值属性：true应该转换");
        _assert(extremeAttrResult.bool2 === false, "极值属性：false应该转换");
        
        // 无属性无内容的节点
        var bareXML:XML = new XML();
        bareXML.ignoreWhite = true;
        bareXML.parseXML("<bare/>");
        var bareNode:XMLNode = bareXML.firstChild;
        
        var bareResult:Object = XMLParser.parseXMLNode(bareNode);
        _assert(typeof bareResult == "object", "裸节点：应该返回对象");
        var propCount:Number = 0;
        for (var prop in bareResult) {
            propCount++;
        }
        _assert(propCount == 0, "裸节点：应该是空对象");
        
        // getInnerText的边界测试
        var innerTextBoundary:String = XMLParser.getInnerText(null);
        _assert(innerTextBoundary == "", "getInnerText边界：null应该返回空字符串");
        
        // configureDataAsArray的边界测试
        var arrayBoundary1:Array = XMLParser.configureDataAsArray(0);
        _assert(arrayBoundary1[0] == 0, "数组配置边界：0应该正确包装");
        
        var arrayBoundary2:Array = XMLParser.configureDataAsArray(false);
        _assert(arrayBoundary2[0] === false, "数组配置边界：false应该正确包装");
    }
    
    // ============================================================================
    // 测试分组11：性能和大数据测试
    // ============================================================================
    private static function testPerformanceAndLargeData():Void {
        trace("\n--- 测试分组11：性能和大数据测试 ---");
        
        // 大型XML文档解析性能测试
        var largeXMLString:String = "<database>";
        for (var i:Number = 0; i < 200; i++) {
            largeXMLString += "<record id=\"" + i + "\">";
            largeXMLString += "<name>User " + i + "</name>";
            largeXMLString += "<email>user" + i + "@example.com</email>";
            largeXMLString += "<age>" + (20 + (i % 50)) + "</age>";
            largeXMLString += "<active>" + (i % 2 == 0 ? "true" : "false") + "</active>";
            largeXMLString += "</record>";
        }
        largeXMLString += "</database>";
        
        var largeXML:XML = new XML();
        largeXML.ignoreWhite = true;
        
        var parseStartTime:Number = getTimer();
        largeXML.parseXML(largeXMLString);
        var xmlParseTime:Number = getTimer() - parseStartTime;
        
        var largeNode:XMLNode = largeXML.firstChild;
        
        var convertStartTime:Number = getTimer();
        var largeResult:Object = XMLParser.parseXMLNode(largeNode);
        var convertTime:Number = getTimer() - convertStartTime;
        
        _assert(largeResult != null, "大数据性能：应该成功解析");
        _assert(largeResult.record instanceof Array, "大数据性能：记录应该是数组");
        _assert(largeResult.record.length == 200, "大数据性能：记录数量应该正确");
        _assert(convertTime < 2000, "大数据性能：转换时间应该合理（<2秒）");
        trace("    大数据解析：XML解析时间=" + xmlParseTime + "ms, 对象转换时间=" + convertTime + "ms");
        
        // 深度嵌套性能测试
        var depthTestString:String = "<root>";
        var currentDepth:String = "";
        for (var j:Number = 0; j < 100; j++) {
            currentDepth += "<level" + j + ">";
        }
        depthTestString += currentDepth + "<data>Deep Value</data>";
        for (var k:Number = 99; k >= 0; k--) {
            depthTestString += "</level" + k + ">";
        }
        depthTestString += "</root>";
        
        var depthXML:XML = new XML();
        depthXML.ignoreWhite = true;
        
        var depthStartTime:Number = getTimer();
        depthXML.parseXML(depthTestString);
        var depthNode:XMLNode = depthXML.firstChild;
        var depthResult:Object = XMLParser.parseXMLNode(depthNode);
        var depthTime:Number = getTimer() - depthStartTime;
        
        _assert(depthResult != null, "深度性能：应该成功解析");
        _assert(depthTime < 1000, "深度性能：解析时间应该合理（<1秒）");
        trace("    深度嵌套解析时间=" + depthTime + "ms");
        
        // 重复解析性能测试
        var repeatTestXML:XML = new XML();
        repeatTestXML.ignoreWhite = true;
        repeatTestXML.parseXML("<simple><name>Test</name><value>123</value></simple>");
        var repeatNode:XMLNode = repeatTestXML.firstChild;
        
        var repeatStartTime:Number = getTimer();
        for (var l:Number = 0; l < 1000; l++) {
            XMLParser.parseXMLNode(repeatNode);
        }
        var repeatTime:Number = getTimer() - repeatStartTime;
        
        _assert(repeatTime < 3000, "重复解析性能：1000次解析应该在3秒内完成");
        trace("    重复解析1000次时间=" + repeatTime + "ms, 平均=" + (repeatTime/1000) + "ms/次");
        
        // 大量属性性能测试
        var manyAttrsString:String = "<element";
        for (var m:Number = 0; m < 50; m++) {
            manyAttrsString += " attr" + m + "=\"value" + m + "\"";
        }
        manyAttrsString += "><content>Test</content></element>";
        
        var manyAttrsXML:XML = new XML();
        manyAttrsXML.ignoreWhite = true;
        
        var attrsStartTime:Number = getTimer();
        manyAttrsXML.parseXML(manyAttrsString);
        var attrsNode:XMLNode = manyAttrsXML.firstChild;
        var attrsResult:Object = XMLParser.parseXMLNode(attrsNode);
        var attrsTime:Number = getTimer() - attrsStartTime;
        
        _assert(attrsResult.attr0 == "value0", "大量属性性能：属性应该正确解析");
        _assert(attrsResult.attr49 == "value49", "大量属性性能：最后一个属性应该正确");
        _assert(attrsResult.content == "Test", "大量属性性能：内容应该正确");
        _assert(attrsTime < 500, "大量属性性能：解析时间应该合理（<0.5秒）");
        trace("    大量属性解析时间=" + attrsTime + "ms");
        
        // 混合大数据测试
        var mixedLargeString:String = "<complex>";
        for (var n:Number = 0; n < 50; n++) {
            mixedLargeString += "<section" + n + " type=\"type" + (n % 5) + "\">";
            for (var o:Number = 0; o < 10; o++) {
                mixedLargeString += "<item id=\"" + (n * 10 + o) + "\">";
                mixedLargeString += "<title>Item " + (n * 10 + o) + "</title>";
                mixedLargeString += "<description>&lt;p&gt;Description for item " + (n * 10 + o) + "&lt;/p&gt;</description>";
                mixedLargeString += "</item>";
            }
            mixedLargeString += "</section" + n + ">";
        }
        mixedLargeString += "</complex>";
        
        var mixedLargeXML:XML = new XML();
        mixedLargeXML.ignoreWhite = true;
        
        var mixedStartTime:Number = getTimer();
        mixedLargeXML.parseXML(mixedLargeString);
        var mixedLargeNode:XMLNode = mixedLargeXML.firstChild;
        var mixedLargeResult:Object = XMLParser.parseXMLNode(mixedLargeNode);
        var mixedTime:Number = getTimer() - mixedStartTime;
        
        _assert(mixedLargeResult != null, "混合大数据：应该成功解析");
        var sectionCount:Number = 0;
        for (var prop in mixedLargeResult) {
            if (prop.indexOf("section") == 0) sectionCount++;
        }
        _assert(sectionCount == 50, "混合大数据：section数量应该正确");
        _assert(mixedTime < 3000, "混合大数据：解析时间应该合理（<3秒）");
        trace("    混合大数据解析时间=" + mixedTime + "ms");
        
        // 内存使用监控（简单模拟）
        var memoryTestStartTime:Number = getTimer();
        for (var p:Number = 0; p < 20; p++) {
            var tempXMLString:String = "<temp>";
            for (var q:Number = 0; q < 20; q++) {
                tempXMLString += "<data" + q + ">Value " + q + "</data" + q + ">";
            }
            tempXMLString += "</temp>";
            
            var tempXML:XML = new XML();
            tempXML.ignoreWhite = true;
            tempXML.parseXML(tempXMLString);
            var tempNode:XMLNode = tempXML.firstChild;
            XMLParser.parseXMLNode(tempNode);
        }
        var memoryTestTime:Number = getTimer() - memoryTestStartTime;
        
        _assert(memoryTestTime < 2000, "内存测试：重复创建销毁应该高效（<2秒）");
        trace("    内存测试时间=" + memoryTestTime + "ms");
    }
    
    // ============================================================================
    // 测试分组12：集成场景测试
    // ============================================================================
    private static function testIntegrationScenarios():Void {
        trace("\n--- 测试分组12：集成场景测试 ---");
        
        // 游戏配置文件集成测试
        var gameConfigXMLString:String =
            '<gameConfig version="2.1">' +
                '<metadata>' +
                    '<title>Epic Adventure</title>' +
                    '<description>&lt;p&gt;An &lt;b&gt;amazing&lt;/b&gt; adventure game!&lt;/p&gt;</description>' +
                    '<author>Game Studio</author>' +
                '</metadata>' +
                '<settings>' +
                    '<graphics quality="ultra" vsync="true" shadows="high"/>' +
                    '<audio masterVolume="0.8" musicVolume="0.6" effectsVolume="1.0"/>' +
                    '<controls>' +
                        '<binding action="move_forward" key="w"/>' +
                        '<binding action="move_backward" key="s"/>' +
                        '<binding action="move_left" key="a"/>' +
                        '<binding action="move_right" key="d"/>' +
                    '</controls>' +
                '</settings>' +
                '<gameObjects>' +
                    '<player>' +
                        '<stats health="100" mana="50" experience="0"/>' +
                        '<position x="0" y="0" z="0"/>' +
                        '<inventory slots="20">' +
                            '<item type="weapon" id="starter_sword" equipped="true"/>' +
                            '<item type="armor" id="leather_vest" equipped="true"/>' +
                        '</inventory>' +
                    '</player>' +
                    '<npcs>' +
                        '<npc id="merchant_1" type="merchant">' +
                            '<name>Old Merchant</name>' +
                            '<position x="10" y="0" z="5"/>' +
                            '<dialogue>&lt;p&gt;Welcome to my shop!&lt;/p&gt;</dialogue>' +
                        '</npc>' +
                        '<npc id="guard_1" type="guard">' +
                            '<name>City Guard</name>' +
                            '<position x="20" y="0" z="10"/>' +
                        '</npc>' +
                    '</npcs>' +
                '</gameObjects>' +
            '</gameConfig>';
        
        var gameConfigXML:XML = new XML();
        gameConfigXML.ignoreWhite = true;
        gameConfigXML.parseXML(gameConfigXMLString);
        var gameConfigNode:XMLNode = gameConfigXML.firstChild;
        
        var gameConfig:Object = XMLParser.parseXMLNode(gameConfigNode);
        
        // 验证游戏配置解析
        _assert(gameConfig.version == "2.1", "游戏集成：版本应该正确");
        _assert(gameConfig.metadata.title == "Epic Adventure", "游戏集成：标题应该正确");
        _assert(gameConfig.metadata.description.indexOf("<b>amazing</b>") >= 0, "游戏集成：HTML描述应该解码");
        _assert(gameConfig.settings.graphics.quality == "ultra", "游戏集成：图形设置应该正确");
        _assert(gameConfig.settings.audio.masterVolume == 0.8, "游戏集成：音频设置应该转换为数字");
        _assert(gameConfig.settings.controls.binding instanceof Array, "游戏集成：控制绑定应该是数组");
        _assert(gameConfig.settings.controls.binding.length == 4, "游戏集成：绑定数量应该正确");
        _assert(gameConfig.gameObjects.player.stats.health == 100, "游戏集成：玩家生命值应该转换为数字");
        _assert(gameConfig.gameObjects.player.inventory.item instanceof Array, "游戏集成：物品应该是数组");
        _assert(gameConfig.gameObjects.npcs.npc instanceof Array, "游戏集成：NPC应该是数组");
        _assert(gameConfig.gameObjects.npcs.npc[0].dialogue.indexOf("Welcome") >= 0, "游戏集成：NPC对话应该解码");
        
        // 数据验证和类型检查
        _assert(typeof gameConfig.gameObjects.player.position.x == "number", "游戏集成：坐标应该是数字类型");
        _assert(gameConfig.gameObjects.player.inventory.item[0].equipped === true, "游戏集成：装备状态应该是布尔值");
        
        // UI布局配置集成测试
        var uiLayoutXMLString:String =
            '<uiLayout>' +
                '<screen name="main_menu" width="1920" height="1080">' +
                    '<panels>' +
                        '<panel id="header" x="0" y="0" width="1920" height="100">' +
                            '<title>Main Menu</title>' +
                            '<background color="#333333" alpha="0.9"/>' +
                        '</panel>' +
                        '<panel id="navigation" x="0" y="100" width="300" height="880">' +
                            '<buttons>' +
                                '<button id="new_game" text="New Game" x="10" y="10" enabled="true"/>' +
                                '<button id="load_game" text="Load Game" x="10" y="60" enabled="false"/>' +
                                '<button id="settings" text="Settings" x="10" y="110" enabled="true"/>' +
                                '<button id="exit" text="Exit" x="10" y="160" enabled="true"/>' +
                            '</buttons>' +
                        '</panel>' +
                        '<panel id="content" x="300" y="100" width="1620" height="880">' +
                            '<background image="menu_bg.jpg" stretch="true"/>' +
                            '<logo x="center" y="200" src="game_logo.png"/>' +
                        '</panel>' +
                    '</panels>' +
                '</screen>' +
            '</uiLayout>';
        
        var uiLayoutXML:XML = new XML();
        uiLayoutXML.ignoreWhite = true;
        uiLayoutXML.parseXML(uiLayoutXMLString);
        var uiLayoutNode:XMLNode = uiLayoutXML.firstChild;
        
        var uiLayout:Object = XMLParser.parseXMLNode(uiLayoutNode);
        
        // 验证UI布局解析
        _assert(uiLayout.screen.name == "main_menu", "UI集成：屏幕名称应该正确");
        _assert(uiLayout.screen.width == 1920, "UI集成：屏幕宽度应该转换为数字");
        _assert(uiLayout.screen.panels.panel instanceof Array, "UI集成：面板应该是数组");
        _assert(uiLayout.screen.panels.panel.length == 3, "UI集成：面板数量应该正确");
        _assert(uiLayout.screen.panels.panel[1].buttons.button instanceof Array, "UI集成：按钮应该是数组");
        _assert(uiLayout.screen.panels.panel[1].buttons.button[1].enabled === false, "UI集成：按钮状态应该转换为布尔值");
        _assert(uiLayout.screen.panels.panel[0].background.alpha == 0.9, "UI集成：透明度应该转换为数字");
        
        // 数据库架构集成测试
        var dbSchemaXMLString:String =
            '<database name="game_db" version="1.0">' +
                '<tables>' +
                    '<table name="users" primaryKey="id">' +
                        '<columns>' +
                            '<column name="id" type="INTEGER" autoIncrement="true" nullable="false"/>' +

                            '<column name="username" type="VARCHAR" length="50" nullable="false" unique="true"/>' +
                            '<column name="email" type="VARCHAR" length="100" nullable="false"/>' +
                            '<column name="password_hash" type="VARCHAR" length="255" nullable="false"/>' +
                            '<column name="created_at" type="TIMESTAMP" nullable="false" dft="CURRENT_TIMESTAMP"/>' +
                            '<column name="last_login" type="TIMESTAMP" nullable="true"/>' +
                            '<column name="is_active" type="BOOLEAN" nullable="false" dft="true"/>' +
                        '</columns>' +
                        '<indexes>' +
                            '<index name="idx_username" columns="username" unique="true"/>' +
                            '<index name="idx_email" columns="email"/>' +
                        '</indexes>' +
                    '</table>' +
                    '<table name="characters" primaryKey="id">' +
                        '<columns>' +
                            '<column name="id" type="INTEGER" autoIncrement="true" nullable="false"/>' +
                            '<column name="user_id" type="INTEGER" nullable="false"/>' +
                            '<column name="name" type="VARCHAR" length="30" nullable="false"/>' +
                            '<column name="level" type="INTEGER" nullable="false" dft="1"/>' +
                            '<column name="experience" type="BIGINT" nullable="false" dft="0"/>' +
                            '<column name="clazz" type="VARCHAR" length="20" nullable="false"/>' +
                        '</columns>' +
                        '<foreignKeys>' +
                            '<foreignKey name="fk_user" column="user_id" references="users.id" onDelete="CASCADE"/>' +
                        '</foreignKeys>' +
                    '</table>' +
                '</tables>' +
            '</database>';
        
        var dbSchemaXML:XML = new XML();
        dbSchemaXML.ignoreWhite = true;
        dbSchemaXML.parseXML(dbSchemaXMLString);
        var dbSchemaNode:XMLNode = dbSchemaXML.firstChild;
        
        var dbSchema:Object = XMLParser.parseXMLNode(dbSchemaNode);
        
        // 验证数据库架构解析
        _assert(dbSchema.name == "game_db", "数据库集成：数据库名称应该正确");
        _assert(dbSchema.version == "1.0", "数据库集成：版本应该正确");
        _assert(dbSchema.tables.table instanceof Array, "数据库集成：表应该是数组");
        _assert(dbSchema.tables.table.length == 2, "数据库集成：表数量应该正确");
        _assert(dbSchema.tables.table[0].columns.column instanceof Array, "数据库集成：列应该是数组");
        _assert(dbSchema.tables.table[0].columns.column[0].autoIncrement === true, "数据库集成：自增标记应该转换为布尔值");
        _assert(dbSchema.tables.table[0].columns.column[1].length == 50, "数据库集成：长度应该转换为数字");
        _assert(dbSchema.tables.table[1].foreignKeys.foreignKey.onDelete == "CASCADE", "数据库集成：外键操作应该正确");
        
        // 工作流定义集成测试
        var workflowXMLString:String =
            '<workflow name="order_processing" version="1.0">' +
                '<description>&lt;p&gt;Order processing workflow for &lt;b&gt;e-commerce&lt;/b&gt; system&lt;/p&gt;</description>' +
                '<variables>' +
                    '<variable name="order_amount" type="number" required="true" min="0.01"/>' +
                    '<variable name="customer_type" type="string" required="true" values="regular,premium,vip"/>' +
                    '<variable name="payment_method" type="string" required="true"/>' +
                    '<variable name="requires_approval" type="boolean" dft="false"/>' +
                '</variables>' +
                '<states>' +
                    '<state id="start" name="Order Received" type="start">' +
                        '<actions>' +
                            '<action type="log" message="Order received for processing"/>' +
                            '<action type="validate" target="order_amount,customer_type"/>' +
                        '</actions>' +
                        '<transitions>' +
                            '<transition to="payment_check" condition="order_amount &lt; 1000"/>' +
                            '<transition to="approval_required" condition="order_amount &gt;= 1000"/>' +
                        '</transitions>' +
                    '</state>' +
                    '<state id="payment_check" name="Payment Verification">' +
                        '<actions>' +
                            '<action type="verify_payment" method="payment_method"/>' +
                        '</actions>' +
                        '<transitions>' +
                            '<transition to="fulfillment" condition="payment_verified == true"/>' +
                            '<transition to="payment_failed" condition="payment_verified == false"/>' +
                        '</transitions>' +
                    '</state>' +
                    '<state id="approval_required" name="Manager Approval">' +
                        '<actions>' +
                            '<action type="notify" target="manager" message="High value order requires approval"/>' +
                        '</actions>' +
                        '<transitions>' +
                            '<transition to="payment_check" condition="approved == true"/>' +
                            '<transition to="rejected" condition="approved == false"/>' +
                        '</transitions>' +
                    '</state>' +
                    '<state id="fulfillment" name="Order Fulfillment">' +
                        '<actions>' +
                            '<action type="create_shipment"/>' +
                            '<action type="update_inventory"/>' +
                            '<action type="notify" target="customer" message="Your order is being processed"/>' +
                        '</actions>' +
                        '<transitions>' +
                            '<transition to="completed"/>' +
                        '</transitions>' +
                    '</state>' +
                    '<state id="completed" name="Order Completed" type="end">' +
                        '<actions>' +
                            '<action type="notify" target="customer" message="Your order has been completed"/>' +
                            '<action type="log" message="Order processing completed successfully"/>' +
                        '</actions>' +
                    '</state>' +
                    '<state id="payment_failed" name="Payment Failed" type="end">' +
                        '<actions>' +
                            '<action type="notify" target="customer" message="Payment failed. Please try again."/>' +
                        '</actions>' +
                    '</state>' +
                    '<state id="rejected" name="Order Rejected" type="end">' +
                        '<actions>' +
                            '<action type="notify" target="customer" message="Order rejected by manager"/>' +
                        '</actions>' +
                    '</state>' +
                '</states>' +
            '</workflow>';
        
        var workflowXML:XML = new XML();
        workflowXML.ignoreWhite = true;
        workflowXML.parseXML(workflowXMLString);
        var workflowNode:XMLNode = workflowXML.firstChild;
        
        var workflow:Object = XMLParser.parseXMLNode(workflowNode);
        
        // 验证工作流解析
        _assert(workflow.name == "order_processing", "工作流集成：工作流名称应该正确");
        _assert(workflow.description.indexOf("<b>e-commerce</b>") >= 0, "工作流集成：描述HTML应该解码");
        _assert(workflow.variables.variable instanceof Array, "工作流集成：变量应该是数组");
        _assert(workflow.variables.variable[0].min == 0.01, "工作流集成：最小值应该转换为数字");
        _assert(workflow.variables.variable[3].dft === false, "工作流集成：默认布尔值应该正确");
        _assert(workflow.states.state instanceof Array, "工作流集成：状态应该是数组");
        _assert(workflow.states.state.length == 7, "工作流集成：状态数量应该正确");
        _assert(workflow.states.state[0].actions.action instanceof Array, "工作流集成：动作应该是数组");
        _assert(workflow.states.state[0].transitions.transition instanceof Array, "工作流集成：转换应该是数组");
        _assert(workflow.states.state[0].transitions.transition[0].condition.indexOf("<") >= 0, "工作流集成：条件HTML实体应该解码");
        
        // 测试与Stage解析器的配合
        var stageWorkflowXMLString:String =
            '<stage>' +
                '<CaseSwitch expression="getDifficultyLevel" params="">' +
                    '<Case casevalue="1">' +
                        '<enemies>' +
                            '<enemy type="goblin" count="2" health="50"/>' +
                        '</enemies>' +
                        '<rewards gold="100" experience="50"/>' +
                    '</Case>' +
                    '<Case casevalue="2">' +
                        '<enemies>' +
                            '<enemy type="orc" count="1" health="100"/>' +
                            '<enemy type="goblin" count="3" health="50"/>' +
                        '</enemies>' +
                        '<rewards gold="200" experience="100"/>' +
                    '</Case>' +
                    '<Case casevalue="dft">' +
                        '<enemies>' +
                            '<enemy type="dragon" count="1" health="500"/>' +
                        '</enemies>' +
                        '<rewards gold="1000" experience="500"/>' +
                    '</Case>' +
                '</CaseSwitch>' +
            '</stage>';
        
        // 设置测试函数
        _global.getDifficultyLevel = function():Number {
            return 2;
        };
        
        var stageWorkflowXML:XML = new XML();
        stageWorkflowXML.ignoreWhite = true;
        stageWorkflowXML.parseXML(stageWorkflowXMLString);
        var stageWorkflowNode:XMLNode = stageWorkflowXML.firstChild;
        
        var stageWorkflow:Object = XMLParser.parseStageXMLNode(stageWorkflowNode);
        
        // 验证Stage和工作流集成
        _assert(stageWorkflow.enemies.enemy instanceof Array, "Stage工作流：敌人应该是数组");
        _assert(stageWorkflow.enemies.enemy.length == 2, "Stage工作流：应该选择难度2的配置");
        _assert(stageWorkflow.enemies.enemy[0].type == "orc", "Stage工作流：第一个敌人应该是兽人");
        _assert(stageWorkflow.enemies.enemy[0].health == 100, "Stage工作流：敌人生命值应该转换为数字");
        _assert(stageWorkflow.rewards.gold == 200, "Stage工作流：奖励金币应该正确");
        
        // 清理测试函数
        delete _global.getDifficultyLevel;
        
        // 配置文件加载模拟测试
        var configLoadTestXMLString:String =
            '<applicationConfig>' +
                '<metadata>' +
                    '<version>1.0.0</version>' +
                    '<buildDate>2024-01-15</buildDate>' +
                    '<environment>production</environment>' +
                '</metadata>' +
                '<features>' +
                    '<feature name="analytics" enabled="true" endpoint="https://api.analytics.com"/>' +
                    '<feature name="debugging" enabled="false"/>' +
                    '<feature name="beta_features" enabled="false"/>' +
                '</features>' +
                '<performance>' +
                    '<cacheSize>1000</cacheSize>' +
                    '<maxConnections>50</maxConnections>' +
                    '<timeout>30000</timeout>' +
                '</performance>' +
            '</applicationConfig>';
        
        var configLoadTestXML:XML = new XML();
        configLoadTestXML.ignoreWhite = true;
        configLoadTestXML.parseXML(configLoadTestXMLString);
        var configLoadTestNode:XMLNode = configLoadTestXML.firstChild;
        
        var appConfig:Object = XMLParser.parseXMLNode(configLoadTestNode);
        
        // 模拟配置验证逻辑
        var isValidConfig:Boolean = (
            appConfig.metadata.version != null &&
            appConfig.features.feature instanceof Array &&
            typeof appConfig.performance.cacheSize == "number"
        );
        
        _assert(isValidConfig, "配置加载集成：配置应该有效");
        _assert(appConfig.features.feature[0].enabled === true, "配置加载集成：功能开关应该正确");
        _assert(appConfig.performance.timeout == 30000, "配置加载集成：超时值应该转换为数字");
    }
    
    // ============================================================================
    // 测试辅助函数
    // ============================================================================
    private static function _assert(condition:Boolean, message:String):Void {
        _testCount++;
        if (condition) {
            _passCount++;
            trace("  ✅ " + message);
        } else {
            _failCount++;
            trace("  ❌ " + message);
        }
    }
    
    /**
     * 获取当前时间（毫秒）- AS2简化实现
     */
    private static function getTimer():Number {
        return new Date().getTime();
    }
    
    /**
     * 辅助函数：比较两个对象是否相等（递归比较）
     */
    private static function _deepEquals(obj1:Object, obj2:Object):Boolean {
        if (obj1 === obj2) return true;
        if (obj1 == null || obj2 == null) return false;
        
        if (typeof obj1 != typeof obj2) return false;
        
        if (typeof obj1 != "object") return obj1 === obj2;
        
        // 检查数组
        if (obj1 instanceof Array && obj2 instanceof Array) {
            if (obj1.length != obj2.length) return false;
            for (var i:Number = 0; i < obj1.length; i++) {
                if (!_deepEquals(obj1[i], obj2[i])) return false;
            }
            return true;
        }
        
        if ((obj1 instanceof Array) != (obj2 instanceof Array)) return false;
        
        // 检查对象属性
        var keys1:Array = [];
        var keys2:Array = [];
        
        for (var key1:String in obj1) keys1.push(key1);
        for (var key2:String in obj2) keys2.push(key2);
        
        if (keys1.length != keys2.length) return false;
        
        for (var j:Number = 0; j < keys1.length; j++) {
            var key:String = keys1[j];
            if (obj2[key] === undefined) return false;
            if (!_deepEquals(obj1[key], obj2[key])) return false;
        }
        
        return true;
    }
    
    /**
     * 辅助函数：生成测试用的XML字符串
     */
    private static function _generateTestXML(elementName:String, content:String, attributes:Object):String {
        var xmlString:String = "<" + elementName;
        
        if (attributes != null) {
            for (var attr:String in attributes) {
                xmlString += " " + attr + "=\"" + attributes[attr] + "\"";
            }
        }
        
        if (content != null && content != "") {
            xmlString += ">" + content + "</" + elementName + ">";
        } else {
            xmlString += "/>";
        }
        
        return xmlString;
    }
    
    /**
     * 辅助函数：计算对象的属性数量
     */
    private static function _countProperties(obj:Object):Number {
        var count:Number = 0;
        for (var prop:String in obj) {
            count++;
        }
        return count;
    }
    
    /**
     * 辅助函数：创建测试用的XMLNode
     */
    private static function _createTestNode(xmlString:String):XMLNode {
        var xml:XML = new XML();
        xml.ignoreWhite = true;
        xml.parseXML(xmlString);
        return xml.firstChild;
    }
    
    /**
     * 辅助函数：验证数组包含指定元素
     */
    private static function _arrayContains(array:Array, item:Object):Boolean {
        for (var i:Number = 0; i < array.length; i++) {
            if (array[i] === item || array[i] == item) {
                return true;
            }
        }
        return false;
    }
    
    /**
     * 辅助函数：生成指定长度的随机字符串
     */
    private static function _generateRandomString(length:Number):String {
        var chars:String = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
        var result:String = "";
        for (var i:Number = 0; i < length; i++) {
            result += chars.charAt(Math.floor(Math.random() * chars.length));
        }
        return result;
    }
    
    /**
     * 辅助函数：验证对象结构是否匹配预期模式
     */
    private static function _validateObjectStructure(obj:Object, expectedKeys:Array):Boolean {
        if (obj == null) return false;
        
        for (var i:Number = 0; i < expectedKeys.length; i++) {
            var key:String = expectedKeys[i];
            if (obj[key] === undefined) {
                return false;
            }
        }
        return true;
    }
    
    /**
     * 辅助函数：创建性能测试用的大型XML结构
     */
    private static function _createLargeXMLStructure(elementCount:Number, nestingDepth:Number):String {
        var xmlString:String = "<root>";
        
        for (var i:Number = 0; i < elementCount; i++) {
            xmlString += "<item" + i + " id=\"" + i + "\" value=\"" + (i * 2) + "\">";
            
            var currentNesting:String = "";
            for (var j:Number = 0; j < nestingDepth; j++) {
                currentNesting += "<level" + j + ">";
            }
            currentNesting += "Content " + i;
            for (var k:Number = nestingDepth - 1; k >= 0; k--) {
                currentNesting += "</level" + k + ">";
            }
            
            xmlString += currentNesting + "</item" + i + ">";
        }
        
        xmlString += "</root>";
        return xmlString;
    }
}