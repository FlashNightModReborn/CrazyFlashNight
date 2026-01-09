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

    /** 刀口数量缓存：iconName -> count */
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
        var bladeCount:Number = getBladeCount(item.icon);
        if (bladeCount > 0) {
            result.push("判定数：", String(bladeCount), TooltipFormatter.br());
        }
    }

    /**
     * 获取刀口数量（带缓存）
     *
     * @param iconName:String 图标名称（不含"图标-"前缀）
     * @return Number 刀口数量，0 表示未检测到
     */
    public static function getBladeCount(iconName:String):Number {
        if (!iconName) return 0;

        // 缓存命中
        if (bladeCountCache[iconName] !== undefined) {
            return bladeCountCache[iconName];
        }

        // 首次检测
        var count:Number = detectBladePoints(iconName);
        bladeCountCache[iconName] = count;
        return count;
    }

    /** 刀素材前缀 */
    private static var BLADE_PREFIX:String = "刀-";

    /**
     * 检测武器的刀口数量
     *
     * 流程：
     * 1. 临时创建隐藏容器
     * 2. attachMovie 加载 "刀-XXX"（而非图标，因为图标素材可能包含脏数据）
     * 3. 遍历显示列表子节点查找刀口位置
     * 4. 清理临时影片剪辑
     *
     * @param iconName:String 图标名称（会转换为对应的刀素材名）
     * @return Number 刀口数量
     */
    private static function detectBladePoints(iconName:String):Number {
        // 获取或创建临时容器
        var container:MovieClip = _root._tooltipTempContainer;
        if (!container) {
            container = _root.createEmptyMovieClip("_tooltipTempContainer", TEMP_DEPTH);
            container._visible = false;
        }

        // 加载刀素材（而非图标，避免图标中的脏数据干扰）
        var linkageName:String = BLADE_PREFIX + iconName;
        var tempBlade:MovieClip = container.attachMovie(linkageName, "tempBlade", 1);

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
     * 只遍历显示列表子节点（child._parent == current），
     * 找到刀口位置1后立即计数并返回，避免无效遍历。
     *
     * @param clip:MovieClip 要搜索的 MovieClip
     * @param depth:Number 剩余搜索深度
     * @return Number 刀口数量
     */
    private static function searchBladePoints(clip:MovieClip, depth:Number):Number {
        if (!clip || depth <= 0) return 0;

        // 特征判断：检查当前层是否有刀口位置1
        if (clip["刀口位置1"] != undefined) {
            return countBladePointsSequential(clip);
        }

        // 遍历显示列表子节点
        for (var childName:String in clip) {
            var child = clip[childName];
            // 只处理 MovieClip 且是当前节点的直接子节点
            if (child instanceof MovieClip && child._parent == clip) {
                var count:Number = searchBladePoints(child, depth - 1);
                if (count > 0) {
                    return count; // 找到后立即返回
                }
            }
        }

        return 0;
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
