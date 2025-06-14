import org.flashNight.gesh.string.StringUtils;
import org.flashNight.gesh.xml.XMLLoader;

class org.flashNight.gesh.xml.XMLParser
{
    /**
     * 将输入配置数据确保为数组格式。
     * @param input 输入数据，可以是任何类型。
     * @return 数组格式的数据。
     */
    public static function configureDataAsArray(input):Array
    {
        if (input instanceof Array)
        {
            return input;
        }
        else if (input != undefined && input != null)
        {
            return [input];
        }
        else
        {
            return [];
        }
    }

    /**
     * 解析给定的 XML 节点并将其转换为对象。
     * @param node XMLNode 要解析的 XML 节点。
     * @return Object 解析后的对象。如果解析失败，返回 null。
     */
    public static function parseXMLNode(node:XMLNode):Object
    {
        try
        {
            // 处理文本节点直接返回其值
            if (node.nodeType == 3) // TEXT_NODE
            {
                return convertDataType(node.nodeValue);
            }
            else if (node.nodeType == 4) // CDATA_SECTION_NODE
            {
                return node.nodeValue;
            }

            // 现在，节点是元素节点，进行有效性检查
            if (node == null || !isValidXML(node)) {
                return null;
            }

            var result:Object = {};

            // 处理节点属性并进行类型转换
            for (var attr:String in node.attributes)
            {
                result[attr] = convertDataType(node.attributes[attr]);
            }

            // 处理子节点
            for (var i:Number = 0; i < node.childNodes.length; i++)
            {
                var childNode:XMLNode = node.childNodes[i];
                var nodeName:String = childNode.nodeName;

                // 跳过注释节点
                if (childNode.nodeType == 8) // COMMENT_NODE
                {
                    continue;
                }

                // 特别处理 Description 和 MaterialDetail 节点
                if ((nodeName == "Description" || nodeName == "MaterialDetail") && childNode.nodeType == 1)
                {
                    var innerText:String = getInnerText(childNode);
                    result[nodeName] = StringUtils.decodeHTML(innerText);
                    continue;
                }

                if (childNode.hasChildNodes())
                {
                    var childValue:Object;

                    if (childNode.childNodes.length == 1 && childNode.firstChild.nodeType == 3)
                    {
                        childValue = convertDataType(childNode.firstChild.nodeValue);
                    }
                    else
                    {
                        childValue = parseXMLNode(childNode);
                    }

                    // 如果已经有同名节点，则转换为数组
                    if (result[nodeName] !== undefined)
                    {
                        if (!(result[nodeName] instanceof Array))
                        {
                            result[nodeName] = [result[nodeName]];
                        }
                        result[nodeName].push(childValue);
                    }
                    else
                    {
                        result[nodeName] = childValue;
                    }
                }
                else
                {
                    var nodeValue:Object;
                    if(childNode.nodeValue != null){
                        nodeValue = convertDataType(childNode.nodeValue);
                    }else{
                        // 子节点无值时若存在attributes则解析attributes，不存在则处理为空字符串
                        var hasAttr = false;
                        var attrs = {};
                        for(var attr:String in childNode.attributes){
                            hasAttr = true;
                            attrs[attr] = convertDataType(childNode.attributes[attr]);
                        }
                        nodeValue = hasAttr ? attrs : "";
                    }
                    if (result[nodeName] !== undefined)
                    {
                        if (!(result[nodeName] instanceof Array))
                        {
                            result[nodeName] = [result[nodeName]];
                        }
                        result[nodeName].push(nodeValue);
                    }
                    else
                    {
                        result[nodeName] = nodeValue;
                    }
                }
            }

            return result;
        }
        catch (e:Error)
        {
            trace("XMLParser.parseXMLNode Error: " + e.message);
            return null;
        }
    }

