import org.flashNight.arki.item.RewardStashStore;
import org.flashNight.arki.item.RewardStashService;
import org.flashNight.gesh.object.PersistedSnapshot;

/** CF6星座抽取策略，只由ItemUse奖励候选写入；不依赖场景装配类。 */
class org.flashNight.arki.item.Cf6ConstellationPolicy {
    private static function isActive():Boolean {
        var run:Object=_root._saveExt.bookRun;
        return run.bookId === "cf6-sting" && run.routeId === "type61" && run.outcome === "active" && run.slot === String(_root.savePath);
    }
    private static function contains(rows:Array,name:String):Boolean {
        for(var i:Number=0;i<rows.length;i++)if(rows[i]===name)return true;return false;
    }
    private static function isConstellationPack(name:String):Boolean {
        return name === "61计划普通星座箱" || name === "61计划星座机缘箱";
    }
    private static function constellationSeen():Object {
        var run:Object=_root._saveExt.bookRun, seen:Object={};
        var names:Array=["光剑天秤","光斧金牛","光刀狮子","光刃摩羯","血色光剑天秤"];
        for (var n:Number=0;n<names.length;n++) if (run.type61Constellations[names[n]] === true) seen[names[n]]=true;
        // 旧局只回填实际持有物品；新局首发与后续抽取共用已保存的获得记录。
        var sources:Array=[_root.物品栏.背包,_root.物品栏.装备栏,_root.物品栏.仓库,_root.物品栏.战备箱];
        for (var c:Number=0;c<sources.length;c++) {
            if (typeof sources[c].toObject != "function") continue;
            var items:Object=sources[c].toObject();
            for (var key:String in items) if (contains(names,String(items[key].name))) seen[items[key].name]=true;
        }
        for (n=0;n<names.length;n++) if (RewardStashStore.ownedQuantity(RewardStashService.peek(),names[n])>0) seen[names[n]]=true;
        return seen;
    }
    /** 普通星座无放回；血剑保留独立10%机会，取得后不再重复血剑。 */
    public static function constellationRecipe(packName:String, recipe:Object):Object {
        if (!isActive() || !isConstellationPack(packName)) return recipe;
        var seen:Object=constellationSeen(), ordinary:Array=[], unseen:Array=[], blood:Object=null;
        for (var i:Number=0;i<recipe.entries.length;i++) {
            var entry:Object=recipe.entries[i];
            if (entry.itemName === "血色光剑天秤") {if (seen[entry.itemName] !== true) blood=entry;}
            else {ordinary.push(entry);if (seen[entry.itemName] !== true) unseen.push(entry);}
        }
        var selected:Array=unseen.length>0 ? unseen : ordinary, entries:Array=[], total:Number=0;
        for (i=0;i<selected.length;i++) {
            var copy:Object=PersistedSnapshot.clone(selected[i]);copy.weight=blood==null ? 1 : 9;
            entries.push(copy);total+=copy.weight;
        }
        if (blood != null && entries.length>0) {
            var rare:Object=PersistedSnapshot.clone(blood);rare.weight=entries.length;
            entries.push(rare);total+=rare.weight;
        }
        return {success:entries.length>0,mode:"chooseOne",entries:entries,totalWeight:total,maxOccurrences:1};
    }
    /** 只能在已经开始的奖励暂存候选内调用；ledger随同一次full-save冻结和恢复。 */
    public static function rememberConstellation(packName:String, entries:Array):Void {
        if (!isActive() || !isConstellationPack(packName) || RewardStashService.pendingOperationId() == "") return;
        var seen:Object=constellationSeen();
        for (var i:Number=0;i<entries.length;i++) seen[entries[i].itemName]=true;
        _root._saveExt.bookRun.type61Constellations=seen;
    }
}
