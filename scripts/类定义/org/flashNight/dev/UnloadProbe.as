// 文件路径：org/flashNight/dev/UnloadProbe.as
//
// 用途：测 onUnload 类方法在 removeMovieClip / 父级 destroy 时的触发时机 + this 状态
// 配套 runner：scripts/TestLoader.as 的 T11 / T12 段落
// 配套文档：agentsDoc/as2-load-timing.md 第 2.5 节（stale-ref window 性能优化探索）
//
// 关键观察点：
//   1. onUnload 触发时 this._parent 是否仍存在？（决定能否在此调用 localToGlobal）
//   2. 父级被 removeMovieClip 时，class-bound 子级的 onUnload 是否级联触发？
//      → 决定 FLA timeline 切帧 destroy holder 时，能否捕获装扮 skin 的 destroy 事件

dynamic class org.flashNight.dev.UnloadProbe extends MovieClip {

    public function UnloadProbe() {
        // 构造不 trace，让 onUnload 独立显形
    }

    public function onUnload():Void {
        var p:Object = {x: 0, y: 0};
        this.localToGlobal(p);
        _root["标记"]("[CLS-onUnload] _name=" + this._name
            + " _parent=" + this._parent
            + " _x=" + this._x + " _y=" + this._y
            + " glob=(" + p.x + "," + p.y + ")");
    }
}