    /**
     * 解析给定的 关卡XML 节点并将其转换为对象。
     * @param node XMLNode 要解析的 关卡XML 节点。
     * @return Object 解析后的对象。如果解析失败，返回 null。
     */
    public static function parseStageXMLNode(node:XMLNode):Object{
        try
        {
            // 处理文本节点直接返回其值
            if (node.nodeType == 3) // TEXT_NODE
            {
                return convertDataType(node.nodeValue);
            }
            else if (node.nodeType == 4) // CDATA_SECTION_NODE
            {
                return node.nodeValue;
            }

            // 现在，节点是元素节点，进行有效性检查
            if (node == null || !isValidXML(node)) {
                return null;
            }

            // 查找CaseSwitch节点
            if(node.firstChild.nodeName === "CaseSwitch"){
                var switchNode = node.firstChild;
                // 读取要调用的目标函数expression与参数params
                var expression = eval(switchNode.attributes.expression);
                if(expression == null) return switchNode.attributes.expression;
                var params = switchNode.attributes.params.split(",");
                for(var i=0; i<params.length; i++){
                    params[i] = convertDataType(params[i]);
                }
                // 执行目标函数并读取返回值
                var switchResult;
                if(params.length <= 1) switchResult = expression();
                if(params.length == 1) switchResult = expression(params[0]);
                else if(params.length == 2) switchResult = expression(params[0],params[1]);
                else switchResult = expression.apply(null,params);
                // 遍历CaseSwitch节点下的所有Case节点
                for (var i:Number = 0; i < switchNode.childNodes.length; i++){
                    var caseNode:XMLNode = switchNode.childNodes[i];
                    var nodeName:String = caseNode.nodeName;
                    if(nodeName !== "Case") continue;
                    var casevalue = convertDataType(caseNode.attributes.casevalue);
                    // 若检测成功，则以对应Case节点内的属性作为该节点的属性
                    if(casevalue == switchResult || casevalue === "default"){
                        // 若节点为文本节点（会被解析为带着casevalue属性与一个null子节点的节点），则返回子节点的文本值
                        if(caseNode.hasChildNodes() && caseNode.firstChild.nodeName == null) return convertDataType(caseNode.firstChild.nodeValue);
                        // 否则，返回整个节点的值
                        else return parseStageXMLNode(caseNode);
                    }
                }
                return null;
            }

            var result:Object = {};
            
            // 处理节点属性并进行类型转换
            for (var attr:String in node.attributes)
            {
                result[attr] = convertDataType(node.attributes[attr]);
            }

            // 处理子节点
            for (var i:Number = 0; i < node.childNodes.length; i++)
            {
                var childNode:XMLNode = node.childNodes[i];
                var nodeName:String = childNode.nodeName;

                // 跳过注释节点
                if (childNode.nodeType == 8) // COMMENT_NODE
                {
                    continue;
                }

                // 特别处理 Description 和 MaterialDetail 节点
                // if ((nodeName == "Description" || nodeName == "MaterialDetail") && childNode.nodeType == 1)
                // {
                //     var innerText:String = getInnerText(childNode);
                //     result[nodeName] = StringUtils.decodeHTML(innerText);
                //     continue;
                // }

                if (childNode.hasChildNodes())
                {
                    var childValue:Object;

                    if (childNode.childNodes.length == 1 && childNode.firstChild.nodeType == 3)
                    {
                        childValue = convertDataType(childNode.firstChild.nodeValue);
                    }
                    else
                    {
                        childValue = parseStageXMLNode(childNode);
                    }

                    // 如果已经有同名节点，则转换为数组
                    if (result[nodeName] !== undefined)
                    {
                        if (!(result[nodeName] instanceof Array))
                        {
                            result[nodeName] = [result[nodeName]];
                        }
                        result[nodeName].push(childValue);
                    }
                    else
                    {
                        result[nodeName] = childValue;
                    }
                }
                else
                {
                    var nodeValue:Object;
                    if(childNode.nodeValue != null){
                        nodeValue = convertDataType(childNode.nodeValue);
                    }else{
                        // 子节点无值时若存在attributes则解析attributes，不存在则处理为空字符串
                        var hasAttr = false;
                        var attrs = {};
                        for(var attr:String in childNode.attributes){
                            hasAttr = true;
                            attrs[attr] = convertDataType(childNode.attributes[attr]);
                        }
                        nodeValue = hasAttr ? attrs : "";
                    }
                    if (result[nodeName] !== undefined)
                    {
                        if (!(result[nodeName] instanceof Array))
                        {
                            result[nodeName] = [result[nodeName]];
                        }
                        result[nodeName].push(nodeValue);
                    }
                    else
                    {
                        result[nodeName] = nodeValue;
                    }
                }
            }

            return result;
        }
        catch (e:Error)
        {
            trace("StageXMLParser.parseStageXMLNode Error: " + e.message);
            return null;
        }
    }

