/**
 * AIEnvironment — AI系统访问全局状态的唯一入口
 *
 * 所有 AI 文件通过此静态门面访问 _root / Stage / getTimer 等全局资源，
 * 便于 mock 替换和服务器迁移。全部 static 方法，零实例分配。
 */
class org.flashNight.arki.unit.UnitAI.AIEnvironment {

    // ═══════ 帧 / 时间 ═══════

    public static function getFrame():Number {
        return _root.帧计时器.当前帧数;
    }

    public static function getTimerMs():Number {
        return getTimer();
    }

    // ═══════ 地图边界 ═══════

    public static function getXmin():Number {
        return (_root.Xmin != undefined) ? _root.Xmin : 0;
    }

    public static function getXmax():Number {
        return (_root.Xmax != undefined) ? _root.Xmax : Stage.width;
    }

    public static function getYmin():Number {
        return (_root.Ymin != undefined) ? _root.Ymin : 0;
    }

    public static function getYmax():Number {
        return (_root.Ymax != undefined) ? _root.Ymax : Stage.height;
    }

    // ═══════ 控制标志 ═══════

    public static function isPaused():Boolean {
        return _root.暂停 === true;
    }

    public static function isFullAuto():Boolean {
        return _root.控制目标全自动 == true;
    }

    public static function getCommand():String {
        return _root.命令;
    }

    public static function getFocusTarget():String {
        return _root.集中攻击目标;
    }

    public static function isBloodyMode():Boolean {
        return _root.血腥开关 != false;
    }

    // ═══════ 调试 ═══════

    /** 全局调试标志（UnitAIData.stuckProbe / MecenaryBehavior 使用） */
    public static function isGlobalDebug():Boolean {
        return _root.调试模式 == true;
    }

    /** AI专用调试标志（WeaponEvaluator / MovementResolver / RetreatMovementStrategy 使用） */
    public static function isAIDebug():Boolean {
        return _root.AI调试模式 == true;
    }

    /** DecisionTrace 日志级别 (0=OFF / 1=BRIEF / 2=TOP3 / 3=FULL) */
    public static function getAILogLevel():Number {
        var lv:Number = _root.AI日志级别;
        return (isNaN(lv) || lv < 0) ? 0 : lv;
    }

    /** 服务器日志通道 */
    public static function log(msg:String):Void {
        _root.服务器.发布服务器消息(msg);
    }

    /** 游戏内消息广播 */
    public static function logBroadcast(sender:MovieClip, msg:String):Void {
        _root.发布消息(sender, msg);
    }

    // ═══════ 服务调用 ═══════

    public static function routeSkill(self:MovieClip, skillName:String):Void {
        _root.技能路由.技能标签跳转_旧(self, skillName);
    }

    public static function getPreBuffMarks():Object {
        return _root.技能函数.预战buff标记;
    }

    public static function useHealPack(unitName:String):Void {
        _root.佣兵使用血包(unitName);
    }

    public static function generatePersonality(seed:Number):Object {
        return _root.生成随机人格(seed);
    }

    public static function computeAIParams(personality:Object):Void {
        _root.计算AI参数(personality);
    }

    // ═══════ 世界查询 ═══════

    public static function resolveUnit(name:String):MovieClip {
        return _root.gameworld[name];
    }

    public static function getGameworld():MovieClip {
        return _root.gameworld;
    }

    public static function getCollisionLayer():MovieClip {
        return _root.collisionLayer;
    }

    public static function getPickupManager():Object {
        return _root.pickupItemManager;
    }

    public static function isAreaSafe():Boolean {
        return _root.gameworld.允许通行 == true;
    }

    /** 背包空位查询（EnemyBehavior 拾取用） */
    public static function getFirstBagVacancy():Number {
        return _root.物品栏.背包.getFirstVacancy();
    }
}
