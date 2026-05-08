// 文件路径：org/flashNight/dev/SkinReadyProbe.as
//
// 用途：测 Object.registerClass + 类方法 onLoad 在 FP20 attachMovie 路径上的触发情况
// 配套 runner：scripts/TestLoader.as 的 T5 段落
// 配套文档：agentsDoc/as2-load-timing.md 第 3 节方案 B
//
// 三个钩子各 trace 一行，对照子 onClipEvent(load) 在序号流中的位置即可定时序：
//   - 构造函数（initialize 阶段）
//   - onLoad 类方法（关键测试点）
//   - onEnterFrame 类方法（一次性）

dynamic class org.flashNight.dev.SkinReadyProbe extends MovieClip {

    private var efFired:Boolean;

    public function SkinReadyProbe() {
        this.efFired = false;
        _root["标记"](_root["探测"]("[CLS] constructor", this));
    }

    public function onLoad():Void {
        _root["标记"](_root["探测"]("[CLS] onLoad", this));
    }

    public function onEnterFrame():Void {
        if (this.efFired) return;
        this.efFired = true;
        _root["标记"](_root["探测"]("[CLS] onEnterFrame", this));
    }
}
