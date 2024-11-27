import org.flashNight.gesh.xml.*;
import org.flashNight.gesh.string.StringUtils;

class org.flashNight.gesh.xml.TestXmlLoader
{
    private static var basePath:String = "C:/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/resources/scripts/类定义/org/flashNight/gesh/xml/TestXml/";

    /**
     * 主测试方法，用于依次测试所有 XML 文件。
     */
    public static function runTests():Void
    {
        trace("开始测试 XMLLoader 和 XMLParser...");
        testSpecialCharactersAndCDATA();
        testEnvironmentSettings();
        testEmptyAndIncomplete();
        testColorEngine();
        testLargeScale(); // 超大文件由于过长，暂时未进行测试
        trace("所有测试完成。");
    }

    /**
     * 处理路径转换，确保兼容性。
     * @param filePath 文件的本地路径。
     * @return 适配后的 URL。
     */
    private static function adaptPathToURL(filePath:String):String
    {
        // 替换反斜杠为正斜杠
        var path:String = filePath.split("\\").join("/");

        // 前缀 'file:///' 不进行编码
        return "file:///" + path;
    }

    /**
     * 测试特殊字符和 CDATA 的解析。
     */
    private static function testSpecialCharactersAndCDATA():Void
    {
        var filePath:String = basePath + "特殊字符和cdata.xml";
        var url:String = adaptPathToURL(filePath);
        trace("Loading URL: " + url); // 调试输出
        new XMLLoader(url, function(parsedData:Object):Void {
            trace("测试通过：特殊字符和 CDATA 文件加载成功。");
            trace("Parsed Data: " + objectToString(parsedData)); // 调试输出

            // 假设 XML 结构为 <StageInfo><Description>...</Description></StageInfo>
            if (parsedData.StageInfo == undefined) {
                fail("StageInfo 节点未找到。");
                return;
            }

            var description:String = parsedData.StageInfo.Description;
            trace("Parsed Description: " + description); // 调试输出
            assert(description == "这是一个包含特殊字符的描述，测试 <br> 换行。", 
                   "特殊字符解析错误。");
        }, function():Void {
            fail("测试失败：无法加载特殊字符和 CDATA 文件。");
        });
    }

    /**
     * 测试环境设置文件。
     */
    private static function testEnvironmentSettings():Void
    {
        var filePath:String = basePath + "环境设置.xml";
        var url:String = adaptPathToURL(filePath);
        trace("Loading URL: " + url); // 调试输出
        new XMLLoader(url, function(parsedData:Object):Void {
            trace("测试通过：环境设置文件加载成功。");
            trace("Parsed Data: " + objectToString(parsedData)); // 调试输出

            // 假设 XML 结构为 <Environment><BackgroundURL>simple_BG.swf</BackgroundURL></Environment>
            if (parsedData.Environment == undefined) {
                fail("Environment 节点未找到。");
                return;
            }

            var environment:Object = parsedData.Environment;
            var backgroundURL:String;

            if (environment instanceof Array) {
                // 如果 Environment 是数组，取第一个元素
                backgroundURL = environment[0].BackgroundURL;
            } else {
                backgroundURL = environment.BackgroundURL;
            }

            trace("Parsed BackgroundURL: " + backgroundURL); // 调试输出
            assert(backgroundURL == "simple_BG.swf", 
                   "环境设置背景 URL 解析错误。");
        }, function():Void {
            fail("测试失败：无法加载环境设置文件。");
        });
    }

/**
 * 测试空节点和不完整 XML 文件。
 */
private static function testEmptyAndIncomplete():Void {
    var filePath:String = basePath + "空节点且不完整.xml";
    var url:String = adaptPathToURL(filePath);
    trace("Loading URL: " + url); // 调试输出

    new XMLLoader(url, function(parsedData:Object):Void {
        trace("测试通过：空节点和不完整文件加载成功。");
        trace("Parsed Data: " + objectToString(parsedData)); // 调试输出

        // 检查 Environment 节点是否存在
        var environments:Object = parsedData.Environment;
        assert(environments != undefined, "Environment 节点未找到。");

        // 将 Environment 转换为数组进行统一处理
        var envArray;
        if (environments instanceof Array) {
            envArray = environments;
        } else {
            envArray = [environments];
        }

        trace("Parsed Environment Count: " + envArray.length); // 调试输出

        // 检查是否有两个 Environment 节点
        assert(envArray.length == 2, "应解析出 2 个 Environment 节点。");

        // 验证第一个节点
        var env1:Object = envArray[0];
        trace("Parsed Environment 1: " + objectToString(env1)); // 调试输出
        if (env1 != null && typeof(env1) == "object") {
            if (env1.BackgroundURL !== undefined) {
                assert(env1.BackgroundURL == "", "环境 1 中 BackgroundURL 应为空字符串。");
            }
            if (env1.Alignment !== undefined) {
                // 由于 convertDataType 已转换为布尔值，但实际解析中显示为字符串 "false"
                // 需要确保转换逻辑正确
                assert(env1.Alignment == false, "环境 1 中 Alignment 应为 false。");
            }
        } else {
            fail("环境 1 应该存在有效数据。");
        }

        // 验证第二个节点
        var env2:Object = envArray[1];
        trace("Parsed Environment 2: " + objectToString(env2)); // 调试输出

        // 接受空字符串、null 或空对象作为合法结果
        var isEnv2Valid:Boolean = (env2 == null) || (env2 == "") || (objectToString(env2) == "{}");
        assert(isEnv2Valid, "环境 2 应为空对象、空字符串或 null。");
    }, function():Void {
        fail("测试失败：无法加载空节点和不完整文件。");
    });
}




