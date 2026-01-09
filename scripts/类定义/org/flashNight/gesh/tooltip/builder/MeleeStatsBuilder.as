/**
 * MeleeStatsBuilder - 近战武器属性构建器
 *
 * 职责：
 * - 构建近战武器专属属性（锋利度、判定数等）
 * - 处理刀类武器的特殊显示逻辑
 * - 通过加载 "刀-XXX" 素材检测刀口数量（避免图标中的脏数据）
 *
 * 设计原则：
 * - 无副作用：仅通过 push 修改传入的 result 数组
 * - 使用 TooltipFormatter 统一格式化
 * - 刀口数量缓存，首次检测后 O(1) 读取
 */
import org.flashNight.arki.item.BaseItem;
import org.flashNight.gesh.tooltip.TooltipFormatter;

class org.flashNight.gesh.tooltip.builder.MeleeStatsBuilder {

    /** 刀口数量缓存：cacheKey(dressup/icon) -> count */
    private static var bladeCountCache:Object = {};

    /** 临时容器深度 */
    private static var TEMP_DEPTH:Number = 99999;

    /** 最大刀口数量 */
    private static var MAX_BLADE_POINTS:Number = 6;

    /** 最大遍历深度 */
    private static var MAX_SEARCH_DEPTH:Number = 4;

    /**
     * 构建近战武器属性块
     *
     * @param result:Array 输出缓冲区（就地修改）
     * @param baseItem:BaseItem 物品实例
     * @param item:Object 物品数据
     * @param data:Object 合并后的装备数据
     * @param equipData:Object 强化/配件数据（可选）
     * @return Void（直接修改 result）
     */
    public static function build(result:Array, baseItem:BaseItem, item:Object, data:Object, equipData:Object):Void {
        // 近战武器的锋利度显示
        TooltipFormatter.upgradeLine(result, data, equipData, "power", "锋利度", null);

        // 检测并显示刀口数量（判定数）
        // 优先使用 data.dressup（刀-xxx）作为权威来源，避免 icon 里存在“脏判定/多套判定”导致误判
        // 若 dressup 缺失或 attach 失败，再回退使用 iconName 推导的 "刀-" + iconName
        var dressupName:String = (data && data.dressup) ? String(data.dressup) : null;
        var bladeCount:Number = getBladeCount(dressupName, item.icon);
        if (bladeCount > 0) {
            result.push("判定数：", String(bladeCount), TooltipFormatter.br());
        }
    }

    /**
     * 获取刀口数量（带缓存）
     *
     * @param dressupName:String 刀装扮链接名（如 "刀-热能武士刀"），可选
     * @param iconName:String 图标名称（不含"图标-"前缀），可选
     * @return Number 刀口数量，0 表示未检测到
     */
    public static function getBladeCount(dressupName:String, iconName:String):Number {
        if (!dressupName && !iconName) return 0;

        var cacheKey:String = dressupName ? ("dressup:" + dressupName) : ("icon:" + iconName);
        // 缓存命中
        if (bladeCountCache[cacheKey] !== undefined) {
            return bladeCountCache[cacheKey];
        }

        // 首次检测
        var count:Number = 0;
        if (dressupName) {
            count = detectBladePointsByLinkage(dressupName);
        }
        if (count <= 0 && iconName) {
            count = detectBladePointsByLinkage(BLADE_PREFIX + iconName);
        }
        bladeCountCache[cacheKey] = count;
        return count;
    }

    /** 刀素材前缀 */
    private static var BLADE_PREFIX:String = "刀-";

    /**
     * 检测武器的刀口数量
     *
     * 流程：
     * 1. 临时创建隐藏容器
     * 2. attachMovie 加载指定 linkage（优先 dressup，回退 "刀-" + iconName）
     * 3. 遍历显示列表子节点查找刀口位置
     * 4. 清理临时影片剪辑
     *
     * @param linkageName:String 库链接名（如 "刀-热能武士刀"）
     * @return Number 刀口数量
     */
    private static function detectBladePointsByLinkage(linkageName:String):Number {
        if (!linkageName) return 0;
        // 获取或创建临时容器
        var container:MovieClip = _root._tooltipTempContainer;
        if (!container) {
            container = _root.createEmptyMovieClip("_tooltipTempContainer", TEMP_DEPTH);
            container._visible = false;
        }

        // 防御：避免重复 attach 同名实例
        if (container.tempBlade) {
            container.tempBlade.removeMovieClip();
        }

        // 加载刀素材
        var tempBlade:MovieClip = container.attachMovie(linkageName, "tempBlade", container.getNextHighestDepth());

        if (!tempBlade) {
            return 0;
        }

        // 遍历查找刀口
        var count:Number = searchBladePoints(tempBlade, MAX_SEARCH_DEPTH);

        // 清理
        tempBlade.removeMovieClip();

        return count;
    }

    /**
     * 在 MovieClip 树中搜索刀口位置
     *
     * 只遍历显示列表子节点（child._parent == current）。
     * 若当前层已包含刀口位置，则计数作为候选；
     * 同时继续向下搜索并取最大值，避免素材内存在多套判定时误选较小的一套。
     *
     * @param clip:MovieClip 要搜索的 MovieClip
     * @param depth:Number 剩余搜索深度
     * @return Number 刀口数量
     */
    private static function searchBladePoints(clip:MovieClip, depth:Number):Number {
        if (!clip || depth <= 0) return 0;

        var best:Number = 0;
        // 特征判断：检查当前层是否有刀口位置1
        if (clip["刀口位置1"] != undefined) {
            best = countBladePointsSequential(clip);
            if (best >= MAX_BLADE_POINTS) {
                return best;
            }
        }

        // 遍历显示列表子节点
        for (var childName:String in clip) {
            var child = clip[childName];
            // 只处理 MovieClip 且是当前节点的直接子节点
            if (child instanceof MovieClip && child._parent == clip) {
                var count:Number = searchBladePoints(child, depth - 1);
                if (count > best) {
                    best = count;
                    if (best >= MAX_BLADE_POINTS) {
                        return best;
                    }
                }
            }
        }

        return best;
    }

    /**
     * 顺序计数刀口位置
     *
     * 利用"刀口不会跳号"的特性，从1开始顺序检查，
     * 遇到缺失立即停止。
     *
     * @param clip:MovieClip 包含刀口位置的 MovieClip
     * @return Number 刀口数量
     */
    private static function countBladePointsSequential(clip:MovieClip):Number {
        var count:Number = 0;

        for (var i:Number = 1; i <= MAX_BLADE_POINTS; i++) {
            var node = clip["刀口位置" + i];
            // 只检查节点是否存在，不检查 _x
            // 因为刀口位置可能是空的占位 MovieClip
            if (node != undefined) {
                count++;
            } else {
                break; // 顺序排布，遇到缺失即停止
            }
        }

        return count;
    }

    /**
     * 清除缓存（用于热更新场景）
     */
    public static function clearCache():Void {
        bladeCountCache = {};
    }
}
