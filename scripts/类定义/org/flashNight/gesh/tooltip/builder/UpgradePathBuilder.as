import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.equipment.TierSystem;
import org.flashNight.gesh.tooltip.TooltipFormatter;
import org.flashNight.gesh.tooltip.TooltipConstants;
import org.flashNight.gesh.tooltip.TooltipBridge;

/**
 * UpgradePathBuilder - 装备升阶路线构建器
 *
 * 装备 tooltip 的"升阶路线"段落构建。三段视图：
 *   1. 升自：装备作为 crafting 配方产物时的来源（直接前驱，1 步）
 *   2. 可升：装备作为 crafting 配方输入时的所有产物名（直接后继，1 步）
 *   3. 可进阶：装备 schema 上支持的 Tier 系统选项（二/三/四/墨冰/狱火），
 *             配合 item.value.tier 标注当前已涂层
 *
 * 设计原则（schema 视图，非 runtime）：
 *   - 只显示"装备能否走这条路线"，不显示"现在能不能走"
 *   - 材料数量、二→三递进约束等 runtime 状态归强化 UI 自身判定
 *   - 多步链不在 tooltip 渲染——玩家悬停下一阶物品 tooltip 自然探索
 *
 * 三段全空时返回空数组，不输出标题区块。
 */
class org.flashNight.gesh.tooltip.builder.UpgradePathBuilder {

    /**
     * 构建装备升阶路线 HTML 片段数组。
     * @param item 物品数据对象（含 name / synthesis 字段）
     * @param baseItem 装备实例（可选；缺失时跳过 tier 段，仅渲染 crafting 段）
     * @return Array HTML 文本片段；三段全空时返回空数组
     */
    public static function build(item:Object, baseItem:BaseItem):Array {
        var result:Array = [];

        // 1) 升自：item 作为产物的配方
        var fromRecipe:Object = TooltipBridge.getSynthesisData(item.synthesis);
        var hasFrom:Boolean = (fromRecipe != null && fromRecipe.materials != null);

        // 2) 可升：item 作为输入的所有产物名
        var toProducts:Array = TooltipBridge.getRecipesUsing(item.name);
        var hasTo:Boolean = (toProducts && toProducts.length > 0);

        // 3) 可进阶：用 byName 版本走纯 schema 判定，不依赖 BaseItem 实例
        //    （商店预览 / Web 面板 / 库存 grid hover 等场景 baseItem=null 也要正常出 tier 段）
        //    available=false 表示装备 schema 不支持该 tier，过滤掉避免噪音
        var supportedTiers:Array = [];
        var rawTierOpts:Array = TierSystem.getAllTierOptionsByName(item.name);
        if (rawTierOpts) {
            for (var i:Number = 0; i < rawTierOpts.length; i++) {
                if (rawTierOpts[i].available) supportedTiers.push(rawTierOpts[i]);
            }
        }
        var hasTier:Boolean = (supportedTiers.length > 0);

        if (!hasFrom && !hasTo && !hasTier) return result;

        // 区块标题
        result.push(TooltipFormatter.br());
        result.push(TooltipFormatter.color(TooltipConstants.LBL_UPGRADE_PATH, TooltipConstants.COL_INFO));
        result.push(TooltipFormatter.br());

        if (hasFrom) renderFrom(result, fromRecipe);
        if (hasTo) renderTo(result, toProducts);
        if (hasTier) renderTier(result, supportedTiers, baseItem);

        return result;
    }

