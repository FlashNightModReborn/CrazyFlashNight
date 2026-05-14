// =======================================================
// wa90变形款 · 装备生命周期函数（自管理版）
// =======================================================
// 双形态自动步枪：默认形态 ⇄ 变形形态（武器变形键切换）
//   - 帧 1～animDuration：形态过渡动画
//   - 枪口位置切换：gun.枪口位置 → 枪口位置0 / 枪口位置1
//   - 弹匣帧 = target.长枪.value.shot + 1（每帧派生，幂等）
//   - 激光部件可见性 = (攻击模式 == 长枪)
// 状态持久化到 target[ref.装备类型].value.wa90变形
// =======================================================

_root.装备生命周期函数.wa90变形款初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    param = param || {};

    /* ---------- 1. 配置参数 ---------- */
    ref.animDuration = param.animationDuration || 15;
    ref.transformInterval = param.transformInterval || 1000;

    /* ---------- 2. 从 item.value 恢复形态状态 ---------- */
    var wv:Object = target[ref.装备类型].value;
    var _rv = _root.装备生命周期函数.读取持久值;

    ref.wa90变形 = _rv(wv, "wa90变形", false);
    ref.weaponValue = wv;
    wv.wa90变形 = ref.wa90变形;
    target.wa90变形 = ref.wa90变形;

    // 初始帧定位到对应形态终态，避免重播变形动画
    ref.currentFrame = ref.wa90变形 ? ref.animDuration : 1;

    /* ---------- 3. placement 触发首次视觉同步 ---------- */
    PlacementVisual.hookVisualUpdate(target, "长枪_引用", ref, _root.装备生命周期函数.wa90变形款视觉更新);
};

_root.装备生命周期函数.wa90变形款周期 = function(ref:Object, param:Object) {
    if (!EquipmentTick.open(ref)) return;

    var target:MovieClip = ref.自机;

    /* ---------- 1. 变形键触发（长枪模式 + 冷却节流） ---------- */
    if (target.攻击模式 == "长枪" && _root.按键输入检测(target, _root.武器变形键)) {
        _root.更新并执行时间间隔动作(
            ref,
            "wa90变形切换",
            _root.装备生命周期函数.wa90变形款切换形态,
            ref.transformInterval,
            false,
            ref
        );
    }

    /* ---------- 2. 推帧：长枪 + 变形 → 推至 animDuration；否则回 1 ---------- */
    var shouldExpand:Boolean = (target.攻击模式 == "长枪" && ref.wa90变形);
    if (shouldExpand) {
        if (ref.currentFrame < ref.animDuration) ref.currentFrame++;
    } else {
        if (ref.currentFrame > 1) ref.currentFrame--;
    }

    _root.装备生命周期函数.wa90变形款视觉更新(ref);
};

/**
 * 形态切换 - 翻转 wa90变形 并持久化
 */
_root.装备生命周期函数.wa90变形款切换形态 = function(ref:Object) {
    ref.wa90变形 = !ref.wa90变形;
    ref.weaponValue.wa90变形 = ref.wa90变形;
    ref.自机.wa90变形 = ref.wa90变形;
};

/**
 * 视觉更新 - 纯写 mc 属性（幂等）
 */
_root.装备生命周期函数.wa90变形款视觉更新 = function(ref:Object) {
    var target:MovieClip = ref.自机;
    var gun:MovieClip = target.长枪_引用;
    if (!gun || !gun.动画) return;

    // 形态过渡动画
    gun.动画.gotoAndStop(ref.currentFrame);

    // 枪口位置切换：影响子弹射出点（Six12 风格）
    gun.枪口位置 = ref.wa90变形 ? gun.枪口位置1 : gun.枪口位置0;

    // 激光部件可见性（兼容旧 模板组件切换 行为；部件缺失则为 no-op）
    gun.动画.激光._visible = (target.攻击模式 == "长枪");

    // 弹匣帧 = 剩余弹药 + 1
    gun.动画.弹匣.gotoAndStop(target.长枪.value.shot + 1);
};
