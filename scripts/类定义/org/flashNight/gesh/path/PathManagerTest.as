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

        // 4. 测试在浏览器环境中的解析 (如可能，需要在浏览器里运行此测试)
        testBrowserEnvironment();

        // 5. 打印最终汇总
        trace("=== PathManager 测试结束 ===\n");
    }

    /**
     * 测试: 环境检测是否准确
     */
    private static function testEnvironmentCheck():Void {
        trace("[Test] testEnvironmentCheck()");

        // 强制初始化
        var basePath:String = PathManager.getBasePath();

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
     * 假设你在 C 盘下运行 SWF 文件，进行解析并查看是否成功。
     */
    private static function testResolvePathOnCDrive():Void {
        trace("[Test] testResolvePathOnCDrive()");

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
     * 已知问题：在非 C 盘上无法成功运行。
     * 这里模拟或真实验证该场景，以便定位和确认 bug。
     */
    private static function testResolvePathOnNonCDrive():Void {
        trace("[Test] testResolvePathOnNonCDrive()");

        // 同理，假定要解析的相对路径
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
     * 测试: 浏览器环境解析（如需要在浏览器中测试）
     */
    private static function testBrowserEnvironment():Void {
        trace("[Test] testBrowserEnvironment()");

        var isBrowser:Boolean = PathManager.isBrowserEnv();
        if (!isBrowser) {
            trace("  [提示] 当前并未检测到浏览器环境，跳过浏览器测试。");
            return;
        }

        // 假设服务器资源路径为 http://yourserver.com/resources/
        // 测试解析 scripts/类定义/ 路径
        var scriptsPath:String = PathManager.getScriptsClassDefinitionPath();
        trace("  浏览器环境下 scripts/类定义/ 路径: " + scriptsPath);
    }
}
