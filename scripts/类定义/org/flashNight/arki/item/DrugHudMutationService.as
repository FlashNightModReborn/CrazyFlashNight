import org.flashNight.arki.item.DrugSlotAffinityService;
import org.flashNight.arki.unit.Action.Skill.ManualCooldownService;
import org.flashNight.arki.item.PlayerAssetTransaction;
/** HUD unequip preserves the legacy first-vacancy policy (never silently merges stacks). */
class org.flashNight.arki.item.DrugHudMutationService {
    public static function unequip(root:Object, slot:Number, expectedItem:Object, expectedCount:Number, locked:Boolean):Object {
        if (locked) return {success:false, error:"locked"};
        if (isNaN(slot) || slot < 0 || slot > 7 || Math.floor(slot) != slot) return {success:false, error:"invalid_slot"};
        var source:Object = root.物品栏.药剂栏;
        var bag:Object = root.物品栏.背包;
        if (source == null || bag == null || root.存档系统 == null) return {success:false, error:"not_ready"};
        var current:Object = source.getItem(String(slot));
        if (current == null || current !== expectedItem || Number(current.value) != expectedCount) return {success:false, error:"stale_state"};
        if (!ManualCooldownService.isReady(ManualCooldownService.drugKey(slot % 4))) return {success:false, error:"cooldown"};
        var destination:Number = Number(bag.getFirstVacancy());
        if (destination == -1) return {success:false, error:"bag_full"};
        var affinity:Object = DrugSlotAffinityService.previewNormalized(root, source);
        if (affinity == null || affinity.ok !== true) return {success:false, error:"not_ready"};
        try { PlayerAssetTransaction.markDirtyRequired(root.存档系统); }
        catch (error) { return {success:false, error:"not_ready"}; }
        if (!source.move(bag, String(slot), destination)) return {success:false, error:"move_failed"};
        var result:Object = DrugSlotAffinityService.recordManualSlots(root, source, [slot], true);
        if (result == null || result.success !== true) return {success:false, error:"needs_reconcile", changed:true};
        return {success:true, changed:true};
    }
}
