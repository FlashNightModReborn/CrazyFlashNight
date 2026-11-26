import org.flashNight.neur.Server.SaveManager;

/** One retained, Host-owned exit operation per loadout session. No operation here releases pause. */
class org.flashNight.arki.item.CharacterBuildExit {
    public static function capture(r:Object, generation:Number):Object {
        return {owner:r.存档系统, ext:r._saveExt, slot:r.savePath, role:r.角色名,
            world:r.gameworld, actor:r.gameworld[r.控制目标], generation:generation, sequence:0,
            context:"character." + generation, endpoints:{}, ledger:null};
    }

    private static function current(o:Object, r:Object, p:Object):Boolean {
        return o != null && r.存档系统 != null && o.owner === r.存档系统 && o.ext === r._saveExt
            && o.slot === r.savePath && o.slot === p.slot && typeof o.slot == "string" && o.slot.length > 0
            && o.role === r.角色名 && typeof o.role == "string" && o.role.length > 0
            && o.generation === p.sessionGeneration && o.world === r.gameworld
            && o.actor != null && o.actor === r.gameworld[r.控制目标];
    }

    private static function covered(sm:SaveManager, proof:Object):Boolean {
        var a:Object=proof.attempt;
        if (!sm.exitAttemptCurrent(a) || a.rawConfirmed !== true || proof.image == null
                || a.owner !== _root.存档系统 || a.slot !== String(_root.savePath) || a.role !== String(_root.角色名)
                || sm.hasPendingChanges() || proof.attemptedWrite === true) return false;
        var current:Object = sm.packGameState();
        var written:Object = proof.image[SaveManager.SAVE_KEY];
        // Wall-clock time of the second pack is the only non-player field to exclude.
        current.lastSaved = written.lastSaved;
        return org.flashNight.gesh.object.PersistedSnapshot.sameData(written,current)
            && org.flashNight.gesh.object.PersistedSnapshot.sameData(proof.image,proof.attempt.so.data);
    }

    private static function domainsReady(sm:SaveManager):Boolean {
        return sm.settingsWriteAllowed() && !sm.hasRewardCommitPending()
            && !org.flashNight.arki.ui.GymTrainingPanelService.hasUnconfirmedGrowth()
            && !org.flashNight.arki.item.LootContainerService.hasStageSettlementPending()
            && !org.flashNight.arki.item.LootContainerService.hasPendingTransportDetach();
    }

    private static function sameOperation(x:Object,p:Object):Boolean {
        return x != null && x.id === p.operationId && x.sequence === p.sequence && x.panel === p.panelInstanceId
            && x.transport === p.transportGeneration && x.epoch === p.writeEpoch
            && x.loadout === p.loadoutRevision && x.live === p.liveRevision && x.drug === p.drugRevision;
    }

    private static function protectField(value:Object, key:String, x:Object):Boolean {
        if (value == null) return true;
        var existed:Boolean = Object.prototype.hasOwnProperty.call(value, key);
        if (typeof value.watch != "function" || !value.watch(key, function(name, before, after, guard) {
            if (before !== after) guard.attemptedWrite = true;
            return before;
        }, x)) return false;
        x.watches.push({value:value, key:key, existed:existed});
        return true;
    }

    // Movie-clip callbacks retain the original equipped value even while the world is paused.
    private static function sealAmmo(r:Object, x:Object, owner:Object):Boolean {
        x.containers = [r.物品栏.装备栏, r.物品栏.背包, r.物品栏.药剂栏, r.物品栏.仓库, r.物品栏.战备箱,
            r.收集品栏.材料, r.收集品栏.情报];
        x.watches = [];
        for (var c:Number=0; c<x.containers.length; c++) {
            var container:Object=x.containers[c];
            if (container == null || container.exitWriteSeal != null) return false;
            container.exitWriteSeal=x;
        }
        var inv:Object = r.物品栏.装备栏;
        var slots:Array = ["手枪","手枪2","长枪"];
        var counters:Array = ["shot","reloadCount","subweaponShot","subweaponReloadCount","isRocketMode","ammoState"];
        var rounds:Array = ["v","capacity","reserve","reserveName","chamber","ghost","reward","paidChamber","paidNormal","rewardScope"];
        // A failed rebuild may still point at the gun that just moved into the backpack.
        var values:Array=[];
        for (var s:Number=0; s<slots.length; s++) {
            values.push(inv.getItem(slots[s]).value, owner.actor[slots[s]].value);
        }
        for (var key:String in owner.endpoints) {
            var e:Object=owner.endpoints[key];
            if (e.firearm && e.container === r.物品栏.背包) values.push(e.item.value);
        }
        for (var i:Number=0; i<values.length; i++) {
            var value:Object=values[i];
            if (value == null || typeof value != "object") continue;
            var previous:Number=0;
            while (previous<i && values[previous] !== value) previous++;
            if (previous<i) continue;
            for (var n:Number=0; n<counters.length; n++) {
                if (!protectField(value,counters[n],x)) return false;
            }
            for (var j:Number=0; j<rounds.length; j++) {
                if (!protectField(value.ammoState,rounds[j],x)) return false;
            }
        }
        return true;
    }

