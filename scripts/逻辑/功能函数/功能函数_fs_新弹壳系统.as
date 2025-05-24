import org.flashNight.arki.bullet.BulletComponent.Shell.*;
import org.flashNight.neur.Event.*;
import org.flashNight.arki.bullet.BulletComponent.Movement.Util.*;
import org.flashNight.arki.bullet.BulletComponent.Movement.*;

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

// 订阅场景变更事件
EventBus.getInstance().subscribe("SceneChanged", function() {
    ShellSystem.initializeBulletPools();
}, null);