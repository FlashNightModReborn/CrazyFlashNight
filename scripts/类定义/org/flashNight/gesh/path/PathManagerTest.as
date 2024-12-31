import org.flashNight.gesh.path.PathManager;
import org.flashNight.gesh.regexp.RegExp;

class org.flashNight.gesh.path.PathManagerTest {

    /**
     * 入口方法：执行所有测试用例。
     */
    public static function runTests():Void {
        trace("=== 开始测试 PathManager ===");

        // 1. 测试环境检测
        testEnvironmentCheck();

        // 2. 测试在 C 盘环境中的路径解析
        testResolvePathOnCDrive();

        // 3. 测试在 非 C 盘 环境中的路径解析
        testResolvePathOnNonCDrive();

        // 4. 测试在浏览器环境中的解析
        testBrowserEnvironment();

        // 5. 测试无效 URL 处理
        testInvalidURL();

        // 6. 测试相对路径以 "resources/" 开头的情况
        testRelativePathWithResources();

        // 7. 测试相对路径不以 "resources/" 开头的情况
        testRelativePathWithoutResources();

        // 8. 新增测试：不同驱动器的路径解析
        testResolvePathOnDDrive();
        testResolvePathOnEDrive();

        // 9. 新增测试：路径中包含空格
        testPathWithSpaces();

        // 10. 新增测试：路径中包含中文字符
        testPathWithChineseCharacters();

        // 11. 新增测试：路径缺少尾部斜杠
        testPathWithoutTrailingSlash();

        // 12. 新增测试：使用反斜杠作为路径分隔符
        testPathWithBackslashes();

        // 13. 新增测试：完全无效的路径格式
        testCompletelyInvalidPath();

        // 14. 新增测试：配置多个基础路径
        testConfigureMultipleBasePaths();

        // 15. 新增测试：基础路径优先级
        testBasePathPriority();

        // 16. 新增测试：解析路径在多个基础路径下的表现
        testResolvePathWithMultipleBasePaths();

        // 17. 新增测试：添加基础路径后重置
        testAddBasePathAndReset();

        // 18. 新增测试：设置所有基础路径
        testSetAllBasePaths();

        // 19. 新增测试：本地环境下 CrazyFlashNight/ 基础路径解析
        testLocalCrazyFlashNightPath();

        // 20. 打印最终汇总
        trace("=== PathManager 测试结束 ===\n");
    }

    /**
     * 测试: 环境检测是否准确
     */
    private static function testEnvironmentCheck():Void {
        trace("[Test] testEnvironmentCheck()");

        // Reset PathManager
        PathManager.reset();

        // Initialize without parameters
        PathManager.initialize();

        // 检测是否有效环境
        var valid:Boolean = PathManager.isEnvironmentValid();
        trace("  isEnvironmentValid = " + valid);

        // 检测是否浏览器环境
        var isBrowser:Boolean = PathManager.isBrowserEnv();
        trace("  isBrowserEnv = " + isBrowser);

        // 打印当前 PathManager 状态
        trace("  PathManager.toString(): " + PathManager.toString());
    }

    /**
     * 测试: C 盘上的路径解析
     */
    private static function testResolvePathOnCDrive():Void {
        trace("[Test] testResolvePathOnCDrive()");

        // Reset PathManager
        PathManager.reset();

        // Simulate C drive environment
        var cDriveUrl:String = "file:///C:/path/to/resources/";
        PathManager.initialize(cDriveUrl);

        // 假定要解析的相对路径
        var relativePath:String = "images/test.png";
        var resolvedPath:String = PathManager.resolvePath(relativePath);

        trace("  Relative Path: " + relativePath);
        trace("  解析后的路径: " + resolvedPath);

        // 检查解析结果中是否包含 C: 或 C|
        if (resolvedPath != null) {
            var cDriveRegex:RegExp = new RegExp("^file:///C[|:]", "i");
            var isOnCDrive:Boolean = cDriveRegex.test(resolvedPath);
            trace("  是否在 C: 或 C| 盘: " + isOnCDrive);
        } else {
            trace("  [警告] 解析返回空，环境可能无效或未在 C: 盘。");
        }
    }

