/** 子能力目录：成长仍归父技能，目录只声明稳定身份与既有等级前置。 */
class org.flashNight.arki.skill.SkillFeatureRegistry {
    private static var definitions:Array;
    private static var byId:Object;
    private static function initialize():Void {
        if (definitions != undefined) return;
        definitions = [
            {id:"impact_chain.half_reload",skillKey:"冲击连携",minLevel:1,label:"半换弹",description:"双枪异枪组合允许单手空弹提前装填；保留另一手未用完的弹药。"},
            {id:"impact_chain.pistol_power",skillKey:"冲击连携",minLevel:1,label:"主手短枪火力",description:"保留主手短枪随父技能等级增长的火力加成。"},
            {id:"impact_chain.offhand_impact",skillKey:"冲击连携",minLevel:1,label:"混搭冲击",description:"强化副手短枪和霰弹长枪的冲击。"},
            {id:"impact_chain.subweapon_impact",skillKey:"冲击连携",minLevel:1,label:"副武器冲击",description:"强化长枪副武器的冲击。"},
            {id:"impact_chain.subweapon_power",skillKey:"冲击连携",minLevel:1,label:"副武器火力转化",description:"随父技能等级，将装备枪械威力加成折算为副武器固定威力。"},
            {id:"impact_chain.ghost_loading",skillKey:"冲击连携",minLevel:1,label:"幽灵装填",description:"支持该机制的枪械可付费补装幽灵弹；关闭后剩余付费幽灵弹退回原弹种余额。"},
            {id:"impact_chain.shotgun_impact",skillKey:"冲击连携",minLevel:1,label:"霰弹额外冲击",description:"保留霰弹枪额外的冲击加成。"},
            {id:"impact_chain.shotgun_subweapon_power",skillKey:"冲击连携",minLevel:1,label:"霰弹副武器火力",description:"强化霰弹枪所搭载副武器的伤害。"},
            {id:"sword.wave",skillKey:"剑气释放",minLevel:1,label:"剑气释放",description:"单刀等兵器的下前攻击可派生剑气。"},
            {id:"sword.double_wave",skillKey:"剑气释放",minLevel:1,label:"双剑气",description:"双刀的下前攻击可派生双剑气。"},
            {id:"sword.sand",skillKey:"剑气释放",minLevel:1,label:"飞沙走石",description:"长柄等兵器的下前攻击可派生飞沙走石。"},
            {id:"sword.shadow",skillKey:"剑气释放",minLevel:1,label:"疾影剑气",description:"疾影兵器的下前攻击可派生疾影剑气。"}
        ];
        byId = {};
        for (var i:Number=0;i<definitions.length;i++) byId[definitions[i].id]=definitions[i];
    }
    public static function all():Array { initialize(); return definitions; }
    public static function get(id:String):Object { initialize(); return byId[id]; }
}
