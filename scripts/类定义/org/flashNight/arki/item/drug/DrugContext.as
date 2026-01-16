/**
 * DrugContext - 药剂使用上下文
 *
 * 封装药剂使用时的所有相关信息，传递给各个效果词条。
 * 提供炼金加成计算等通用功能。
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.arki.item.drug.DrugContext {

    /** 使用药剂的目标单位（通常是玩家控制的角色） */
    public var target:Object;

    /** 炼金技能等级（0表示无炼金技能） */
    public var alchemyLevel:Number;

    /** 原始药剂数据（itemData.data） */
    public var drugData:Object;

    /** 物品名称 */
    public var itemName:String;

    /** 完整物品数据 */
    public var itemData:Object;

    /**
     * 构造函数
     */
    public function DrugContext() {
        this.alchemyLevel = 0;
    }

    /**
     * 从当前游戏状态初始化上下文
     *
     * @param itemName 物品名称
     * @return DrugContext 初始化后的上下文实例
     */
    public static function create(itemName:String):DrugContext {
        var ctx:DrugContext = new DrugContext();
        ctx.itemName = itemName;

        // 获取目标（玩家控制的角色）
        ctx.target = _root.gameworld[_root.控制目标];

        // 获取炼金等级
        if (_root.主角被动技能.炼金 && _root.主角被动技能.炼金.启用) {
            ctx.alchemyLevel = _root.主角被动技能.炼金.等级;
        } else {
            ctx.alchemyLevel = 0;
        }

        // 获取物品数据
        ctx.itemData = _root.getItemData(itemName);
        ctx.drugData = ctx.itemData ? ctx.itemData.data : null;

        return ctx;
    }

    /**
     * 检查上下文是否有效
     *
     * @return Boolean 上下文是否可用于执行效果
     */
    public function isValid():Boolean {
        return this.target != null &&
               this.target.hp > 0 &&
               this.drugData != null;
    }

    // ========================================
    // 炼金加成计算工具方法
    // ========================================

    /**
     * 计算HP恢复值（含炼金加成）
     * 公式: baseValue + min(floor(baseValue * alchemyLevel * 0.05), 500)
     *
     * @param baseValue 基础HP恢复值
     * @return Number 加成后的HP恢复值
     */
    public function calcHPWithAlchemy(baseValue:Number):Number {
        if (isNaN(baseValue) || baseValue == 0) return 0;
        var bonus:Number = Math.min(Math.floor(baseValue * this.alchemyLevel * 0.05), 500);
        return baseValue + bonus;
    }

    /**
     * 计算MP恢复值（含炼金加成）
     * 公式: baseValue + min(ceil(baseValue * alchemyLevel * 0.1), 1000)
     *
     * @param baseValue 基础MP恢复值
     * @return Number 加成后的MP恢复值
     */
    public function calcMPWithAlchemy(baseValue:Number):Number {
        if (isNaN(baseValue) || baseValue == 0) return 0;
        var bonus:Number = Math.min(Math.ceil(baseValue * this.alchemyLevel * 0.1), 1000);
        return baseValue + bonus;
    }

    /**
     * 计算淬毒值（含炼金加成）
     * 公式: baseValue + min(floor(baseValue * alchemyLevel * 0.07), 2000)
     *
     * @param baseValue 基础淬毒值
     * @return Number 加成后的淬毒值
     */
    public function calcPoisonWithAlchemy(baseValue:Number):Number {
        if (isNaN(baseValue) || baseValue == 0) return 0;
        var bonus:Number = Math.min(Math.floor(baseValue * this.alchemyLevel * 0.07), 2000);
        return baseValue + bonus;
    }

    /**
     * 计算净化值（含炼金加成）
     * 公式: baseValue + min(floor(5 * alchemyLevel), 50)
     *
     * @param baseValue 基础净化值
     * @return Number 加成后的净化值
     */
    public function calcPurifyWithAlchemy(baseValue:Number):Number {
        if (isNaN(baseValue)) baseValue = 0;
        var bonus:Number = Math.min(Math.floor(5 * this.alchemyLevel), 50);
        return baseValue + bonus;
    }

    /**
     * 计算HP满血上限（含炼金加成）
     * 公式: hp满血值 * (1 + alchemyLevel * 0.03)
     *
     * @return Number 加成后的HP上限
     */
    public function getMaxHPWithAlchemy():Number {
        var baseMax:Number = this.target.hp满血值;
        return Math.ceil(baseMax * (1 + this.alchemyLevel * 0.03));
    }

    /**
     * 通用加成计算
     *
     * @param baseValue 基础值
     * @param factor 加成系数（如0.05表示5%每级）
     * @param cap 加成上限
     * @return Number 加成后的值
     */
    public function calcWithAlchemy(baseValue:Number, factor:Number, cap:Number):Number {
        if (isNaN(baseValue) || baseValue == 0) return 0;
        var bonus:Number = Math.floor(baseValue * this.alchemyLevel * factor);
        if (!isNaN(cap) && cap > 0) {
            bonus = Math.min(bonus, cap);
        }
        return baseValue + bonus;
    }
}