    /**
     * 从包含 HTML 标签的 XML 节点中提取内部文本内容。
     * @param node XMLNode 包含 HTML 标签的父节点。
     * @return String 内部文本内容。
     */
    public static function getInnerText(node:XMLNode):String
    {
        var innerText:String = "";
        for (var i:Number = 0; i < node.childNodes.length; i++)
        {
            var child:XMLNode = node.childNodes[i];
            if (child.nodeType == 3 || child.nodeType == 4) // TEXT_NODE or CDATA_SECTION_NODE
            {
                innerText += child.nodeValue;
            }
        }
        return StringUtils.decodeHTML(innerText);
    }

    /**
     * 将字符串转换为适当的数据类型（数字、布尔值或字符串）。
     * @param value String 要转换的字符串。
     * @return Object 转换后的数据。
     */
    public static function convertDataType(value:String):Object
    {
        if (!isNaN(Number(value)))
        {
            return Number(value);
        }
        else if (value.toLowerCase() == "true")
        {
            return true;
        }
        else if (value.toLowerCase() == "false")
        {
            return false;
        }
        return value;
    }

    /**
     * 检查 XML 是否有效。
     * @param node XMLNode 要检查的 XML 节点。
     * @return Boolean 如果 XML 合法则返回 true，否则返回 false。
     */
    public static function isValidXML(node:XMLNode):Boolean {
        // 检查节点名是否存在，并且不是空字符串
        if (node.nodeName == undefined || node.nodeName == null || node.nodeName == "") {
            return false;
        }

        // 检查所有子节点是否有效，忽略文本节点、CDATA 节点和注释节点
        for (var i:Number = 0; i < node.childNodes.length; i++) {
            var child:XMLNode = node.childNodes[i];
            if (child.nodeType == 3 || child.nodeType == 4 || child.nodeType == 8) { // TEXT, CDATA, COMMENT
                continue;
            }
            if (!isValidXML(child)) {
                return false;
            }
        }
        return true;
    }

    /**
     * 加载 XML 文件并处理其内容。
     * @param xmlFilePath 要加载的 XML 文件地址。
     * @param onLoadHandler 加载完成后的处理函数，接收解析后的 XML 节点作为参数。
     */
    public static function loadAndParseXML(xmlFilePath:String, onLoadHandler:Function):Void
    {
        new XMLLoader(xmlFilePath, function(xmlNode:XMLNode):Void {
            var parsedData = XMLParser.parseXMLNode(xmlNode);
            onLoadHandler(parsedData);
        });
    }
}




// import org.flashNight.gesh.xml.XMLParser;
// import org.flashNight.gesh.string.StringUtils;

// /**
//  * 辅助函数，递归比较两个对象是否相等，忽略属性顺序。
//  * @param obj1 第一个对象。
//  * @param obj2 第二个对象。
//  * @return Boolean 如果对象相等，则返回 true，否则返回 false。
//  */
// function compareObjects(obj1:Object, obj2:Object):Boolean {
//     if (obj1 == null && obj2 == null) return true;
//     if (obj1 == null || obj2 == null) return false;
//     if (typeof(obj1) != "object" || typeof(obj2) != "object") return obj1 === obj2;

//     // 获取所有键
//     var keys1:Array = [];
//     var keys2:Array = [];

//     for (var key1:String in obj1) {
//         keys1.push(key1);
//     }
//     for (var key2:String in obj2) {
//         keys2.push(key2);
//     }

