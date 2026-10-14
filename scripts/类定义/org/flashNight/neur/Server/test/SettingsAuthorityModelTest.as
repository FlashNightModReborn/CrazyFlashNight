import org.flashNight.neur.Server.SettingsCanonical;
import org.flashNight.neur.Server.SettingsCanonicalSchema;
import org.flashNight.neur.Server.SettingsAuthority;
import org.flashNight.gesh.object.PersistedSnapshot;
import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.arki.item.itemCollection.DrugInventory;
import org.flashNight.arki.item.itemCollection.Inventory;
import org.flashNight.arki.item.itemCollection.EquipmentInventory;

/** Only in-memory state and synthetic callbacks. Never obtains a SharedObject. */
class org.flashNight.neur.Server.test.SettingsAuthorityModelTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(ok:Boolean, name:String):Void {
        if (ok) passed++; else { failed++; trace("SettingsAuthorityModelTest FAIL: " + name); }
    }
    private static function sample():Object {
        var values:Array = [42,55,1,1,1,1,12,1,0,1,1,0,0,1];
        var codes:Array = [87,83,65,68,74,75,82,49,50,51,52,53,54,55,56,57,48,
            32,85,73,79,80,76,72,71,67,66,78,77,47,69,70,18,81,16,17];
        var settings:Object = {};
        var keys:Array = [];
        for (var i:Number = 0; i < 14; i++) {
            var booleanField:Boolean = false;
            for (var j:Number = 0; j < SettingsCanonicalSchema.BOOLEAN_INDEXES.length; j++) {
                if (SettingsCanonicalSchema.BOOLEAN_INDEXES[j] == i) booleanField = true;
            }
            settings[SettingsCanonicalSchema.SETTING_IDS[i]] = booleanField ? values[i] == 1 :
                i == 6 ? values[i] / 10 : i == 13 ? SettingsCanonicalSchema.PLAY_MODES[values[i]] : values[i];
        }
        for (var k:Number = 0; k < 36; k++) keys.push(["label", SettingsCanonicalSchema.KEY_IDS[k], codes[k]]);
        return {settings:settings, keys:keys};
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0;
        var directParent:ArrayInventory = new ArrayInventory(null,8);
        var directChild:DrugInventory = new DrugInventory(null,8);
        trace("[OWNED_FIXTURE_DIAG] direct inventory capacities=" + directParent.capacity + "," + directChild.capacity);
        trace("[OWNED_FIXTURE_DIAG] drug inherits array=" + (directChild instanceof ArrayInventory));
        check(directParent.capacity == 8 && directParent instanceof Inventory, "array inventory parent initialized");
        check(directChild.capacity == 8, "drug inventory owns eight slots");
        check(directChild instanceof ArrayInventory, "drug inventory preserves production inheritance");
        var directEquipment:EquipmentInventory = new EquipmentInventory(null);
        check(directEquipment instanceof Inventory && directEquipment.getItems() != null,
            "equipment inventory preserves production inheritance");
        var v:Object = sample();
        var canonical:String = SettingsCanonical.encode(v.settings, v.keys, true);
        check(canonical != null && canonical.length == 342, "fixed payload byte length");
        trace("SettingsAuthorityModelTest Canonical: " + canonical);
        v.settings.basicZoomScale = 1.24;
        check(SettingsCanonical.encode(v.settings, v.keys, true) == null, "no raw zoom rounding");
        v = sample(); v.settings.是否阴影 = 1;
        check(SettingsCanonical.encode(v.settings, v.keys, true) == null, "literal boolean");
        v = sample(); v.keys[1][2] = v.keys[0][2];
        check(SettingsCanonical.encode(v.settings, v.keys, true) == null, "duplicate key rejection");
        v = sample();
        var owner:Object = {};
        var a:SettingsAuthority = new SettingsAuthority({contextId:"ctx.demo", saveOwnerId:"owner.demo",
            originNamespaceDigest:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", writeAdmission:"allowed"}, owner, "owned", "vm.2");
        check(a.capture(v.settings, v.keys), "initial projection");
        var lease:Object = a.beginPreview();
        check(lease != null && lease.globalVolume == undefined, "opaque preview lease");
        var preview:Object = PersistedSnapshot.clone(v.settings); preview.setGlobalVolume = 90; preview.setBGMVolume = 80;
        a.capture(preview, v.keys);
        check(a.projection().settings.setGlobalVolume == 42 && a.projection().settings.setBGMVolume == 55,
            "preview excluded from save projection");
        var audio:Object = {globalVolume:90, bgmVolume:80,
            setGlobalVolume:function(n:Number):Void { this.globalVolume = n; },
            setBGMVolume:function(n:Number):Void { this.bgmVolume = n; }};
        check(!a.restorePreview({}, audio), "foreign lease cannot restore");
        check(a.restorePreview(lease, audio) && audio.globalVolume == 42 && audio.bgmVolume == 55, "own preview restored");
        v.settings.setGlobalVolume = 43;
        var desired:String = SettingsCanonical.encode(v.settings, v.keys, true);
        var request:Object = {contextId:a.contextId(), saveOwnerId:a.ownerId(), authorityEpoch:a.epoch(),
            operationToken:"op.1", saveAttemptId:"save.1", expectedCanonical:desired,
            baseStateToken:a.stateToken(), expectedRevision:a.revision(),
            originMutationRequestDigest:"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            settingsDigest:"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"};
        check(a.beginMutation(request, desired), "exact mutation admission");
        var blocked:Boolean = false;
        try { a.projection(); } catch (blockedError) { blocked = true; }
        check(blocked, "reentrant save blocked");
        check(a.completeMutation(v.settings, v.keys), "complete application");
        var projection:Object = a.projection(); var receipt:Object = a.freezeReceipt(projection);
        check(receipt != null && receipt.operationToken == "op.1" && receipt.revision == 1, "receipt only after complete apply");
        a.finishSave(false);
        check(a.readOutcome().applied === true && a.readOutcome().durable === false && a.state(false).needsSaveRetry,
            "applied unconfirmed remains retryable");
        check(a.confirmPacked(projection, receipt), "exact packed confirmation");
        a.finishSave(false);
        check(a.readOutcome().durable === true && a.readOutcome().attemptState == "confirmed", "late false cannot downgrade");
        var recovered:SettingsAuthority = new SettingsAuthority({contextId:"ctx.demo", saveOwnerId:"owner.demo", slot:"owned",
            originNamespaceDigest:a.originDigest(), writeAdmission:"allowed", rawCanonical:desired, recoveryConfirmation:"cold_read_exact",
            recoveryMapping:{contextId:"ctx.demo",saveOwnerId:"owner.demo",originNamespaceDigest:a.originDigest(),slot:"owned",
                targetStateToken:"op.1",targetRevision:8,operationToken:"op.1",sourceAuthorityEpoch:"vm.old",
                originMutationRequestDigest:request.originMutationRequestDigest,settingsDigest:request.settingsDigest,
                currentAttempt:{saveAttemptId:"save.certified"}}},owner,"owned","vm.new");
        recovered.capture(v.settings,v.keys);recovered.installRecovery("sol");
        var recoveredReceipt:Object=recovered.freezeReceipt(recovered.projection());
        check(recovered.revision()==0 && recoveredReceipt.revision==8 && recoveredReceipt.sourceAuthorityEpoch=="vm.old",
            "cold operation keeps original revision when new VM autosaves");
        check(recoveredReceipt.saveAttemptId=="save.certified" && recovered.readOutcome().durable,
            "cold mapping keeps actual certified historical attempt");
        check(!a.sameOwner({}, "owned") && !a.sameOwner(owner, "different"), "owner and slot exact");
        var data:Object = {__unknown:{value:7}, first:{x:1}}; data.second = data.first;
        var copy:Object = PersistedSnapshot.cloneData(data);
        check(copy.__unknown.value == 7 && copy.first !== copy.second && copy.first !== data.first, "unknown fields and aliases detached");
        var shadowed:Object={hasOwnProperty:7,__serialized:9};
        check(PersistedSnapshot.cloneData(shadowed).__serialized==9,"own property name cannot poison complete snapshot");
        data.self = data; var cyclic:Boolean = false;
        try { PersistedSnapshot.cloneData(data); } catch (cycleError) { cyclic = true; }
        check(cyclic, "cycles rejected before exposure");
        trace("SettingsAuthorityModelTest Tests Passed: " + passed);
        trace("SettingsAuthorityModelTest Tests Failed: " + failed);
    }
}
