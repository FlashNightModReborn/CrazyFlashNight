/** 店级资格由导航和交易共同消费；来源索引及商品目录不自行授予访问权。 */
class org.flashNight.arki.item.NpcShopAccessService {
    public static function canAccess(shopId:String):Boolean {
        if (!org.flashNight.arki.scene.Cf6Type61Service.shopAllowed(shopId)) return false;
        if (shopId == "书中-迷之盔甲君") {
            var run:Object = _root._saveExt.bookRun;
            return run != null && run.bookId === "repair-campus" && run.outcome === "active"
                && run.slot === String(_root.savePath)
                && _root.当前关卡名 === String(org.flashNight.arki.scene.BookDefinition.get().stageName);
        }
        // 真实当前世界中的 NPC 仍可现场服务，包括无车、普通生存和未映射的特殊 NPC。
        // 只认当前剪辑和权威目录引用，不接纳 caller 传入的 source / npc 名称作为资格。
        var world:MovieClip = _root.gameworld;
        var catalog:Object = _root.shops[shopId];
        if (typeof world == "movieclip" && catalog != undefined) {
            for (var key:String in world) {
                var npc = world[key];
                if (typeof npc == "movieclip" && npc._parent === world && npc.物品栏 === catalog) return true;
            }
        }
        var projection:Object = org.flashNight.arki.map.MapDomainBridge.getProjection();
        return org.flashNight.arki.map.MapDomainBridge.isCurrent()
            && projection.shopAccess[shopId] === true;
    }
    public static function captureContext():Object {
        return {slot:String(_root.savePath), saveOwner:_root.存档系统, run:_root._saveExt.bookRun,
            sceneEpoch:org.flashNight.arki.map.MapDomainBridge.getSceneEpoch()};
    }
    public static function isContextCurrent(context:Object):Boolean {
        return context != null && context.slot === String(_root.savePath)
            && context.saveOwner === _root.存档系统 && context.run === _root._saveExt.bookRun
            && context.sceneEpoch === org.flashNight.arki.map.MapDomainBridge.getSceneEpoch();
    }
}