//     // 比较键的数量
//     if (keys1.length != keys2.length) return false;

//     // 比较每个键的值
//     for (var i:Number = 0; i < keys1.length; i++) {
//         var key:String = keys1[i];
//         // 替换 '!(key in obj2)' 为 'obj2[key] == undefined'
//         if (obj2[key] == undefined) return false;

//         if (typeof(obj1[key]) == "object" && typeof(obj2[key]) == "object") {
//             if (!compareObjects(obj1[key], obj2[key])) return false;
//         }
//         else {
//             if (obj1[key] !== obj2[key]) return false;
//         }
//     }

//     return true;
// }

// /**
//  * 将对象转换为字符串的辅助函数，用于在测试失败时显示对象内容。
//  * @param obj Object 要转换的对象。
//  * @return String 对象的字符串表示。
//  */
// function objectToString(obj:Object):String {
//     if (obj == null) return "null";
//     if (typeof(obj) != "object") return "\"" + obj + "\"";
//     var str:String = "{";
//     var first:Boolean = true;
//     for (var key:String in obj) {
//         if (!first) str += ", ";
//         str += key + ": " + objectToString(obj[key]);
//         first = false;
//     }
//     str += "}";
//     return str;
// }

// /**
//  * 运行单元测试。
//  * @param testName String 测试名称。
//  * @param expected Object 期望的结果。
//  * @param actual Object 实际的结果。
//  */
// function runTest(testName:String, expected:Object, actual:Object):Void {
//     var pass:Boolean = compareObjects(expected, actual);
//     if (pass) {
//         trace(testName + ": PASS");
//     } else {
//         trace(testName + ": FAIL");
//         trace("  Expected: " + objectToString(expected));
//         trace("  Actual  : " + objectToString(actual));
//     }
// }

// // 开始测试
// trace("===== XMLParser 类单元测试 =====");

// // 1. 测试简单 XML 解析
// trace("----- 测试简单 XML 解析 -----");
// var testXML1:String = "<User><Username>john_doe</Username><Age>30</Age><Active>true</Active><Bio>&lt;p&gt;Hello&lt;/p&gt;</Bio></User>";
// var expected1:Object = { Username: "john_doe", Age: 30, Active: true, Bio: "<p>Hello</p>" };
// var xml1:XML = new XML();
// xml1.ignoreWhite = true;
// xml1.parseXML(testXML1);
// var result1:Object = XMLParser.parseXMLNode(xml1.firstChild);
// runTest("简单 XML 解析测试", expected1, result1);

// // 2. 测试 XML 解析带属性
// trace("----- 测试 XML 解析带属性 -----");
// var testXML2:String = "<Product id=\"123\" category=\"Electronics\"><Name>Smartphone</Name><Price>499.99</Price><InStock>false</InStock></Product>";
// var expected2:Object = { id: 123, category: "Electronics", Name: "Smartphone", Price: 499.99, InStock: false };
// var xml2:XML = new XML();
// xml2.ignoreWhite = true;
// xml2.parseXML(testXML2);
// var result2:Object = XMLParser.parseXMLNode(xml2.firstChild);
// runTest("XML 解析带属性测试", expected2, result2);

// // 3. 测试 XML 解析包含无效 XML
// trace("----- 测试 XML 解析包含无效 XML -----");
// var testXML3:String = "<Invalid><Tag></Invalid>"; // Malformed XML
// var xml3:XML = new XML();
// xml3.ignoreWhite = true;
// xml3.parseXML(testXML3);
// var result3:Object = XMLParser.parseXMLNode(xml3.firstChild);
// runTest("XML 解析无效 XML 测试", null, result3);

// // 4. 测试 XML 解析包含 CDATA
// trace("----- 测试 XML 解析包含 CDATA -----");
// var testXML4:String = "<Note><Message><![CDATA[Hello, <b>Alice</b>!]]></Message></Note>";
// var expected4:Object = { Message: "Hello, <b>Alice</b>!" };
// var xml4:XML = new XML();
// xml4.ignoreWhite = true;
// xml4.parseXML(testXML4);
// var result4:Object = XMLParser.parseXMLNode(xml4.firstChild);
// runTest("XML 解析包含 CDATA 测试", expected4, result4);

