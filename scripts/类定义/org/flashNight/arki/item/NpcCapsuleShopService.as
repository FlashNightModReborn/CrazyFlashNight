/** 合法胶囊的单次现场服务资格；不是普通远程商店访问权。 */
class org.flashNight.arki.item.NpcCapsuleShopService {
    private static var _shots:Array = [];
    private static var _active:Object;
    private static var _sequence:Number = 0;
    private static var CAPSULE:String = "谜之胶囊";
    private static var SHOP:String = "迷之盔甲君";

    private static function current(shot:Object):Boolean {
        var elapsed:Number = getTimer() - Number(shot.createdAt);
        return shot != null && (shot.state === "armed" || (shot.state === "pending" && elapsed > -1 && elapsed < 30000))
            && org.flashNight.arki.item.NpcShopAccessService.isContextCurrent(shot.context)
            && typeof shot.world == "movieclip" && shot.world === _root.gameworld
            && shot.world.__capsuleShopSceneIdentity === shot.sceneIdentity
            && typeof shot.unit == "movieclip" && shot.unit._parent === shot.world
            && shot.unit === shot.world[_root.控制目标]
            && shot.unit.__capsuleShopUnitIdentity === shot.unitIdentity;
    }

    private static function prune():Void {
        for (var i:Number = _shots.length - 1; i > -1; i--) {
            var shot:Object = _shots[i];
            if (!current(shot) || typeof shot.projectile != "movieclip"
                    || shot.projectile.__capsuleShopShot !== shot.seal) {
                _shots.splice(i, 1);
            }
        }
        if (_active != null && !sessionCurrent(_active)) _active = null;
    }

    /** 只由现役手雷攻击帧在真实弹体生成后、原有扣除前调用。 */
    public static function registerShot(unit:MovieClip, projectile:MovieClip):Object {
        prune();
        var world:MovieClip = _root.gameworld;
        var equipment:Object = _root.物品栏.装备栏;
        if (_root.暂停 || _root.存档系统 == undefined || typeof world != "movieclip"
                || typeof unit != "movieclip" || unit !== world[_root.控制目标]
                || unit._parent !== world || unit.是否为敌人 === true
                || typeof projectile != "movieclip" || projectile._parent !== world.子弹区域
                || projectile.子弹种类 !== CAPSULE || projectile.发射者 !== unit._name
                || projectile.__capsuleShopShot != undefined || _shots.length > 7) return null;
        var item:Object = equipment.getItem("手雷");
        var count:Number = item.value;
        var definition:Object = org.flashNight.arki.item.ItemUtil.getItemData(CAPSULE);
        // 主角装配持有的是装备栏原始 BaseItem；名称强转不能代替真实装备身份。
        if (item == null || unit.手雷 !== item || item.name !== CAPSULE || typeof item.value != "number"
                || !(count > 0 && count < 9007199254740992) || Math.floor(count) != count
                || definition.use !== "手雷" || definition.data.bullet !== CAPSULE
                || typeof equipment.getMutationRevision != "function") return null;
        var revision:Number = equipment.getMutationRevision();
        for (var previous:Number = 0; previous < _shots.length; previous++) {
            if (_shots[previous].equipment === equipment && _shots[previous].revision === revision) return null;
        }
        if (world.__capsuleShopSceneIdentity == undefined) world.__capsuleShopSceneIdentity = {};
        if (unit.__capsuleShopUnitIdentity == undefined) unit.__capsuleShopUnitIdentity = {};
        var seal:Object = {};
        var shot:Object = {state:"pending", world:world, unit:unit, projectile:projectile,
            sceneIdentity:world.__capsuleShopSceneIdentity, unitIdentity:unit.__capsuleShopUnitIdentity,
            context:org.flashNight.arki.item.NpcShopAccessService.captureContext(),
            equipment:equipment, item:item, count:count, revision:revision,
            seal:seal, createdAt:getTimer()};
        projectile.__capsuleShopShot = seal;
        _shots.push(shot);
        return seal;
    }

