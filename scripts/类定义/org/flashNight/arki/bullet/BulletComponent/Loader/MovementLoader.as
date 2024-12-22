import org.flashNight.arki.bullet.BulletComponent.Loader.*;


class org.flashNight.arki.bullet.BulletComponent.Loader.MovementLoader implements IComponentLoader {
    public function MovementLoader() {
        // 构造函数，若需要初始化可以在此实现
    }

    /**
     * 实现接口方法，加载并解析弹壳相关信息
     * @param data:Object 子弹数据节点
     * @return Object 解析后的弹壳信息
     */
    public function load(data:Object):Object {
        var movementInfo:Object = {};
        var movementNode:Object = data.movement;

        /*

        movementInfo.弹壳 = (movementNode != undefined && movementNode.casing != undefined) ? movementNode.casing : "步枪弹壳";
        movementInfo.myX = (movementNode != undefined && movementNode.xOffset != undefined) ? Number(movementNode.xOffset) : 0;
        movementInfo.myY = (movementNode != undefined && movementNode.yOffset != undefined) ? Number(movementNode.yOffset) : 0;
        movementInfo.模拟方式 = (movementNode != undefined && movementNode.simulationMethod != undefined) ? movementNode.simulationMethod : "标准";

        */
        return movementInfo;
    }
}