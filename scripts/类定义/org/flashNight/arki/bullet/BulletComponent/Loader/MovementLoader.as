import org.flashNight.arki.bullet.BulletComponent.Loader.*;

class org.flashNight.arki.bullet.BulletComponent.Loader.MovementLoader implements IComponentLoader {
    public function MovementLoader() {
        // 构造函数，若需要初始化可以在此实现
    }

    /**
     * 实现接口方法，加载并解析移动相关信息
     * @param data:Object 子弹数据节点
     * @return Object 解析后的移动信息，如果必要信息缺失则返回 null
     */
    public function load(data:Object):Object {
        var movementInfo:Object = {};
        var movementNode:Object = data.movement;

        // 检查 movement 节点是否存在
        if(movementNode == undefined) {
            return null;
        }

        // 读取 func 属性，必须存在
        if(movementNode.func == undefined) {
            return null;
        }
        movementInfo.func = movementNode.func;

        // 读取参数信息
        movementInfo.param = {};
        
        // 如果存在 param 节点，解析其中的配置项
        if(movementNode.param != undefined) {
            var paramNode = movementNode.param;
            
            // 读取 missileConfig 参数，如果存在
            if(paramNode.missileConfig != undefined) {
                movementInfo.param.missileConfig = paramNode.missileConfig;
            }
            
            // 读取 usePreLaunch 参数，默认为 true
            if(paramNode.usePreLaunch != undefined) {
                var usePreLaunch = String(paramNode.usePreLaunch).toLowerCase();
                movementInfo.param.usePreLaunch = (usePreLaunch == "true" || usePreLaunch == "1");
            } else {
                movementInfo.param.usePreLaunch = true; // 默认值
            }
            
            // 如果以后有更多参数，可以在这里继续解析
        }

        return movementInfo;
    }
}