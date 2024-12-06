import org.flashNight.arki.bullet.BulletComponent.Loader.*;

class org.flashNight.arki.bullet.BulletComponent.Loader.ShellLoader implements IComponentLoader {
    public function ShellLoader() {
        // 构造函数
    }

    public function load(data:Object):Object {
        var shellInfo:Object = {};
        var shellNode:Object = data.shell;

        shellInfo.弹壳 = (shellNode != undefined && shellNode.casing != undefined) ? shellNode.casing : "步枪弹壳";
        shellInfo.myX = (shellNode != undefined && shellNode.xOffset != undefined) ? Number(shellNode.xOffset) : 0;
        shellInfo.myY = (shellNode != undefined && shellNode.yOffset != undefined) ? Number(shellNode.yOffset) : 0;
        shellInfo.模拟方式 = (shellNode != undefined && shellNode.simulationMethod != undefined) ? shellNode.simulationMethod : "标准";

        // 若 shellNode 中包含 name 字段，可在这里直接解析
        // 不过这里建议只处理当前组件的逻辑，不赋 name，以保持组件专注点
        // 让 InfoLoader 在整合阶段插入 name

        return shellInfo;
    }
}