    private static function release(r:Object, x:Object):Void {
        for (var i:Number=0; i<x.watches.length; i++) {
            var w:Object=x.watches[i];
            w.value.unwatch(w.key);
            if (!w.existed) delete w.value[w.key];
        }
        for (var c:Number=0; c<x.containers.length; c++) {
            var container:Object=x.containers[c];
            if (container != null && container.exitWriteSeal === x) container.exitWriteSeal = null;
        }
        if (r.__characterExitSeal === x) delete r.__characterExitSeal;
        x.image=null;
        x.attempt=null;
    }

    private static function status(o:Object,r:Object,p:Object,eligible:Function):String {
        if (!current(o,r,p) || typeof p.operationId != "string" || p.operationId.length != 32
                || p.v !== 1 || !(p.sequence > 0) || !(p.transportGeneration > 0)) return "blocked";
        var x:Object=o.ledger;
        var sm:SaveManager=SaveManager.getInstance();
        if (!sameOperation(x,p)) {
            if (p.phase != "prepare" || p.sequence <= o.sequence || r.__characterExitSeal != null
                    || !eligible(p) || !domainsReady(sm)) return "blocked";
            o.sequence=p.sequence;
            x={id:p.operationId, sequence:p.sequence, panel:p.panelInstanceId, transport:p.transportGeneration,
                epoch:p.writeEpoch, loadout:p.loadoutRevision, live:p.liveRevision, drug:p.drugRevision, state:"prepared"};
            o.ledger=x;
        }
        if (p.phase != "prepare" && p.phase != "persist" && p.phase != "query") return "blocked";
        if (p.phase == "persist" || x.state == "terminate") {
            if (p.role !== o.role || p.context !== o.context) return "unconfirmed";
        }
        if (x.state == "terminate") {
            // A lost receipt is a query of this exact save. Inspect its image again
            // in case a synchronous listener or late callback invalidated it.
            if (r.__characterExitSeal === x && eligible(p) && domainsReady(sm) && covered(sm,x))
                return "terminate";
            x.state="blocked";
            release(r,x);
        }
        if (x.state != "prepared" || p.phase != "persist") return x.state;
        if (!eligible(p) || !domainsReady(sm) || !current(o,r,p)) {
            x.state="blocked"; return x.state;
        }
        x.state="unconfirmed";
        r.__characterExitSeal=x;
        try {
            if (sealAmmo(r,x,o)) {
                x.flushing=true;
                try { sm.flushBeforeTransition("safe_exit"); } finally { x.flushing=false; }
            }
            if (current(o,r,p) && eligible(p) && domainsReady(sm) && covered(sm,x)) {
                x.state="terminate";
                x.serial=x.attempt.serial;
                return x.state;
            }
        } catch (error) { trace("[CharacterBuildExit] save proof failed: " + error); }
        if (x.physicalStarted !== true || x.rawFailed === true || x.attempt.rawConfirmed === true) {
            x.state="blocked";
            release(r,x);
        }
        return x.state;
    }

    public static function handle(o:Object,r:Object,p:Object,eligible:Function):Object {
        var state:String="unconfirmed";
        try { state=status(o,r,p,eligible); } catch (error) { trace("[CharacterBuildExit] " + error); }
        if (typeof r.server.sendServerMessage == "function") {
            try { r.server.sendServerMessage("event=character_build_persisted_exit phase="+p.phase+" state="+state
                +" serial="+Number(o.ledger.serial || 0)+" session="+p.sessionGeneration); } catch (ignored) {}
        }
        return {task:"loadout_exit_response", v:1, callId:p.callId, operationId:p.operationId, sequence:p.sequence,
            panelInstanceId:p.panelInstanceId, sessionGeneration:p.sessionGeneration, transportGeneration:p.transportGeneration,
            writeEpoch:p.writeEpoch, loadoutRevision:p.loadoutRevision,liveRevision:p.liveRevision,drugRevision:p.drugRevision,
            slot:p.slot,role:o == null ? "" : o.role,context:o == null ? "" : o.context,
            state:state,saveSerial:state=="terminate" ? o.ledger.serial : 0};
    }
}
