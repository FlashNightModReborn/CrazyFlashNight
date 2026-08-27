import org.flashNight.neur.Event.EventBus;
import org.flashNight.neur.Event.Delegate;
import org.flashNight.arki.key.KeyManager;
import org.flashNight.naki.DataStructures.Dictionary;

/**
 * KeyManagerTest 类用于测试 KeyManager 的功能，包括键码映射、事件订阅、事件发布等。
 * 
 * @class org.flashNight.arki.key.KeyManagerTest
 * @version 1.0
 */
class org.flashNight.arki.key.KeyManagerTest {
    private static var migrationTestsRun:Number = 0;
    private static var migrationTestsPassed:Number = 0;
    private static var migrationTestsFailed:Number = 0;

    private var eventBus:EventBus;
    private var controlSettings:Array;
    private var keySettings:Array;
    private var logText:TextField;

    /**
     * 构造函数。初始化测试环境。
     */
    public function KeyManagerTest() {
        // 初始化日志界面
        setupLogUI();
        
        log("[KeyManagerTest] Starting tests...");

        // 初始化 EventBus
        eventBus = EventBus.initialize();
        log("[KeyManagerTest] EventBus initialized.");

        // 定义键值设定
        keySettings = [
            ["Interaction Key", "互动键", 69], // E key
            ["Weapon Skill Key", "武器技能键", 70], // F key
            ["Fly Key", "飞行键", 18], // Alt key
            ["Weapon Transform Key", "武器变形键", 81], // Q key
            ["Run Key", "奔跑键", 16] // Shift key
        ];

        // 初始化 controlSettings
        controlSettings = [];

        // 定义翻译函数 (identity for simplicity)
        var translationFunction:Function = function(str:String):String {
            return str;
        };

        // 刷新键值设定
        KeyManager.refreshKeySettings(keySettings, translationFunction, controlSettings);
        log("[KeyManagerTest] Key settings refreshed.");

        // 订阅键事件
        subscribeToKeyEvents();
        log("[KeyManagerTest] Subscribed to key events.");

        // Schedule additional tests
        scheduleAdditionalTests();

        log("[KeyManagerTest] Initialization complete.");
    }

    /**
     * 设置日志输出的文本字段。
     */
    private function setupLogUI():Void {
        // 创建一个文本字段用于显示日志
        _root.createTextField("logText", _root.getNextHighestDepth(), 10, 10, 600, 400);
        logText = _root.logText;
        logText.multiline = true;
        logText.wordWrap = true;
        logText.border = true;
        logText.background = true;
        logText.backgroundColor = 0xFFFFFF;
        logText.textColor = 0x000000;
        logText.html = true;
        logText.text = "<b>KeyManagerTest Log:</b><br>";
    }

    /**
     * 记录日志信息到文本字段和控制台。
     * 
     * @param message 日志信息
     */
    private function log(message:String):Void {
        logText.text += message + "<br>";
        trace(message);
    }

    /**
     * 订阅 KeyDown 和 KeyUp 事件。
     */
    private function subscribeToKeyEvents():Void {
        for (var i:Number = 0; i < keySettings.length; i++) {
            var keyName:String = keySettings[i][1];
            var keyDownEvent:String = "KeyDown_" + keyName;
            var keyUpEvent:String = "KeyUp_" + keyName;

            // 创建回调函数，捕获 keyName via closure
            var downCallback:Function = createCallback(keyName, "Down");
            var upCallback:Function = createCallback(keyName, "Up");

            // 订阅事件
            eventBus.subscribe(keyDownEvent, downCallback, this);
            eventBus.subscribe(keyUpEvent, upCallback, this);
        }
    }

    /**
     * 创建带有闭包的回调函数。
     * 
     * @param keyName 键名
     * @param eventType "Down" 或 "Up"
     * @return Function 回调函数
     */
    private function createCallback(keyName:String, eventType:String):Function {
        return function():Void {
            var message:String = "Key " + eventType + ": " + keyName;
            log(message);
        };
    }

    /**
     * 安排额外的测试用例。
     */
    private function scheduleAdditionalTests():Void {
        // 创建一个 MovieClip 用于调度测试
        _root.createEmptyMovieClip("testSchedulerMC", _root.getNextHighestDepth());
        _root.testSchedulerMC.onEnterFrame = Delegate.create(this, runScheduledTests);
        _root.testSchedulerMC.frame = 0;
    }