// // 5. 测试 XML 解析包含多个同名节点
// trace("----- 测试 XML 解析包含多个同名节点 -----");
// var testXML5:String = "<Library><Book><Title>Book One</Title><Author>Author A</Author></Book><Book><Title>Book Two</Title><Author>Author B</Author></Book></Library>";
// var expected5:Object = { Book: [ { Title: "Book One", Author: "Author A" }, { Title: "Book Two", Author: "Author B" } ] };
// var xml5:XML = new XML();
// xml5.ignoreWhite = true;
// xml5.parseXML(testXML5);
// var result5:Object = XMLParser.parseXMLNode(xml5.firstChild);
// runTest("XML 解析包含多个同名节点测试", expected5, result5);

// // 6. 测试 XML 解析包含注释
// trace("----- 测试 XML 解析包含注释 -----");
// var testXML6:String = "<Data><Value>123</Value><!-- This is a comment --><Value>456</Value></Data>";
// var expected6:Object = { Value: [123, 456] };
// var xml6:XML = new XML();
// xml6.ignoreWhite = true;
// xml6.parseXML(testXML6);
// var result6:Object = XMLParser.parseXMLNode(xml6.firstChild);
// runTest("XML 解析包含注释测试", expected6, result6);

// // 7. 测试 XML 解析嵌套节点
// trace("----- 测试 XML 解析嵌套节点 -----");
// var testXML7:String = "<Company><Name>Tech Corp</Name><Departments><Department><Name>Research</Name><Employees>50</Employees></Department><Department><Name>Development</Name><Employees>150</Employees></Department></Departments></Company>";
// var expected7:Object = { Name: "Tech Corp", Departments: { Department: [ { Name: "Research", Employees: 50 }, { Name: "Development", Employees: 150 } ] } };
// var xml7:XML = new XML();
// xml7.ignoreWhite = true;
// xml7.parseXML(testXML7);
// var result7:Object = XMLParser.parseXMLNode(xml7.firstChild);
// runTest("XML 解析嵌套节点测试", expected7, result7);

// // 8. 测试 XML 解析空节点
// trace("----- 测试 XML 解析空节点 -----");
// var testXML8:String = "<Empty></Empty>";
// var expected8:Object = {};
// var xml8:XML = new XML();
// xml8.ignoreWhite = true;
// xml8.parseXML(testXML8);
// var result8:Object = XMLParser.parseXMLNode(xml8.firstChild);
// runTest("XML 解析空节点测试", expected8, result8);

// // 9. 测试 XML 解析含有布尔值和数字
// trace("----- 测试 XML 解析含有布尔值和数字 -----");
// var testXML9:String = "<Settings><Volume>75</Volume><Muted>false</Muted><Brightness>0.8</Brightness><Notifications>true</Notifications></Settings>";
// var expected9:Object = { Volume: 75, Muted: false, Brightness: 0.8, Notifications: true };
// var xml9:XML = new XML();
// xml9.ignoreWhite = true;
// xml9.parseXML(testXML9);
// var result9:Object = XMLParser.parseXMLNode(xml9.firstChild);
// runTest("XML 解析含有布尔值和数字测试", expected9, result9);

// // 10. 测试 XML 解析包含空字符串
// trace("----- 测试 XML 解析包含空字符串 -----");
// var testXML10:String = "<Response><Status></Status><Message></Message></Response>";
// var expected10:Object = { Status: "", Message: "" };
// var xml10:XML = new XML();
// xml10.ignoreWhite = true;
// xml10.parseXML(testXML10);
// var result10:Object = XMLParser.parseXMLNode(xml10.firstChild);
// runTest("XML 解析包含空字符串测试", expected10, result10);

// // 结束测试
// trace("===== 所有测试完成 =====");

