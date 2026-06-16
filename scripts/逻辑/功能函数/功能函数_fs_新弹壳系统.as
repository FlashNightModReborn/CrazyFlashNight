
// 初始化Shell系统
ShellSystem.initialize();
MovementSystem.initialize();
// 初始化导弹配置
var missileConfigManager:MissileConfig = MissileConfig.getInstance();
missileConfigManager.loadConfigs(
    function(configs:Object):Void {
        // 配置加载成功的回调
        _root.服务器.发布服务器消息("导弹配置加载成功");
        // 你可以在这里执行依赖配置的初始化操作
    },
    function():Void {
        // 配置加载失败的回调
        _root.服务器.发布服务器消息("导弹配置加载失败，使用默认配置");
    }
);

// 订阅场景运行时重置事件：确保在全局 EnhancedCooldownWheel 清理后重建弹壳循环
EventBus.getInstance().subscribe("SceneRuntimeReset", function() {
    ShellSystem.initializeBulletPools();
}, null);
