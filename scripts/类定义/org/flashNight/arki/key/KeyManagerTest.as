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
        var test:KeyManagerTest = new KeyManagerTest();
    }
}

