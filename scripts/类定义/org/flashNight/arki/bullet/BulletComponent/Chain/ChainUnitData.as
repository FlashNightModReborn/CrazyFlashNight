// ChainUnitData —— 联弹单元体数据对象（P5 class 化）
//
// 取代帧脚本中的 {mc,x,y,rot,...} 字面量：非 dynamic 类，字段静态声明，
// 经类型引用的字段名拼写错误在编译期报错（运行时哈希访问，性能中性）。
//
// 实例经 ChainUnitManager.acquireUnitData / releaseUnitData 自由表池化复用，
// 跨生命周期、跨联弹类型流转——生成端（联弹系统.生成单元体）必须复位
// 业务字段与渲染影子字段（v=-1 / wr=undefined），拖尾初始化额外复位 tLen/tHead。
class org.flashNight.arki.bullet.BulletComponent.Chain.ChainUnitData {

    // ---------- 通用（全部联弹类型） ----------
    // 池化的视觉 MC（共享层子剪辑）；回收时置 null 不持有已死引用
    public var mc:MovieClip;
    // 子弹本地坐标
    public var x:Number;
    public var y:Number;
    // 散射角（横向/纵向/滑翔/爆炸终身不变；拖尾逐帧收束改写）
    public var rot:Number;
    // rot 的三角函数缓存（生成时一次求值；拖尾更新改 rot 时跟写，
    // 渲染组镜像兜底分支与纵向 X 推进消费）
    public var sin:Number;
    public var cos:Number;

    // ---------- 渲染影子（差量下发用；池化复用必须强制复位） ----------
    // 显示状态版本（对齐 ChainGroup.rVer；-1 = 强制首帧全量写）
    public var v:Number;
    // 已写显示角（undefined = 强制首帧写 _rotation）
    public var wr:Number;

    // ---------- 横向拖尾扩展 ----------
    public var initRot:Number;
    public var age:Number;
    public var phaseJit:Number;
    public var centerX:Number;
    public var centerY:Number;
    public var oscPhase0:Number;
    public var convergeT:Number;
    // 拖尾环形缓冲（8 槽，存全局 {x,y,zn}；槽对象跨生命周期复用）
    public var trail:Array;
    public var tLen:Number;
    public var tHead:Number;

    public function ChainUnitData() {
    }
}