    /**
     * 测试: 非 C 盘上的路径解析
     */
    private static function testResolvePathOnNonCDrive():Void {
        trace("[Test] testResolvePathOnNonCDrive()");

        // Reset PathManager
        PathManager.reset();

        // Simulate non-C drive environment
        var nonCDriveUrl:String = "file:///D:/path/to/resources/";
        PathManager.initialize(nonCDriveUrl);

        // 假定要解析的相对路径
        var relativePath:String = "resources/data/config.xml";
        var resolvedPath:String = PathManager.resolvePath(relativePath);

        trace("  Relative Path: " + relativePath);
        trace("  解析后的路径: " + resolvedPath);

        // 使用正则检测盘符
        if (resolvedPath != null) {
            // 这里匹配形如 file:///D: 或 file:///D| 等等
            var nonCDriveRegex:RegExp = new RegExp("^file:///[D-Zd-z][|:]", "i");
            var isOnNonCDrive:Boolean = nonCDriveRegex.test(resolvedPath);
            trace("  是否在 非C 盘: " + isOnNonCDrive);

            // 对测试结果进行汇总
            if (isOnNonCDrive) {
                trace("  [信息] 在非C盘环境中解析成功，建议查看文件是否能正常加载。");
            } else {
                trace("  [信息] 该路径不在非C盘，或解析不符合预期。");
            }
        } else {
            trace("  [错误] 解析返回 null，说明 PathManager 认为此环境无效或无法解析。");
        }
    }

    /**
     * 测试: 浏览器环境解析
     */
    private static function testBrowserEnvironment():Void {
        trace("[Test] testBrowserEnvironment()");

        // Reset PathManager
        PathManager.reset();

        // Simulate browser environment
        var browserUrl:String = "http://yourserver.com/resources/";
        PathManager.initialize(browserUrl);

        // 检测是否浏览器环境
        var isBrowser:Boolean = PathManager.isBrowserEnv();
        trace("  isBrowserEnv = " + isBrowser);

        // 测试解析 scripts/类定义/ 路径
        var scriptsPath:String = PathManager.getScriptsClassDefinitionPath();
        trace("  浏览器环境下 scripts/类定义/ 路径: " + scriptsPath);

        // Check if scriptsPath is as expected
        var expectedPath:String = "http://yourserver.com/resources/scripts/类定义/";
        if (scriptsPath == expectedPath) {
            trace("  [成功] 路径解析正确。");
        } else {
            trace("  [失败] 路径解析错误，预期: " + expectedPath + "，实际: " + scriptsPath);
        }
    }

    /**
     * 测试: 无效 URL 处理
     */
    private static function testInvalidURL():Void {
        trace("[Test] testInvalidURL()");

        // Reset PathManager
        PathManager.reset();

        // Pass an invalid URL
        var invalidUrl:String = "invalid://url";
        PathManager.initialize(invalidUrl);

        // 检测是否有效环境
        var valid:Boolean = PathManager.isEnvironmentValid();
        trace("  isEnvironmentValid = " + valid);

        // 检测是否浏览器环境
        var isBrowser:Boolean = PathManager.isBrowserEnv();
        trace("  isBrowserEnv = " + isBrowser);

        // Check if environment is invalid
        if (!valid) {
            trace("  [成功] 无效 URL 正确识别为无效环境。");
        } else {
            trace("  [失败] 无效 URL 被识别为有效环境。");
        }
    }