    /**
     * 测试色彩引擎文件。
     */
    private static function testColorEngine():Void
    {
        var filePath:String = basePath + "色彩引擎.xml";
        var url:String = adaptPathToURL(filePath);
        trace("Loading URL: " + url); // 调试输出
        new XMLLoader(url, function(parsedData:Object):Void {
            trace("测试通过：色彩引擎文件加载成功。");
            trace("Parsed Data: " + objectToString(parsedData)); // 调试输出

            // 假设 XML 结构为 <PresetSet><Preset><Brightness>-10</Brightness></Preset></PresetSet>
            if (parsedData.PresetSet == undefined) {
                fail("PresetSet 节点未找到。");
                return;
            }

            var presetSet:Object = parsedData.PresetSet;
            var presets:Array;

            if (presetSet.Preset instanceof Array) {
                presets = presetSet.Preset;
            } else {
                presets = [presetSet.Preset];
            }

            if (presets.length == 0) {
                fail("Preset 节点未找到。");
                return;
            }

            var brightness:Number = Number(presets[0].Brightness);
            trace("Parsed Brightness: " + brightness); // 调试输出
            assert(brightness == -10, 
                   "色彩引擎亮度解析错误。");
        }, function():Void {
            fail("测试失败：无法加载色彩引擎文件。");
        });
    }

    /**
     * 测试大规模数据文件。
     */
    private static function testLargeScale():Void
    {
        var filePath:String = basePath + "超大.xml";
        var url:String = adaptPathToURL(filePath);
        var startTime:Number = getTimer();
        trace("Loading URL: " + url); // 调试输出
        new XMLLoader(url, function(parsedData:Object):Void {
            var endTime:Number = getTimer();
            trace("测试通过：超大文件加载成功。耗时: " + (endTime - startTime) + "ms");
            // trace("Parsed Data: " + objectToString(parsedData)); // 调试输出

            // 假设 XML 结构为 <PresetSet><Preset>...</Preset><Preset>...</Preset>...1000个Preset</PresetSet>
            if (parsedData.PresetSet == undefined) {
                fail("PresetSet 节点未找到。");
                return;
            }

            var presetSet:Object = parsedData.PresetSet;
            var presets:Array;

            if (presetSet.Preset instanceof Array) {
                presets = presetSet.Preset;
            } else {
                presets = [presetSet.Preset];
            }

            trace("Parsed Preset Count: " + presets.length); // 调试输出
            assert(presets.length == 1000, 
                   "超大文件解析错误：未解析所有数据。");
        }, function():Void {
            fail("测试失败：无法加载超大文件。");
        });
    }

    /**
     * 工具方法：断言条件是否成立。
     */
    private static function assert(condition:Boolean, message:String):Void
    {
        if (!condition)
        {
            fail("断言失败: " + message);
        }
    }

    /**
     * 工具方法：输出失败信息。
     */
    private static function fail(message:String):Void
    {
        trace("测试失败: " + message);
    }

    /**
     * 将对象转换为字符串的辅助函数，用于在调试时显示对象内容。
     * @param obj Object 要转换的对象。
     * @return String 对象的字符串表示。
     */
    private static function objectToString(obj:Object):String
    {
        if (obj == null) return "null";
        if (typeof(obj) != "object") return "\"" + obj + "\"";
        var str:String = "{";
        var first:Boolean = true;
        for (var key:String in obj) {
            if (!first) str += ", ";
            str += key + ": " + objectToString(obj[key]);
            first = false;
        }
        str += "}";
        return str;
    }
}
