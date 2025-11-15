// 文件路径：org/flashNight/arki/unit/HeroUtil.as
/**
 * 主角工具类
 * 提供主角相关的通用方法，包括称号管理等
 */
class org.flashNight.arki.unit.HeroUtil {

    /** 默认称号 */
    public static var DEFAULT_TITLE:String = "菜鸟";

    /**
     * 称号晋升表
     * 每个阶段定义了：杀敌数门槛、称号名称
     * 数组按杀敌数从高到低排序，方便查找
     */
    private static var TITLE_RANKS:Array = [
        {kills: 10000, title: "传奇佣兵"},      // 10000+ 杀敌
        {kills: 5000,  title: "战场死神"},      // 5000+ 杀敌
        {kills: 3000,  title: "杀戮机器"},      // 3000+ 杀敌
        {kills: 2000,  title: "精英杀手"},      // 2000+ 杀敌
        {kills: 1000,  title: "资深佣兵"},      // 1000+ 杀敌
        {kills: 500,   title: "老兵"},          // 500+ 杀敌
        {kills: 300,   title: "斗士"},          // 300+ 杀敌
        {kills: 150,   title: "战士"},          // 150+ 杀敌
        {kills: 50,    title: "新兵"},          // 50+ 杀敌
        {kills: 10,    title: "见习佣兵"},      // 10+ 杀敌
        {kills: 0,     title: "菜鸟"}           // 0+ 杀敌（默认）
    ];

    /**
     * 根据杀敌数获取对应称号
     * @param killCount 杀敌数
     * @return String 称号名称
     */
    private static function getTitleByKillCount(killCount:Number):String {
        // 遍历称号表，找到第一个满足条件的称号
        for (var i:Number = 0; i < TITLE_RANKS.length; i++) {
            var rank:Object = TITLE_RANKS[i];
            if (killCount >= rank.kills) {
                return rank.title;
            }
        }

        // 兜底返回默认称号
        return DEFAULT_TITLE;
    }

    /**
     * 获取主角称号
     * 优先级：装备称号 > 杀敌数称号 > 全局称号 > 默认称号
     * @return String 称号文本
     */
    public static function getHeroTitle():String {
        // 通过 TargetCacheManager 获取主角
        var hero:MovieClip = org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager.findHero();

        // 优先级1：从颈部装备获取称号（装备称号优先级最高）
        if (hero != null && hero.颈部装备数据 != undefined && hero.颈部装备数据.data != undefined) {
            var equipTitle:String = hero.颈部装备数据.data.title;
            if (equipTitle != undefined && equipTitle != "") {
                return equipTitle;
            }
        }

        // 优先级2：根据杀敌数自动计算称号
        if (_root.killStats != undefined && _root.killStats.total != undefined) {
            var killCount:Number = Number(_root.killStats.total);
            if (!isNaN(killCount) && killCount >= 0) {
                return getTitleByKillCount(killCount);
            }
        }

        // 优先级3：从全局变量获取称号
        if (_root.玩家称号 != undefined && _root.玩家称号 != "") {
            return _root.玩家称号;
        }

        // 优先级4：返回默认称号
        return DEFAULT_TITLE;
    }

    /**
     * 获取翻译后的主角称号
     * @return String 翻译后的称号文本
     */
    public static function getTranslatedHeroTitle():String {
        var title:String = getHeroTitle();

        // 如果存在翻译函数，使用翻译
        if (_root.获得翻译 != undefined) {
            return _root.获得翻译(title);
        }

        return title;
    }

    /**
     * 设置主角称号到全局变量
     * @param title 称号文本
     */
    public static function setGlobalHeroTitle(title:String):Void {
        if (title != undefined && title != "") {
            _root.玩家称号 = title;
        } else {
            _root.玩家称号 = DEFAULT_TITLE;
        }
    }

    /**
     * 重置主角称号为默认值
     */
    public static function resetHeroTitle():Void {
        _root.玩家称号 = DEFAULT_TITLE;
    }

    /**
     * 检查主角是否使用默认称号
     * @return Boolean true表示使用默认称号
     */
    public static function isUsingDefaultTitle():Boolean {
        var currentTitle:String = getHeroTitle();
        return currentTitle == DEFAULT_TITLE;
    }

    /**
     * 获取下一个称号的信息
     * @return Object 包含下一称号信息：{title:String, kills:Number, current:Number, progress:Number}
     *         如果已是最高称号，返回null
     */
    public static function getNextTitleInfo():Object {
        if (_root.killStats == undefined || _root.killStats.total == undefined) {
            return {
                title: TITLE_RANKS[TITLE_RANKS.length - 2].title,
                kills: TITLE_RANKS[TITLE_RANKS.length - 2].kills,
                current: 0,
                progress: 0
            };
        }

        var killCount:Number = Number(_root.killStats.total);

        // 查找当前称号和下一个称号
        for (var i:Number = 0; i < TITLE_RANKS.length; i++) {
            var rank:Object = TITLE_RANKS[i];
            if (killCount >= rank.kills) {
                // 找到当前称号，检查是否有更高级的称号
                if (i > 0) {
                    var nextRank:Object = TITLE_RANKS[i - 1];
                    var remaining:Number = nextRank.kills - killCount;
                    var progress:Number = (killCount - rank.kills) / (nextRank.kills - rank.kills) * 100;

                    return {
                        title: nextRank.title,
                        kills: nextRank.kills,
                        current: killCount,
                        remaining: remaining,
                        progress: Math.floor(progress)
                    };
                } else {
                    // 已经是最高称号
                    return null;
                }
            }
        }

        return null;
    }

    /**
     * 获取所有称号等级列表（用于UI显示）
     * @return Array 称号列表
     */
    public static function getAllTitleRanks():Array {
        return TITLE_RANKS;
    }
}