    /**
     * 测试: 相对路径以 "resources/" 开头的情况
     */
    private static function testRelativePathWithResources():Void {
        trace("[Test] testRelativePathWithResources()");

        // Reset PathManager
        PathManager.reset();

        // Simulate C drive environment
        var cDriveUrl:String = "file:///C:/path/to/resources/";
        PathManager.initialize(cDriveUrl);

        // Relative path starting with "resources/"
        var relativePath:String = "resources/data/config.xml";
        var resolvedPath:String = PathManager.resolvePath(relativePath);

        trace("  Relative Path: " + relativePath);
        trace("  解析后的路径: " + resolvedPath);

        // Expected resolved path: "file:///C:/path/to/resources/data/config.xml"
        var expectedPath:String = "file:///C:/path/to/resources/data/config.xml";
        if (resolvedPath == expectedPath) {
            trace("  [成功] 路径解析正确。");
        } else {
            trace("  [失败] 路径解析错误，预期: " + expectedPath + "，实际: " + resolvedPath);
        }
    }

    /**
     * 测试: 相对路径不以 "resources/" 开头的情况
     */
    private static function testRelativePathWithoutResources():Void {
        trace("[Test] testRelativePathWithoutResources()");

        // Reset PathManager
        PathManager.reset();

        // Simulate C drive environment
        var cDriveUrl:String = "file:///C:/path/to/resources/";
        PathManager.initialize(cDriveUrl);

        // Relative path not starting with "resources/"
        var relativePath:String = "data/config.xml";
        var resolvedPath:String = PathManager.resolvePath(relativePath);

        trace("  Relative Path: " + relativePath);
        trace("  解析后的路径: " + resolvedPath);

        // Expected resolved path: "file:///C:/path/to/resources/data/config.xml"
        var expectedPath:String = "file:///C:/path/to/resources/data/config.xml";
        if (resolvedPath == expectedPath) {
            trace("  [成功] 路径解析正确。");
        } else {
            trace("  [失败] 路径解析错误，预期: " + expectedPath + "，实际: " + resolvedPath);
        }
    }

    /**
     * 新增测试: D 盘上的路径解析
     */
    private static function testResolvePathOnDDrive():Void {
        trace("[Test] testResolvePathOnDDrive()");

        // Reset PathManager
        PathManager.reset();

        // Simulate D drive environment
        var dDriveUrl:String = "file:///D:/projects/resources/";
        PathManager.initialize(dDriveUrl);

        // Relative path to resolve
        var relativePath:String = "assets/images/logo.png";
        var resolvedPath:String = PathManager.resolvePath(relativePath);

        trace("  Relative Path: " + relativePath);
        trace("  解析后的路径: " + resolvedPath);

        // Expected resolved path: "file:///D:/projects/resources/assets/images/logo.png"
        var expectedPath:String = "file:///D:/projects/resources/assets/images/logo.png";
        if (resolvedPath == expectedPath) {
            trace("  [成功] 路径解析正确。");
        } else {
            trace("  [失败] 路径解析错误，预期: " + expectedPath + "，实际: " + resolvedPath);
        }
    }

    /**
     * 新增测试: E 盘上的路径解析
     */
    private static function testResolvePathOnEDrive():Void {
        trace("[Test] testResolvePathOnEDrive()");

        // Reset PathManager
        PathManager.reset();

        // Simulate E drive environment
        var eDriveUrl:String = "file:///E:/media/resources/";
        PathManager.initialize(eDriveUrl);

        // Relative path to resolve
        var relativePath:String = "videos/intro.mp4";
        var resolvedPath:String = PathManager.resolvePath(relativePath);

        trace("  Relative Path: " + relativePath);
        trace("  解析后的路径: " + resolvedPath);

        // Expected resolved path: "file:///E:/media/resources/videos/intro.mp4"
        var expectedPath:String = "file:///E:/media/resources/videos/intro.mp4";
        if (resolvedPath == expectedPath) {
            trace("  [成功] 路径解析正确。");
        } else {
            trace("  [失败] 路径解析错误，预期: " + expectedPath + "，实际: " + resolvedPath);
        }
    }