    /** 原有手雷扣除与记录完成后复核原件、数量和容器版本，不代办或重放扣除。 */
    public static function confirmShot(token:Object):Boolean {
        prune();
        var shot:Object = null;
        for (var i:Number = 0; i < _shots.length; i++) if (_shots[i].seal === token) shot = _shots[i];
        if (shot == null || shot.state !== "pending" || !current(shot)
                || _root.物品栏.装备栏 !== shot.equipment) return false;
        var remaining:Number = shot.count - 1;
        var expectedRevision:Number = shot.revision + (remaining > 0 ? 1 : 2);
        if (shot.equipment.getMutationRevision() !== expectedRevision) return false;
        var item:Object = shot.equipment.getItem("手雷");
        if (remaining > 0 ? (item !== shot.item || item.name !== CAPSULE || item.value !== remaining)
                         : !shot.equipment.isEmpty("手雷")) {
            shot.state = "rejected";
            return false;
        }
        shot.state = "armed";
        return true;
    }

    /** 弹体落地只消费一次资格；固定商店，不接纳 caller 的 shopId/source。 */
    public static function openProjectile(projectile:MovieClip):Boolean {
        prune();
        var shot:Object = null;
        var index:Number = -1;
        for (var i:Number = 0; i < _shots.length; i++) {
            var candidate:Object = _shots[i];
            if (candidate.projectile === projectile && candidate.seal === projectile.__capsuleShopShot) {
                shot = candidate; index = i; break;
            }
        }
        if (index < 0 || shot.state !== "armed" || !current(shot)
                || projectile._parent !== shot.world.子弹区域) return false;
        _shots.splice(index, 1);
        shot.state = "consumed";
        if (_root.shops[SHOP] == undefined || _root.server.sendSocketMessage == undefined) return false;
        _sequence++;
        var grant:Object = {id:"capsule." + getTimer() + "." + _sequence,
            owner:"", context:shot.context, world:shot.world, sceneIdentity:shot.sceneIdentity,
            unit:shot.unit, unitIdentity:shot.unitIdentity, createdAt:getTimer()};
        _active = grant;
        var payload:String = org.flashNight.arki.ui.PanelRequestEnvelope.build("npcshop", "npc_shop_refresh", [],
            [{name:"shopId", value:SHOP}, {name:"capsuleOpenId", value:grant.id}]);
        try {
            if (_root.server.sendSocketMessage(payload) === true) return true;
            if (_active === grant) _active = null;
        } catch (error) {
            // 投递可能已发生：保留有界 pending 身份，不重发，不回补或重放消耗。
            trace("[NpcCapsuleShop] open delivery unknown");
        }
        return false;
    }

    private static function safeOwner(value):Boolean {
        if (typeof value != "string" || value.length < 1 || value.length > 128) return false;
        for (var i:Number = 0; i < value.length; i++) {
            var code:Number = value.charCodeAt(i);
            if (!((code > 47 && code < 58) || (code > 64 && code < 91) || (code > 96 && code < 123)
                    || code == 45 || code == 46 || code == 95 || code == 126)) return false;
        }
        return true;
    }

    private static function sessionCurrent(grant:Object):Boolean {
        if (grant == null || !org.flashNight.arki.item.NpcShopAccessService.isContextCurrent(grant.context)
                || typeof grant.world != "movieclip" || grant.world !== _root.gameworld
                || grant.world.__capsuleShopSceneIdentity !== grant.sceneIdentity
                || typeof grant.unit != "movieclip" || grant.unit !== grant.world[_root.控制目标]
                || grant.unit.__capsuleShopUnitIdentity !== grant.unitIdentity) return false;
        var age:Number = getTimer() - Number(grant.createdAt);
        return grant.owner != "" || (age > -1 && age < 30000);
    }

    /** Host 私有开店关联 + exact instance 在首次 snapshot 单次绑定，后续报价/提交逐次复证。 */
    public static function authorize(shopId:String, openId, owner, bind:Boolean):Boolean {
        prune();
        var grant:Object = _active;
        if (shopId !== SHOP || grant == null || typeof openId != "string" || openId !== grant.id
                || !safeOwner(owner) || !sessionCurrent(grant)) return false;
        if (grant.owner == "") {
            if (!bind) return false;
            grant.owner = owner;
        }
        return grant.owner === owner;
    }

    /** exact close / rebind / disconnect 的回收不触碰交易未知写锁。 */
    public static function retire(openId, owner):Boolean {
        var grant:Object = _active;
        if (grant == null || typeof openId != "string" || openId !== grant.id || !safeOwner(owner)
                || (grant.owner != "" && grant.owner !== owner)) return false;
        _active = null;
        return true;
    }
}