    /**
     * 运行计划中的测试用例。
     */
    private function runScheduledTests():Void {
        _root.testSchedulerMC.frame++;
        var frame:Number = _root.testSchedulerMC.frame;

        // 每隔一定帧数执行不同的测试
        if (frame == 60) { // After ~1 second
            testAddRemoveKeyMapping();
        }
        if (frame == 120) { // After ~2 seconds
            testSubscribeOnce();
        }
        if (frame == 180) { // After ~3 seconds
            testRefreshKeySettings();
        }
        if (frame > 180) { // Stop after all tests
            delete _root.testSchedulerMC.onEnterFrame;
            log("[KeyManagerTest] All scheduled tests completed.");
        }
    }

    /**
     * 测试添加和移除键映射。
     */
    private function testAddRemoveKeyMapping():Void {
        log("[KeyManagerTest] Testing addKeyMapping...");

        // 添加一个新的键映射
        var newKeycode:Number = 72; // H key
        var newKeyName:String = "HKey";
        KeyManager.addKeyMapping(newKeycode, newKeyName);
        log("[KeyManagerTest] Added key mapping: " + newKeyName + " -> " + newKeycode);

        // 订阅新的键事件
        var keyDownEvent:String = "KeyDown_" + newKeyName;
        var keyUpEvent:String = "KeyUp_" + newKeyName;

        var downCallback:Function = createCallback(newKeyName, "Down");
        var upCallback:Function = createCallback(newKeyName, "Up");

        eventBus.subscribe(keyDownEvent, downCallback, this);
        eventBus.subscribe(keyUpEvent, upCallback, this);
        log("[KeyManagerTest] Subscribed to " + keyDownEvent + " and " + keyUpEvent);

        // Schedule removal after 2 seconds
        _root.testSchedulerMC.removeKeyFrame = 240; // 4 seconds
    }

    /**
     * 取消订阅并移除键映射。
     */
    private function removeKeyMapping():Void {
        var newKeyName:String = "HKey";
        var keyDownEvent:String = "KeyDown_" + newKeyName;
        var keyUpEvent:String = "KeyUp_" + newKeyName;

        // Unsubscribe callbacks
        // Note: In this simplified test, we don't store references to the callbacks.
        // In a more robust test, you'd keep references to unsubscribe properly.
        // For demonstration, assuming all HKey events are handled correctly.

        // Remove key mapping
        var keycode:Number = KeyManager.getKeySetting(newKeyName);
        KeyManager.removeKeyMapping(keycode);
        log("[KeyManagerTest] Removed key mapping: " + newKeyName);
    }

    /**
     * 测试一次性订阅。
     */
    private function testSubscribeOnce():Void {
        log("[KeyManagerTest] Testing subscribeOnce...");

        var keyName:String = "互动键"; // Interaction key

        // Define a one-time callback
        var onceCallback:Function = function():Void {
            var message:String = "One-time callback for " + keyName + " triggered.";
            log(message);
        };

        // Subscribe once
        eventBus.subscribeOnce("KeyDown_" + keyName, onceCallback, this);
        log("[KeyManagerTest] Subscribed once to KeyDown_" + keyName);
    }

    /**
     * 测试刷新键设置。
     */
    private function testRefreshKeySettings():Void {
        log("[KeyManagerTest] Testing refreshKeySettings...");

        // Define new key settings
        var newKeySettings:Array = [
            ["Jump Key", "跳跃键", 32], // Spacebar
            ["Crouch Key", "蹲下键", 67] // C key
        ];

        // Define a new translation function
        var newTranslationFunction:Function = function(str:String):String {
            return str;
        };

        // Refresh key settings
        KeyManager.refreshKeySettings(newKeySettings, newTranslationFunction, controlSettings);
        log("[KeyManagerTest] Key settings refreshed with new keys.");

        // Subscribe to new key events
        for (var i:Number = 0; i < newKeySettings.length; i++) {
            var keyName:String = newKeySettings[i][1];
            var keyDownEvent:String = "KeyDown_" + keyName;
            var keyUpEvent:String = "KeyUp_" + keyName;

            var downCallback:Function = createCallback(keyName, "Down");
            var upCallback:Function = createCallback(keyName, "Up");

            eventBus.subscribe(keyDownEvent, downCallback, this);
            eventBus.subscribe(keyUpEvent, upCallback, this);
            log("[KeyManagerTest] Subscribed to " + keyDownEvent + " and " + keyUpEvent);
        }

        // Unsubscribe from old keys
        keySettings = newKeySettings;
        // Note: Assuming KeyManager.refreshKeySettings handles unsubscription of old keys internally.
    }