    /**
     * 新增测试: 路径中包含空格
     */
    private static function testPathWithSpaces():Void {
        trace("[Test] testPathWithSpaces()");

        // Reset PathManager
        PathManager.reset();

        // Simulate C drive environment with spaces in path
        var spacedPathUrl:String = "file:///C:/Program Files/My App/resources/";
        PathManager.initialize(spacedPathUrl);

        // Relative path to resolve
        var relativePath:String = "assets/images/my logo.png";
        var resolvedPath:String = PathManager.resolvePath(relativePath);

        trace("  Relative Path: " + relativePath);
        trace("  解析后的路径: " + resolvedPath);

        // Expected resolved path: "file:///C:/Program Files/My App/resources/assets/images/my logo.png"
        var expectedPath:String = "file:///C:/Program Files/My App/resources/assets/images/my logo.png";
        if (resolvedPath == expectedPath) {
            trace("  [成功] 路径解析正确。");
        } else {
            trace("  [失败] 路径解析错误，预期: " + expectedPath + "，实际: " + resolvedPath);
        }
    }

    /**
     * 新增测试: 路径中包含中文字符
     */
    private static function testPathWithChineseCharacters():Void {
        trace("[Test] testPathWithChineseCharacters()");

        // Reset PathManager
        PathManager.reset();

        // Simulate C drive environment with Chinese characters in path
        var chinesePathUrl:String = "file:///C:/项目/resources/";
        PathManager.initialize(chinesePathUrl);

        // Relative path to resolve
        var relativePath:String = "数据/config.xml";
        var resolvedPath:String = PathManager.resolvePath(relativePath);

        trace("  Relative Path: " + relativePath);
        trace("  解析后的路径: " + resolvedPath);

        // Expected resolved path: "file:///C:/项目/resources/数据/config.xml"
        var expectedPath:String = "file:///C:/项目/resources/数据/config.xml";
        if (resolvedPath == expectedPath) {
            trace("  [成功] 路径解析正确。");
        } else {
            trace("  [失败] 路径解析错误，预期: " + expectedPath + "，实际: " + resolvedPath);
        }
    }

    /**
     * 新增测试: 路径缺少尾部斜杠
     */
    private static function testPathWithoutTrailingSlash():Void {
        trace("[Test] testPathWithoutTrailingSlash()");

        // Reset PathManager
        PathManager.reset();

        // Simulate C drive environment without trailing slash
        var noSlashUrl:String = "file:///C:/path/to/resources";
        PathManager.initialize(noSlashUrl);

        // Relative path to resolve
        var relativePath:String = "assets/data.json";
        var resolvedPath:String = PathManager.resolvePath(relativePath);

        trace("  Relative Path: " + relativePath);
        trace("  解析后的路径: " + resolvedPath);

        // Expected resolved path: "file:///C:/path/to/resources/assets/data.json"
        var expectedPath:String = "file:///C:/path/to/resources/assets/data.json";
        if (resolvedPath == expectedPath) {
            trace("  [成功] 路径解析正确，并正确添加尾部斜杠。");
        } else {
            trace("  [失败] 路径解析错误，预期: " + expectedPath + "，实际: " + resolvedPath);
        }
    }

    /**
     * 新增测试: 使用反斜杠作为路径分隔符
     */
    private static function testPathWithBackslashes():Void {
        trace("[Test] testPathWithBackslashes()");

        // Reset PathManager
        PathManager.reset();

        // Simulate C drive environment with backslashes in URL
        var backslashUrl:String = "file:///C:\\path\\to\\resources\\";
        PathManager.initialize(backslashUrl);

        // Relative path to resolve
        var relativePath:String = "assets\\images\\logo.png";
        var resolvedPath:String = PathManager.resolvePath(relativePath);

        trace("  Relative Path: " + relativePath);
        trace("  解析后的路径: " + resolvedPath);

        // Expected resolved path: "file:///C:/path/to/resources/assets/images/logo.png"
        var expectedPath:String = "file:///C:/path/to/resources/assets/images/logo.png";
        if (resolvedPath == expectedPath) {
            trace("  [成功] 反斜杠被正确转换为斜杠，路径解析正确。");
        } else {
            trace("  [失败] 路径解析错误，预期: " + expectedPath + "，实际: " + resolvedPath);
        }
    }

