import org.flashNight.gesh.xml.*;
import org.flashNight.gesh.path.PathManager;

class org.flashNight.gesh.xml.TestXmlLoader {
    /**
     * 主测试方法，用于依次测试所有 XML 文件。
     */
    public static function runTests():Void {
        // 初始化路径管理器
        PathManager.initialize();
        if (!PathManager.isEnvironmentValid()) {
            trace("未检测到资源目录，无法运行测试！");
            return;
        }

        trace("开始测试 XMLLoader 和 XMLParser...");
        testSpecialCharactersAndCDATA();
        testEnvironmentSettings();
        testEmptyAndIncomplete();
        testColorEngine();
        testLargeScale(); // 超大文件由于过长，暂时未进行测试
        trace("所有测试完成。");
    }

    /**
     * 获取完整路径，并验证是否处于有效环境。
     * @param relativePath String 相对路径。
     * @return String 完整路径。
     */
    private static function resolveTestFilePath(relativePath:String):String {
        var scriptsClassDefinitionPath:String = PathManager.getScriptsClassDefinitionPath();
        if (scriptsClassDefinitionPath == null) {
            trace("当前环境无效，无法解析测试文件路径：" + relativePath);
            return null;
        }
        return scriptsClassDefinitionPath + "org/flashNight/gesh/xml/TestXml/" + relativePath;
    }

    /**
     * 测试特殊字符和 CDATA 的解析。
     */
    private static function testSpecialCharactersAndCDATA():Void {
        var filePath:String = resolveTestFilePath("特殊字符和cdata.xml");
        if (filePath == null) return;

        trace("Loading URL: " + filePath); // 调试输出
        new XMLLoader(filePath, function(parsedData:Object):Void {
            trace("测试通过：特殊字符和 CDATA 文件加载成功。");
            trace("Parsed Data: " + objectToString(parsedData)); // 调试输出

            if (parsedData.StageInfo == undefined) {
                fail("StageInfo 节点未找到。");
                return;
            }

            var description:String = parsedData.StageInfo.Description;
            trace("Parsed Description: " + description); // 调试输出
            assert(description == "这是一个包含特殊字符的描述，测试 <br> 换行。", "特殊字符解析错误。");
        }, function():Void {
            fail("测试失败：无法加载特殊字符和 CDATA 文件。");
        });
    }

    /**
     * 测试环境设置文件。
     */
    private static function testEnvironmentSettings():Void {
        var filePath:String = resolveTestFilePath("环境设置.xml");
        if (filePath == null) return;

        trace("Loading URL: " + filePath); // 调试输出
        new XMLLoader(filePath, function(parsedData:Object):Void {
            trace("测试通过：环境设置文件加载成功。");
            trace("Parsed Data: " + objectToString(parsedData)); // 调试输出

            if (parsedData.Environment == undefined) {
                fail("Environment 节点未找到。");
                return;
            }

            var environment:Object = parsedData.Environment;
            var backgroundURL:String;

            if (environment instanceof Array) {
                backgroundURL = environment[0].BackgroundURL;
            } else {
                backgroundURL = environment.BackgroundURL;
            }

            trace("Parsed BackgroundURL: " + backgroundURL); // 调试输出
            assert(backgroundURL == "simple_BG.swf", "环境设置背景 URL 解析错误。");
        }, function():Void {
            fail("测试失败：无法加载环境设置文件。");
        });
    }

    /**
     * 测试空节点和不完整 XML 文件。
     */
    private static function testEmptyAndIncomplete():Void {
        var filePath:String = resolveTestFilePath("空节点且不完整.xml");
        if (filePath == null) return;

        trace("Loading URL: " + filePath); // 调试输出
        new XMLLoader(filePath, function(parsedData:Object):Void {
            trace("测试通过：空节点和不完整文件加载成功。");
            trace("Parsed Data: " + objectToString(parsedData)); // 调试输出

            var environments:Object = parsedData.Environment;
            assert(environments != undefined, "Environment 节点未找到。");

            var envArray = (environments instanceof Array) ? environments : [environments];
            trace("Parsed Environment Count: " + envArray.length); // 调试输出
            assert(envArray.length == 2, "应解析出 2 个 Environment 节点。");

            var env1:Object = envArray[0];
            if (env1 != null && typeof(env1) == "object") {
                if (env1.BackgroundURL !== undefined) {
                    assert(env1.BackgroundURL == "", "环境 1 中 BackgroundURL 应为空字符串。");
                }
                if (env1.Alignment !== undefined) {
                    assert(env1.Alignment == false, "环境 1 中 Alignment 应为 false。");
                }
            } else {
                fail("环境 1 应该存在有效数据。");
            }

            var env2:Object = envArray[1];
            var isEnv2Valid:Boolean = (env2 == null) || (env2 == "") || (objectToString(env2) == "{}");
            assert(isEnv2Valid, "环境 2 应为空对象、空字符串或 null。");
        }, function():Void {
            fail("测试失败：无法加载空节点和不完整文件。");
        });
    }

    /**
     * 测试色彩引擎文件。
     */
    private static function testColorEngine():Void {
        var filePath:String = resolveTestFilePath("色彩引擎.xml");
        if (filePath == null) return;

        trace("Loading URL: " + filePath); // 调试输出
        new XMLLoader(filePath, function(parsedData:Object):Void {
            trace("测试通过：色彩引擎文件加载成功。");
            trace("Parsed Data: " + objectToString(parsedData)); // 调试输出

            if (parsedData.PresetSet == undefined) {
                fail("PresetSet 节点未找到。");
                return;
            }

            var presetSet:Object = parsedData.PresetSet;
            var presets:Array = (presetSet.Preset instanceof Array) ? presetSet.Preset : [presetSet.Preset];

            var brightness:Number = Number(presets[0].Brightness);
            trace("Parsed Brightness: " + brightness); // 调试输出
            assert(brightness == -10, "色彩引擎亮度解析错误。");
        }, function():Void {
            fail("测试失败：无法加载色彩引擎文件。");
        });
    }

    /**
     * 测试大规模数据文件。
     */
    private static function testLargeScale():Void {
        var filePath:String = resolveTestFilePath("超大.xml");
        if (filePath == null) return;

        var startTime:Number = getTimer();
        trace("Loading URL: " + filePath); // 调试输出
        new XMLLoader(filePath, function(parsedData:Object):Void {
            var endTime:Number = getTimer();
            trace("测试通过：超大文件加载成功。耗时: " + (endTime - startTime) + "ms");

            if (parsedData.PresetSet == undefined) {
                fail("PresetSet 节点未找到。");
                return;
            }

            var presetSet:Object = parsedData.PresetSet;
            var presets:Array = (presetSet.Preset instanceof Array) ? presetSet.Preset : [presetSet.Preset];

            trace("Parsed Preset Count: " + presets.length); // 调试输出
            assert(presets.length == 1000, "超大文件解析错误：未解析所有数据。");
        }, function():Void {
            fail("测试失败：无法加载超大文件。");
        });
    }

    /**
     * 工具方法：断言条件是否成立。
     */
    private static function assert(condition:Boolean, message:String):Void {
        if (!condition) {
            fail("断言失败: " + message);
        }
    }

    /**
     * 工具方法：输出失败信息。
     */
    private static function fail(message:String):Void {
        trace("测试失败: " + message);
    }

    /**
     * 将对象转换为字符串的辅助函数，用于在调试时显示对象内容。
     */
    private static function objectToString(obj:Object):String {
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
