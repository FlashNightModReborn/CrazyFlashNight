/**
 * SwitchStrikeCore - 攻击模式切换时的切手技参数核心
 *
 * 时间轴只负责动画、命中定位器与形态名；所有伤害公式和冲击参数集中在此处。
 * 武器可通过 data.switchstrike 覆盖数值参数，不接受可执行公式字符串。
 */
class org.flashNight.arki.unit.Action.Melee.SwitchStrikeCore {

    private static var _profileDefaults:Object = null;

    /** 时间轴入口：初始化定位器子弹、应用形态参数并发射。 */
    public static function shoot(locator:MovieClip, profileName:String):Void {
        if (!locator || !locator._parent || !locator._parent._parent) return;

        var unit:MovieClip = locator._parent._parent;
        var bullet:Object = _root.子弹属性初始化(locator);
        if (!bullet) return;

        buildBulletProperties(unit, profileName, bullet);
        bullet.区域定位area = locator.area;
        _root.子弹区域shoot传递(bullet);
    }

    /** 纯参数构建入口，供运行时和 TestLoader 共用。 */
    public static function buildBulletProperties(unit:Object, profileName:String, bullet:Object):Object {
        if (!bullet) bullet = {};

        var profile:Object = resolveProfile(unit, profileName);
        if (!profile) return bullet;

        bullet.声音 = profile.sound != undefined ? profile.sound : "";
        bullet.霰弹值 = numberOr(profile.pelletCount, 1);
        bullet.子弹散射度 = numberOr(profile.diffusion, 0);
        bullet.子弹种类 = profile.bulletType || "近战子弹";
        bullet.子弹威力 = calculatePower(unit, profile);
        bullet.子弹速度 = numberOr(profile.velocity, 0);
        bullet.Z轴攻击范围 = numberOr(profile.zRange, 30);

        var knockRate:Number = numberOr(profile.knockRate, 10);
        var impactMultiplier:Number = numberOr(profile.impactMultiplier, 1);
        if (impactMultiplier <= 0) impactMultiplier = 1;
        bullet.击倒率 = knockRate / impactMultiplier;

        if (profile.horizontalKnockback != undefined) {
            bullet.水平击退速度 = Number(profile.horizontalKnockback);
        }
        if (profile.verticalKnockback != undefined) {
            bullet.垂直击退速度 = Number(profile.verticalKnockback);
        }
        if (profile.damageType != undefined) bullet.伤害类型 = profile.damageType;
        if (profile.magicType != undefined) bullet.魔法伤害属性 = profile.magicType;

        return bullet;
    }

    /** 解析形态默认值，并叠加对应武器 data.switchstrike 的受控字段。 */
    public static function resolveProfile(unit:Object, profileName:String):Object {
        var defaults:Object = getProfileDefaults()[profileName];
        if (!defaults) return null;

        var profile:Object = {};
        copyScalarFields(profile, defaults);

        var weaponData:Object = getWeaponData(unit, profileName);
        var custom:Object = weaponData ? weaponData.switchstrike : null;
        if (custom) {
            copyScalarFields(profile, custom);
            if (custom[profileName] && typeof custom[profileName] == "object") {
                copyScalarFields(profile, custom[profileName]);
            }
        }

        return profile;
    }

    private static function calculatePower(unit:Object, profile:Object):Number {
        var unarmedPower:Number = numberOr(unit ? unit.空手攻击力 : 0, 0);
        var power:Number = 0;
        var longgun:Object;
        var blade:Object;
        var passive:Object;

        switch (profile.powerMode) {
            case "longgunWeight":
                longgun = unit ? unit.长枪属性 : null;
                power = unarmedPower / numberOr(profile.unarmedDivisor, 5)
                    + numberOr(profile.weightCoefficient, 3) * numberOr(longgun ? longgun.weight : 0, 0);
                break;
            case "bladePower":
                blade = unit ? unit.刀属性 : null;
                power = unarmedPower / numberOr(profile.unarmedDivisor, 5)
                    + numberOr(profile.weaponPowerCoefficient, 1) * numberOr(blade ? blade.power : 0, 0);
                break;
            case "kick":
                power = unarmedPower * numberOr(profile.unarmedCoefficient, 1);
                passive = unit && unit.被动技能 ? unit.被动技能.拳脚攻击 : null;
                if (passive && passive.启用) {
                    power *= 1 + numberOr(passive.等级, 0) * 0.1;
                }
                break;
            default:
                power = unarmedPower * numberOr(profile.unarmedCoefficient, 1);
                break;
        }

        if (unit && unit.mp攻击加成) power += unit.mp攻击加成;
        return power;
    }

    private static function getWeaponData(unit:Object, profileName:String):Object {
        if (!unit) return null;
        if (profileName == "长枪") return unit.长枪属性;
        if (profileName == "兵器" || profileName == "双刀" || profileName == "疾影") {
            return unit.刀属性;
        }
        return null;
    }

    private static function copyScalarFields(target:Object, source:Object):Void {
        for (var key:String in source) {
            var value = source[key];
            if (typeof value != "object" || value == null) target[key] = value;
        }
    }

    private static function numberOr(value, fallback:Number):Number {
        var numeric:Number = Number(value);
        return isNaN(numeric) ? fallback : numeric;
    }

    private static function getProfileDefaults():Object {
        if (_profileDefaults) return _profileDefaults;

        _profileDefaults = {
            空手: {
                powerMode: "unarmed", unarmedCoefficient: 1.5,
                pelletCount: 3, diffusion: 0, bulletType: "近战联弹",
                velocity: 0, zRange: 30, knockRate: 1, horizontalKnockback: 15
            },
            长枪: {
                powerMode: "longgunWeight", unarmedDivisor: 5, weightCoefficient: 3,
                pelletCount: 3, diffusion: 0, bulletType: "近战联弹",
                velocity: 0, zRange: 30, knockRate: 5, impactMultiplier: 1,
                horizontalKnockback: 15, damageType: "物理"
            },
            兵器: {
                powerMode: "bladePower", unarmedDivisor: 5, weaponPowerCoefficient: 1,
                pelletCount: 3, diffusion: 0, bulletType: "近战联弹",
                velocity: 0, zRange: 30, knockRate: 10
            },
            双刀: {
                powerMode: "bladePower", unarmedDivisor: 5, weaponPowerCoefficient: 1,
                pelletCount: 3, diffusion: 0, bulletType: "近战联弹",
                velocity: 0, zRange: 30, knockRate: 10
            },
            疾影: {
                powerMode: "bladePower", unarmedDivisor: 5, weaponPowerCoefficient: 1,
                pelletCount: 3, diffusion: 0, bulletType: "近战联弹",
                velocity: 0, zRange: 30, knockRate: 10
            },
            回旋踢: {
                powerMode: "kick", unarmedCoefficient: 1,
                pelletCount: 1, diffusion: 0, bulletType: "近战子弹",
                velocity: 0, zRange: 37, knockRate: 1, horizontalKnockback: 24
            }
        };

        return _profileDefaults;
    }
}
