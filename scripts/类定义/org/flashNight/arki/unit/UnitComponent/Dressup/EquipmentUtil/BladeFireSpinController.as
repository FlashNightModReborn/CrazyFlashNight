/**
 * BladeFireSpinController - 加特林族连射计数 + 转速帧推进
 *
 * 抽离 4 个加特林族装备共有的 tick 逻辑：
 *   - fireCount 短路升降（射击时 spinUpAmount，未射击时 spinDownRate 衰减）
 *   - gunFrame 浮点帧推进（speed = fireCount * spinSpeedFactor），到顶取模回卷
 *   - isFiring 本帧消费后重置
 *
 * 实际收益武器（4 个直接 + 1 个 delegate）：
 *   M134 / XM556_Microgun / 僵尸割草机 / 混凝土切割机；XM556_H_Stinger 通过
 *   delegate _root.装备生命周期函数.XM556周期 自动跟上。
 *
 * 不纳入：
 *   - 杀戮风暴：滞回 spinStartThreshold/spinStopThreshold + [startFrame,endFrame] 区间
 *   - XM214-CageFrame：值归一化模型 (shotgunValue → spinFactor)
 *   - M134暴力版：AI 抡枪 trigger，无 tick 字段
 *   - XM556-OC-Overlord：展开/收拢 + 射击循环帧机制，无 fireCount
 *
 * 字段 contract（canonical，调用方 init 时种好）：
 *   ref.fireCount         Number  当前连射计数
 *   ref.maxSpinCount      Number  连射计数上限
 *   ref.spinUpAmount      Number  射击时累加
 *   ref.spinDownRate      Number  无射击时衰减
 *   ref.spinSpeedFactor   Number  fireCount → 帧速率系数
 *   ref.gunFrame          Number  当前动画帧（浮点）
 *   ref.isFiring          Boolean 本帧是否射击（消费后被本函数重置）
 *
 * 设计选择（方案 A）：
 *   - 不使用 cfg 索引（避免 AVM1 dynamic prop lookup 每帧亏损）
 *   - gunAnim 由调用方显式传入（4 个文件路径不一：长枪_引用.动画 / 引用本身）
 *   - tick 内对 gunAnim undefined 做防御（detached MC 安全）
 */
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.BladeFireSpinController {

    public static function tick(ref:Object, gunAnim:MovieClip):Void {
        // 1. 短路升降 fireCount
        (ref.isFiring && (ref.fireCount = Math.min(ref.fireCount + ref.spinUpAmount, ref.maxSpinCount))) ||
        (ref.fireCount = Math.max(0, ref.fireCount - ref.spinDownRate));

        // 2. 浮点帧推进 + 取模回卷
        if (ref.fireCount > 0) {
            ref.gunFrame += ref.fireCount * ref.spinSpeedFactor;
            if (gunAnim && ref.gunFrame > gunAnim._totalFrames) {
                ref.gunFrame = ((ref.gunFrame - 1) % gunAnim._totalFrames) + 1;
            }
        }

        // 3. 消费本帧射击标记
        ref.isFiring = false;
    }
}