    /**
     * 新增测试: 完全无效的路径格式
     */
    private static function testCompletelyInvalidPath():Void {
        trace("[Test] testCompletelyInvalidPath()");

        // Reset PathManager
        PathManager.reset();

        // Pass a completely invalid URL
        var invalidPath:String = "ht!tp://@invalid_path";
        PathManager.initialize(invalidPath);

        // Attempt to resolve a path
        var relativePath:String = "assets/data.json";
        var resolvedPath:String = PathManager.resolvePath(relativePath);

        trace("  Relative Path: " + relativePath);
        trace("  解析后的路径: " + resolvedPath);

        // Expected: null, since the environment is invalid
        if (resolvedPath == null) {
            trace("  [成功] 完全无效的路径被正确识别，无法解析。");
        } else {
            trace("  [失败] 完全无效的路径未被正确处理，解析结果: " + resolvedPath);
        }
    }

    /**
     * 新增测试: 配置多个基础路径
     */
    private static function testConfigureMultipleBasePaths():Void {
        trace("[Test] testConfigureMultipleBasePaths()");

        // Reset PathManager
        PathManager.reset();

        // 设置多个基础路径
        PathManager.setBasePaths(["resources/", "CrazyFlashNight/"]);

        // Simulate browser environment with multiple base paths
        var browserUrl:String = "http://yourserver.com/CrazyFlashNight/";
        PathManager.initialize(browserUrl);

        // 检测是否浏览器环境
        var isBrowser:Boolean = PathManager.isBrowserEnv();
        trace("  isBrowserEnv = " + isBrowser);

        // 获取基础路径
        var basePath:String = PathManager.getBasePath();
        trace("  basePath = " + basePath);

        // 预期基础路径应为 "http://yourserver.com/CrazyFlashNight/"
        var expectedBasePath:String = "http://yourserver.com/CrazyFlashNight/";
        if (basePath == expectedBasePath) {
            trace("  [成功] 基础路径配置正确。");
        } else {
            trace("  [失败] 基础路径配置错误，预期: " + expectedBasePath + "，实际: " + basePath);
        }
    }

    /**
     * 新增测试: 基础路径优先级
     */
    private static function testBasePathPriority():Void {
        trace("[Test] testBasePathPriority()");

        // Reset PathManager
        PathManager.reset();

        // 设置多个基础路径，先设置 "CrazyFlashNight/"，后设置 "resources/"
        PathManager.setBasePaths(["CrazyFlashNight/", "resources/"]);

        // Simulate environment where both base paths are present
        var testUrl:String = "http://yourserver.com/CrazyFlashNight/";
        PathManager.initialize(testUrl);

        // 基础路径应为 "CrazyFlashNight/"，因为它在列表中排在前面
        var basePath:String = PathManager.getBasePath();
        var expectedBasePath:String = "http://yourserver.com/CrazyFlashNight/";
        if (basePath == expectedBasePath) {
            trace("  [成功] 基础路径优先级正确，选择了列表中第一个匹配的路径。");
        } else {
            trace("  [失败] 基础路径优先级错误，预期: " + expectedBasePath + "，实际: " + basePath);
        }
    }