    /**
     * 运行所有测试。
     */
    public static function run():Void {
        runMigrationTests();
        var test:KeyManagerTest = new KeyManagerTest();
    }

    /** 可由 focused TestLoader 独立调用，不依赖上面的交互式帧调度。 */
    public static function runAllTests():Void {
        runMigrationTests();
    }

    public static function runMigrationTests():Void {
        migrationTestsRun = migrationTestsPassed = migrationTestsFailed = 0;
        trace("--- KeyManagerMigrationTest ---");

        testDrugSwitchDefaultAndFallback();
        testDrugSwitchPreferredFallbackOrder();
        testDrugSwitchDefaultTableFallbackAndPreservation();
        testDrugSwitchAscendingFallbackSkipsReservedKeys();
        testPendingMigrationInfoIsDefensive();

        trace("--- KeyManagerMigrationTest: " + migrationTestsPassed + "/"
            + migrationTestsRun + " passed, " + migrationTestsFailed + " failed ---");
    }

    private static function testDrugSwitchDefaultAndFallback():Void {
        var defaults:Array = buildDrugSwitchDefaults();
        var historic:Array = [
            ["动作A", "动作A", 65],
            ["药剂1", "快捷物品栏键1", 55],
            ["奔跑", "奔跑键", 16]
        ];
        var normalized:Array = KeyManager.normalizeKeySettings(historic, defaults);
        migrationCheck(normalized.length == 4 && codeFor(normalized, "药剂组切换键") == 54,
            "missing switch uses 6 when keycode 54 is free");
        migrationCheck(codeFor(normalized, "动作A") == 65
                && codeFor(normalized, "快捷物品栏键1") == 55,
            "normalization preserves every existing registered logical id value");

        historic[0][2] = 54;
        normalized = KeyManager.normalizeKeySettings(historic, defaults);
        migrationCheck(codeFor(normalized, "动作A") == 54
                && codeFor(normalized, "药剂组切换键") == 84,
            "occupied 6 is preserved and switch deterministically falls back to T");
    }

    private static function testDrugSwitchDefaultTableFallbackAndPreservation():Void {
        var defaults:Array = [
            ["动作A", "动作A", 65],
            ["动作B", "动作B", 66],
            ["动作C", "动作C", 67],
            ["动作D", "动作D", 68],
            ["动作E", "动作E", 69],
            ["动作F", "动作F", 70],
            ["药剂组切换", "药剂组切换键", 54]
        ];
        var historic:Array = [
            ["动作A", "动作A", 54],
            ["动作B", "动作B", 84],
            ["动作C", "动作C", 89],
            ["动作D", "动作D", 86],
            ["动作E", "动作E", 88],
            ["动作F", "动作F", 90]
        ];
        var normalized:Array = KeyManager.normalizeKeySettings(historic, defaults);
        migrationCheck(codeFor(normalized, "药剂组切换键") == 65,
            "after T/Y/V/X/Z the first free authority default code is selected");

        historic.push(["药剂组切换", "药剂组切换键", 90]);
        normalized = KeyManager.normalizeKeySettings(historic, defaults);
        migrationCheck(codeFor(normalized, "药剂组切换键") == 90
                && codeFor(normalized, "动作F") == 90,
            "an existing switch value is preserved without repairing unrelated historical duplicates");
    }

