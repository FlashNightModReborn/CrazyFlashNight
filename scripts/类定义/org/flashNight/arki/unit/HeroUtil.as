// 文件路径：org/flashNight/arki/unit/HeroUtil.as
import org.flashNight.gesh.xml.LoadXml.HeroTitlesLoader;

/**
 * 主角工具类
 * 提供主角相关的通用方法，包括称号管理等
 */
class org.flashNight.arki.unit.HeroUtil {

    /** 默认称号（降级使用） */
    private static var DEFAULT_TITLE_FALLBACK:String = "菜鸟";

    /**
     * 称号晋升表（降级使用）
     * 每个阶段定义了：杀敌数门槛、称号名称
     * 数组按杀敌数从高到低排序，方便查找
     */
    private static var TITLE_RANKS_FALLBACK:Array = [
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

    /** 从XML加载的默认称号 */
    public static var DEFAULT_TITLE:String = null;

    /** 从XML加载的称号晋升表 */
    private static var TITLE_RANKS:Array = null;

    /** 配置加载状态标记 */
    private static var configLoaded:Boolean = false;

    /**
     * 加载主角配置（从XML）
     * 应在游戏初始化时调用
     * @param onSuccess 加载成功回调
     * @param onError 加载失败回调
     */
    public static function loadHeroConfig(onSuccess:Function, onError:Function):Void {
        trace("[HeroUtil] 开始加载主角称号配置...");

        var loader:HeroTitlesLoader = HeroTitlesLoader.getInstance();

        loader.loadHeroTitles(
            function(data:Object):Void {
                trace("[HeroUtil] 主角称号配置加载成功！");

                // 解析默认称号
                if (data.default_title != undefined) {
                    DEFAULT_TITLE = data.default_title;
                    trace("[HeroUtil] 默认称号设置为: " + DEFAULT_TITLE);
                } else {
                    DEFAULT_TITLE = DEFAULT_TITLE_FALLBACK;
                    trace("[HeroUtil] 警告：未找到default_title，使用降级默认值: " + DEFAULT_TITLE);
                }

                // 解析称号晋升表
                if (data.title_ranks != undefined && data.title_ranks.rank != undefined) {
                    var ranksData = data.title_ranks.rank;

                    // 确保是数组
                    if (!(ranksData instanceof Array)) {
                        ranksData = [ranksData];
                    }

                    TITLE_RANKS = [];
                    for (var i:Number = 0; i < ranksData.length; i++) {
                        var rankNode = ranksData[i];
                        TITLE_RANKS.push({
                            kills: Number(rankNode.kills),
                            title: String(rankNode.title)
                        });
                    }

                    trace("[HeroUtil] 成功加载 " + TITLE_RANKS.length + " 个称号等级");
                } else {
                    TITLE_RANKS = TITLE_RANKS_FALLBACK;
                    trace("[HeroUtil] 警告：未找到title_ranks，使用降级默认值");
                }

                configLoaded = true;

                if (onSuccess != null) {
                    onSuccess();
                }
            },
            function():Void {
                trace("[HeroUtil] 主角称号配置加载失败！使用降级默认值");
                DEFAULT_TITLE = DEFAULT_TITLE_FALLBACK;
                TITLE_RANKS = TITLE_RANKS_FALLBACK;
                configLoaded = true;

                if (onError != null) {
                    onError();
                }
            }
        );
    }

    /**
     * 根据杀敌数获取对应称号
     * @param killCount 杀敌数
     * @return String 称号名称
     */
    private static function getTitleByKillCount(killCount:Number):String {
        // 确保使用正确的数据源（优先XML，否则降级）
        var ranks:Array = TITLE_RANKS != null ? TITLE_RANKS : TITLE_RANKS_FALLBACK;
        var defaultTitle:String = DEFAULT_TITLE != null ? DEFAULT_TITLE : DEFAULT_TITLE_FALLBACK;

        // 遍历称号表，找到第一个满足条件的称号
        for (var i:Number = 0; i < ranks.length; i++) {
            var rank:Object = ranks[i];
            if (killCount >= rank.kills) {
                return rank.title;
            }
        }

        // 兜底返回默认称号
        return defaultTitle;
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
        return DEFAULT_TITLE != null ? DEFAULT_TITLE : DEFAULT_TITLE_FALLBACK;
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
        var defaultTitle:String = DEFAULT_TITLE != null ? DEFAULT_TITLE : DEFAULT_TITLE_FALLBACK;
        if (title != undefined && title != "") {
            _root.玩家称号 = title;
        } else {
            _root.玩家称号 = defaultTitle;
        }
    }

    /**
     * 重置主角称号为默认值
     */
    public static function resetHeroTitle():Void {
        var defaultTitle:String = DEFAULT_TITLE != null ? DEFAULT_TITLE : DEFAULT_TITLE_FALLBACK;
        _root.玩家称号 = defaultTitle;
    }

    /**
     * 检查主角是否使用默认称号
     * @return Boolean true表示使用默认称号
     */
    public static function isUsingDefaultTitle():Boolean {
        var defaultTitle:String = DEFAULT_TITLE != null ? DEFAULT_TITLE : DEFAULT_TITLE_FALLBACK;
        var currentTitle:String = getHeroTitle();
        return currentTitle == defaultTitle;
    }

    /**
     * 获取下一个称号的信息
     * @return Object 包含下一称号信息：{title:String, kills:Number, current:Number, progress:Number}
     *         如果已是最高称号，返回null
     */
    public static function getNextTitleInfo():Object {
        var ranks:Array = TITLE_RANKS != null ? TITLE_RANKS : TITLE_RANKS_FALLBACK;

        if (_root.killStats == undefined || _root.killStats.total == undefined) {
            return {
                title: ranks[ranks.length - 2].title,
                kills: ranks[ranks.length - 2].kills,
                current: 0,
                progress: 0
            };
        }

        var killCount:Number = Number(_root.killStats.total);

        // 查找当前称号和下一个称号
        for (var i:Number = 0; i < ranks.length; i++) {
            var rank:Object = ranks[i];
            if (killCount >= rank.kills) {
                // 找到当前称号，检查是否有更高级的称号
                if (i > 0) {
                    var nextRank:Object = ranks[i - 1];
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
        return TITLE_RANKS != null ? TITLE_RANKS : TITLE_RANKS_FALLBACK;
    }
}