    /**
     * 新增测试: 解析路径在多个基础路径下的表现
     */
    private static function testResolvePathWithMultipleBasePaths():Void {
        trace("[Test] testResolvePathWithMultipleBasePaths()");

        // Reset PathManager
        PathManager.reset();

        // 设置多个基础路径
        PathManager.setBasePaths(["CrazyFlashNight/", "resources/"]);

        // Simulate environment with "resources/" in URL
        var testUrl:String = "http://yourserver.com/resources/";
        PathManager.initialize(testUrl);

        // 解析一个以 "resources/" 开头的相对路径
        var relativePath1:String = "resources/assets/image.png";
        var resolvedPath1:String = PathManager.resolvePath(relativePath1);
        var expectedPath1:String = "http://yourserver.com/resources/assets/image.png";
        trace("  Relative Path: " + relativePath1);
        trace("  解析后的路径: " + resolvedPath1);
        if (resolvedPath1 == expectedPath1) {
            trace("  [成功] 路径解析正确。");
        } else {
            trace("  [失败] 路径解析错误，预期: " + expectedPath1 + "，实际: " + resolvedPath1);
        }

        // 解析一个不以 "resources/" 开头的相对路径
        var relativePath2:String = "assets/data.json";
        var resolvedPath2:String = PathManager.resolvePath(relativePath2);
        var expectedPath2:String = "http://yourserver.com/resources/assets/data.json";
        trace("  Relative Path: " + relativePath2);
        trace("  解析后的路径: " + resolvedPath2);
        if (resolvedPath2 == expectedPath2) {
            trace("  [成功] 路径解析正确。");
        } else {
            trace("  [失败] 路径解析错误，预期: " + expectedPath2 + "，实际: " + resolvedPath2);
        }
    }

    /**
     * 新增测试: 添加基础路径后重置
     */
    private static function testAddBasePathAndReset():Void {
        trace("[Test] testAddBasePathAndReset()");

        // Reset PathManager
        PathManager.reset();

        // 添加一个新的基础路径
        PathManager.addBasePath("newBasePath/");
        trace("  添加新的基础路径 'newBasePath/'");

        // 设置基础路径列表
        PathManager.setBasePaths(["resources/", "CrazyFlashNight/", "newBasePath/"]);

        // 初始化 PathManager
        var testUrl:String = "http://yourserver.com/newBasePath/";
        PathManager.initialize(testUrl);

        // 获取基础路径
        var basePath:String = PathManager.getBasePath();
        var expectedBasePath:String = "http://yourserver.com/newBasePath/";
        trace("  basePath = " + basePath);

        if (basePath == expectedBasePath) {
            trace("  [成功] 新添加的基础路径被正确识别和设置。");
        } else {
            trace("  [失败] 新添加的基础路径未被正确识别，预期: " + expectedBasePath + "，实际: " + basePath);
        }

        // 重置 PathManager
        PathManager.reset();
        trace("  PathManager 已重置。");

        // 检查 PathManager 状态
        var valid:Boolean = PathManager.isEnvironmentValid();
        trace("  初始化后是否有效环境: " + valid);
    }

    /**
     * 新增测试: 设置所有基础路径
     */
    private static function testSetAllBasePaths():Void {
        trace("[Test] testSetAllBasePaths()");

        // Reset PathManager
        PathManager.reset();

        // 设置所有基础路径
        var newBasePaths:Array = ["resources/", "CrazyFlashNight/", "assets/"];
        PathManager.setBasePaths(newBasePaths);
        trace("  设置所有基础路径为: " + newBasePaths.join(", "));

        // Simulate environment matching "assets/"
        var testUrl:String = "file:///C:/app/assets/";
        PathManager.initialize(testUrl);

        // 获取基础路径
        var basePath:String = PathManager.getBasePath();
        var expectedBasePath:String = "file:///C:/app/assets/";
        trace("  basePath = " + basePath);

        if (basePath == expectedBasePath) {
            trace("  [成功] 基础路径 'assets/' 被正确识别和设置。");
        } else {
            trace("  [失败] 基础路径 'assets/' 未被正确识别，预期: " + expectedBasePath + "，实际: " + basePath);
        }

        // 解析一个相对路径
        var relativePath:String = "images/logo.png";
        var resolvedPath:String = PathManager.resolvePath(relativePath);
        var expectedResolvedPath:String = "file:///C:/app/assets/images/logo.png";
        trace("  Relative Path: " + relativePath);
        trace("  解析后的路径: " + resolvedPath);
        if (resolvedPath == expectedResolvedPath) {
            trace("  [成功] 路径解析正确。");
        } else {
            trace("  [失败] 路径解析错误，预期: " + expectedResolvedPath + "，实际: " + resolvedPath);
        }
    }