    private static function testDrugSwitchPreferredFallbackOrder():Void {
        var expected:Array = [84, 89, 86, 88, 90];
        var defaults:Array = [
            ["动作0", "动作0", 65],
            ["动作1", "动作1", 66],
            ["动作2", "动作2", 67],
            ["动作3", "动作3", 68],
            ["动作4", "动作4", 69],
            ["动作5", "动作5", 70],
            ["药剂组切换", "药剂组切换键", 54]
        ];
        var occupied:Array = [54, 84, 89, 86, 88];
        for (var stage:Number = 0; stage < expected.length; stage++) {
            var historic:Array = [];
            for (var i:Number = 0; i <= stage; i++) {
                historic.push([
                    "动作" + i,
                    "动作" + i,
                    occupied[i]
                ]);
            }
            var normalized:Array = KeyManager.normalizeKeySettings(
                historic, defaults);
            migrationCheck(
                codeFor(normalized, "药剂组切换键") == expected[stage],
                "preferred switch fallback stage " + stage
                    + " selects " + expected[stage]);
        }
    }

    private static function testDrugSwitchAscendingFallbackSkipsReservedKeys():Void {
        var defaults:Array = [];
        var historic:Array = [];
        var mapped:Array = KeyManager.getAllKeycodes();
        var rowIndex:Number = 0;
        for (var i:Number = 0; i < mapped.length; i++) {
            var code:Number = Number(mapped[i]);
            if (code >= 124 || code == 27
                    || (code >= 112 && code <= 123)) {
                continue;
            }
            var id:String = "占用键" + rowIndex++;
            // 全部 authority defaults 故意复用已占用的 A，确保默认表阶段耗尽；
            // source 则逐项占满 124 以下的所有非保留合法码。
            defaults.push([id, id, 65]);
            historic.push([id, id, code]);
        }
        defaults.push(["药剂组切换", "药剂组切换键", 54]);

        var normalized:Array = KeyManager.normalizeKeySettings(
            historic, defaults);
        migrationCheck(codeFor(normalized, "药剂组切换键") == 144,
            "ascending fallback skips free Esc and F1..F12 after every lower legal and default-table code is occupied");
    }

    private static function testPendingMigrationInfoIsDefensive():Void {
        var oldDefaults:Object = _root.默认键值设定;
        var oldSettings:Object = _root.键值设定;
        var oldControl:Object = _root.按键设定表;
        try {
            KeyManager.clearPendingKeySettingsMigration();
            _root.默认键值设定 = buildDrugSwitchDefaults();
            _root.键值设定 = [
                ["动作A", "动作A", 54],
                ["药剂1", "快捷物品栏键1", 55],
                ["奔跑", "奔跑键", 16]
            ];
            _root.按键设定表 = [[0, 0, 0, 0]];
            KeyManager.refreshKeySettings(_root.键值设定, null, _root.按键设定表[0]);
            var info:Object = KeyManager.getPendingKeySettingsMigrationInfo();
            migrationCheck(KeyManager.hasPendingKeySettingsMigration()
                    && info.id == "药剂组切换键" && info.defaultCode == 54
                    && info.assignedCode == 84,
                "refresh exposes the exact automatic switch assignment while persistence is pending");
            info.assignedCode = 999;
            migrationCheck(KeyManager.getPendingKeySettingsMigrationInfo().assignedCode == 84,
                "pending migration info is returned as a defensive copy");
            KeyManager.clearPendingKeySettingsMigration();
            migrationCheck(KeyManager.getPendingKeySettingsMigrationInfo() == null,
                "the existing durable-save clear boundary also clears migration info");
        } finally {
            _root.默认键值设定 = oldDefaults;
            _root.键值设定 = oldSettings;
            _root.按键设定表 = oldControl;
            KeyManager.clearPendingKeySettingsMigration();
        }
    }

    private static function buildDrugSwitchDefaults():Array {
        return [
            ["动作A", "动作A", 65],
            ["药剂组切换", "药剂组切换键", 54],
            ["药剂1", "快捷物品栏键1", 55],
            ["奔跑", "奔跑键", 16]
        ];
    }

    private static function codeFor(rows:Array, id:String):Number {
        for (var i:Number = 0; i < rows.length; i++) {
            if (String(rows[i][1]) == id) return Number(rows[i][2]);
        }
        return NaN;
    }

    private static function migrationCheck(condition:Boolean, message:String):Void {
        migrationTestsRun++;
        if (condition) {
            migrationTestsPassed++;
            trace("[PASS] " + message);
        } else {
            migrationTestsFailed++;
            trace("[TEST_FAIL] " + message);
        }
    }
}