    /**
     * 渲染"升自"段：子弹列表风格，每个材料独占一行。
     * 复用 ItemUtil.getRequirementFromTask 的材料解析逻辑，
     * 与 buildSynthesisMaterials 行为一致（数量 / 强化度 / 装备名三种模式）。
     *
     * 格式：
     *   升自：
     *     • 诛神短剑 x1
     *     • 远古碎片 x60
     *     • 强化石 x4000
     */
    private static function renderFrom(result:Array, fromRecipe:Object):Void {
        var requirements:Array = ItemUtil.getRequirementFromTask(fromRecipe.materials);
        if (!requirements || requirements.length == 0) return;

        // 标签行
        result.push("  ");
        result.push(TooltipFormatter.color(TooltipConstants.TIP_UPGRADE_FROM, TooltipConstants.COL_CRAFT));
        result.push(TooltipFormatter.br());

        for (var i:Number = 0; i < requirements.length; i++) {
            var req:Object = requirements[i];
            if (!req || !req.name) continue;
            var itemData:Object = ItemUtil.getItemData(req.name);
            var displayName:String = (itemData && itemData.displayname) ? itemData.displayname : req.name;
            result.push("  • ", displayName);
            if (req.isQuantity) {
                result.push(" x", req.value);
            } else if (ItemUtil.isEquipment(req.name)) {
                result.push(" +", req.value);
            } else {
                result.push("：", req.value);
            }
            result.push(TooltipFormatter.br());
        }
    }

    /**
     * 渲染"可升"段：子弹列表风格，每个产物独占一行。
     * 数量 > UPGRADE_MAX_TO_PRODUCTS 时显示前 N + 末尾"... 等共 M"独立一行。
     *
     * 格式：
     *   可升：
     *     • "贯空天盖"上衣
     *     • 黑犀胸甲
     *     • 奇美拉胸甲
     *     • ... 等共 5
     */
    private static function renderTo(result:Array, toProducts:Array):Void {
        // 标签行
        result.push("  ");
        result.push(TooltipFormatter.color(TooltipConstants.TIP_UPGRADE_TO, TooltipConstants.COL_CRAFT));
        result.push(TooltipFormatter.br());

        var maxN:Number = TooltipConstants.UPGRADE_MAX_TO_PRODUCTS;
        var total:Number = toProducts.length;
        var shown:Number = Math.min(total, maxN);
        for (var i:Number = 0; i < shown; i++) {
            var prodName:String = toProducts[i];
            var itemData:Object = ItemUtil.getItemData(prodName);
            var displayName:String = (itemData && itemData.displayname) ? itemData.displayname : prodName;
            result.push("  • ", displayName, TooltipFormatter.br());
        }
        if (total > maxN) {
            result.push("  • ... ", TooltipConstants.TIP_ETC, "共", total, TooltipFormatter.br());
        }
    }

    /**
     * 渲染"可进阶"段：参考 ModsBlockBuilder 的子弹列表样式，每个 tier 独占一行，
     * 避免多 tier + 材料名拼接成长串导致视觉堆积。
     *
     * 格式：
     *   可进阶：
     *     • 二阶 [二阶复合防御组件]
     *     • 三阶 [三阶复合防御组件]
     *     • 冷凝「当前」 [铁枪冷凝核心]
     *
     * - 标签行用 COL_ENHANCE 淡绿（与现有 schema 视图色调一致）
     * - 材料名用 COL_INFO 金色方括号（对齐 ModsBlockBuilder 的 tagValue 风格，便于扫读）
     * - 已涂 tier 在名后追加 TIP_TIER_CURRENT 标注（「当前」中文方括号，避免 HTML tag 吞）
     */
    private static function renderTier(result:Array, supportedTiers:Array, baseItem:BaseItem):Void {
        // 标签行（无子项就不渲染，由调用方 hasTier 判断保证）
        result.push("  ");
        result.push(TooltipFormatter.color(TooltipConstants.TIP_TIER_OPTIONS, TooltipConstants.COL_ENHANCE));
        result.push(TooltipFormatter.br());

        var currentTier:String = (baseItem && baseItem.value) ? baseItem.value.tier : null;
        for (var i:Number = 0; i < supportedTiers.length; i++) {
            var opt:Object = supportedTiers[i];
            result.push("  • ", opt.name);
            if (currentTier && opt.name === currentTier) {
                result.push(TooltipConstants.TIP_TIER_CURRENT);
            }
            if (opt.material) {
                result.push(" ");
                result.push(TooltipFormatter.color("[" + opt.material + "]", TooltipConstants.COL_INFO));
            }
            result.push(TooltipFormatter.br());
        }
    }
}
