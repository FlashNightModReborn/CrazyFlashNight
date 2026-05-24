/*
 * DropLuckRoller —— 掉落概率判定的统一入口
 *
 * 把三件原本散在各 caller 里的事情聚合到一处：
 *   1. 名义概率 percent → fraction 归一化（item.概率 在 XML 里写的是 0..100）
 *   2. 逆向被动 Magic-Find 类乘数（每级 +5%，与 PRD 正交叠加）
 *   3. 调用 PRD 引擎做"伪随机分布"判定（命中清零、未中累计；状态由 SaveManager
 *      经 _root.killStats.dropPRD 持久化）
 *
 * 当前接入点
 * ---------
 *   - 敌人掉落：UnitUtil.getUnitTypeKey(unit) 作 prdKeyPrefix
 *   - 资源箱（物品栏式 row*col 资源箱）："资源箱|" + presetName 作 prdKeyPrefix
 *
 * 备忘：通关奖励暂未接入
 * --------------------
 * 关卡通关奖励 (_root.奖励物品界面.生成关卡随机奖励品) 当前住在
 *   flashswf/UI/奖励物品界面.swf
 * 内，rolling 仍走 _root.成功率(AcquisitionProbability)，没有 PRD/逆向待遇。
 * 此 UI 计划随 launcher web overlay 迁移到 web 端，届时连同 rolling 一并改成
 *   DropLuckRoller.rollDrop("关卡|" + _root.当前关卡名, item)
 * key 前缀建议 "关卡|"，与现有 "兵种 typeKey" / "资源箱|presetName" 命名空间隔离。
 *
 * 设计原则
 * --------
 *   - 引擎层 (PseudoRandomDistribution) 不知道任何业务概念
 *   - 本类 (DropLuckRoller) 知道"逆向被动"、"item.概率 是 percent"等业务约定
 *   - 调用方只关心"给我一个 prdKey 前缀和 item，告诉我中没中"
 *   - 未来如果出现 Magic-Find 装备 / 幸运 buff / 关卡难度修正等多源乘数，
 *     只需扩 getLuckBonus()，所有 caller 自动受益
 */
class org.flashNight.arki.item.DropLuckRoller {

    /*
     * 当前逆向被动给出的掉落率乘数附加值（不含底数 1）。
     * 满级 10 级返回 0.5（即 +50%）。技能未启用 / 未学时返回 0。
     */
    public static function getLuckBonus():Number {
        var skill:Object = _root.主角被动技能.逆向;
        if (skill && skill.启用) {
            return skill.等级 * 0.05;
        }
        return 0;
    }

    /*
     * 按 PRD + 逆向乘数判定 item 是否掉出。
     *
     * @param prdKeyPrefix  PRD 计数表键前缀；本方法会拼上 "|" + item.名字
     *                      作为最终 key（兵种/箱子/关卡之间不会撞键）
     * @param item          掉落配置对象，要求带 .名字 与 .概率（percent 0..100）
     *                      .概率 缺省/NaN 时视为 100% 必中（不消费 PRD 计数）
     * @return              本次是否命中
     */
    public static function rollDrop(prdKeyPrefix:String, item:Object):Boolean {
        var nominalPercent:Number = Number(item.概率);
        // NaN/undefined → 视为 100% 必中，不走 PRD（与原 isNaN 短路语义等价）
        if (isNaN(nominalPercent)) return true;

        var effectiveP:Number = nominalPercent * 0.01 * (1 + getLuckBonus());
        var prdKey:String = prdKeyPrefix + "|" + item.名字;
        return _root.dropPRDEngine.roll(prdKey, effectiveP);
    }
}
