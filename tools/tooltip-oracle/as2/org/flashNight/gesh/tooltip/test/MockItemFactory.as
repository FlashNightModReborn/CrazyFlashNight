/**
 * MockItemFactory - 测试用物品 fixture 工厂
 *
 * 返回 {item, data, equipData} 三元组。
 * 所有 fixture 包含 level 字段（EquipmentStatsComposer L45 对所有类型调用 upgradeLine "level"）。
 */
class org.flashNight.gesh.tooltip.test.MockItemFactory {

    public static function meleeWeapon():Object {
        var item:Object = {name: "测试军刀", displayname: "测试军刀", type: "武器", use: "刀", actiontype: "斩击", price: 15200};
        var data:Object = {level: 9, weight: 3, power: 100, force: 10, hp: 50, defence: 5, bladeCount: 3, dressup: "刀-测试军刀"};
        return {item: item, data: data, equipData: null};
    }

    public static function gun():Object {
        var item:Object = {name: "测试手枪", displayname: "测试手枪", type: "武器", use: "手枪", price: 20000};
        var data:Object = {level: 10, weight: 2, clipname: "手枪通用弹药", bullet: "普通", capacity: 12, interval: 200, impact: 50, split: 1, singleshoot: false, reloadType: "clip", power: 80};
        return {item: item, data: data, equipData: null};
    }

    public static function grenade():Object {
        var item:Object = {name: "测试手雷", displayname: "测试手雷", type: "武器", use: "手雷", price: 500};
        var data:Object = {level: 1, weight: 1, power: 200};
        return {item: item, data: data, equipData: null};
    }

    public static function armor():Object {
        var item:Object = {name: "测试护甲", displayname: "测试护甲", type: "防具", use: "防具", price: 8000};
        var data:Object = {level: 5, weight: 8, defence: 50, hp: 100};
        return {item: item, data: data, equipData: null};
    }

    public static function upgradedGun():Object {
        var base:Object = gun();
        base.equipData = {level: 10, weight: 2, clipname: "手枪通用弹药", bullet: "普通", capacity: 18, interval: 160, impact: 50, split: 1, singleshoot: false, reloadType: "clip", power: 80};
        return base;
    }

    public static function weaponWithCrit():Object {
        var base:Object = meleeWeapon();
        base.data.criticalhit = 10;
        return base;
    }

    public static function weaponWithMagic():Object {
        var base:Object = meleeWeapon();
        base.data.damagetype = "魔法";
        base.data.magictype = "热";
        return base;
    }

    public static function weaponWithResistance():Object {
        var base:Object = meleeWeapon();
        var md:Object = {};
        md["热"] = 10;
        md["冷"] = 5;
        base.data.magicdefence = md;
        return base;
    }

    public static function weaponWithSilencePercent():Object {
        var base:Object = gun();
        base.data.silence = "90%";
        return base;
    }

    public static function weaponWithSilenceDistance():Object {
        var base:Object = gun();
        base.data.silence = "300";
        return base;
    }

    public static function weaponWithSlay():Object {
        var base:Object = meleeWeapon();
        base.data.slay = 8;
        return base;
    }

    /** 最小 baseItem mock（满足 EquipmentStatsComposer L42）
     * 无返回类型注解，避免传递给 BaseItem 参数时触发 AS2 类型检查 */
    public static function mockBaseItem() {
        return {value: {level: 1}, getData: function() { return null; }};
    }
}