    /**
     * 新增测试: 基础路径优先级 - 列表中后面的基础路径优先级更低
     */
    private static function testBasePathPriorityMultipleMatches():Void {
        trace("[Test] testBasePathPriorityMultipleMatches()");

        // Reset PathManager
        PathManager.reset();

        // 设置多个基础路径
        PathManager.setBasePaths(["resources/", "CrazyFlashNight/", "assets/"]);

        // Simulate environment where URL contains multiple base paths
        var testUrl:String = "http://yourserver.com/resources/CrazyFlashNight/";
        PathManager.initialize(testUrl);

        // 获取基础路径
        var basePath:String = PathManager.getBasePath();
        var expectedBasePath:String = "http://yourserver.com/resources/CrazyFlashNight/";
        trace("  basePath = " + basePath);

        // 基础路径应为 "resources/"，因为它在列表中排在前面
        var expectedFirstMatch:String = "http://yourserver.com/resources/CrazyFlashNight/";
        if (basePath == expectedFirstMatch) {
            trace("  [成功] 基础路径优先级正确，选择了列表中第一个匹配的路径。");
        } else {
            trace("  [失败] 基础路径优先级错误，预期: " + expectedFirstMatch + "，实际: " + basePath);
        }
    }

    /**
     * 新增测试: 本地环境下 CrazyFlashNight/ 基础路径解析
     */
    private static function testLocalCrazyFlashNightPath():Void {
        trace("[Test] testLocalCrazyFlashNightPath()");

        // Reset PathManager
        PathManager.reset();

        // 设置基础路径列表
        PathManager.setBasePaths(["resources/", "CrazyFlashNight/"]);

        // Simulate local environment with CrazyFlashNight/
        var crazyFlashNightUrl:String = "file:///C:/path/to/CrazyFlashNight/";
        PathManager.initialize(crazyFlashNightUrl);

        // 检查是否有效环境
        var valid:Boolean = PathManager.isEnvironmentValid();
        trace("  isEnvironmentValid = " + valid);

        // 检查是否浏览器环境
        var isBrowser:Boolean = PathManager.isBrowserEnv();
        trace("  isBrowserEnv = " + isBrowser);

        // 获取基础路径
        var basePath:String = PathManager.getBasePath();
        var expectedBasePath:String = "file:///C:/path/to/CrazyFlashNight/";
        trace("  basePath = " + basePath);

        if (basePath == expectedBasePath) {
            trace("  [成功] 本地环境下 'CrazyFlashNight/' 基础路径被正确识别和设置。");
        } else {
            trace("  [失败] 本地环境下 'CrazyFlashNight/' 基础路径识别错误，预期: " + expectedBasePath + "，实际: " + basePath);
        }

        // 解析一个以 "CrazyFlashNight/" 开头的相对路径
        var relativePath1:String = "CrazyFlashNight/assets/image.png";
        var resolvedPath1:String = PathManager.resolvePath(relativePath1);
        var expectedPath1:String = "file:///C:/path/to/CrazyFlashNight/assets/image.png";
        trace("  Relative Path: " + relativePath1);
        trace("  解析后的路径: " + resolvedPath1);
        if (resolvedPath1 == expectedPath1) {
            trace("  [成功] 路径解析正确。");
        } else {
            trace("  [失败] 路径解析错误，预期: " + expectedPath1 + "，实际: " + resolvedPath1);
        }

        // 解析一个不以基础路径开头的相对路径
        var relativePath2:String = "assets/data.json";
        var resolvedPath2:String = PathManager.resolvePath(relativePath2);
        var expectedPath2:String = "file:///C:/path/to/CrazyFlashNight/assets/data.json";
        trace("  Relative Path: " + relativePath2);
        trace("  解析后的路径: " + resolvedPath2);
        if (resolvedPath2 == expectedPath2) {
            trace("  [成功] 路径解析正确。");
        } else {
            trace("  [失败] 路径解析错误，预期: " + expectedPath2 + "，实际: " + resolvedPath2);
        }
    }
}
