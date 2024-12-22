import org.flashNight.arki.bullet.BulletComponent.Loader.*;

class org.flashNight.arki.bullet.BulletComponent.Loader.ShellLoader implements IComponentLoader {
    public function ShellLoader() {
        // 构造函数，若需要初始化可以在此实现
    }

    /**
     * 实现接口方法，加载并解析弹壳相关信息
     * @param data:Object 子弹数据节点
     * @return Object 解析后的弹壳信息
     */
    public function load(data:Object):Object {
        var shellInfo:Object = {};
        var shellNode:Object = data.shell;

        if(shellNode != undefined && shellNode.casing != undefined)
        {
            shellInfo.弹壳 = shellNode.casing;
        }
        else
        {
            return null;
        }

        shellInfo.myX = (shellNode != undefined && shellNode.xOffset != undefined) ? Number(shellNode.xOffset) : 0;
        shellInfo.myY = (shellNode != undefined && shellNode.yOffset != undefined) ? Number(shellNode.yOffset) : 0;
        shellInfo.模拟方式 = (shellNode != undefined && shellNode.simulationMethod != undefined) ? shellNode.simulationMethod : "标准";

        return shellInfo;
    }
}