import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.obtain.ItemObtainIndex;
import org.flashNight.gesh.tooltip.TooltipInputProjection;

class org.flashNight.gesh.tooltip.TooltipBookShopFilterTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;

    private static function check(value:Boolean, label:String):Void {
        if (value) passed++;
        else { failed++; trace("TooltipBookShopFilterTest FAIL: " + label); }
    }

    private static function hasNpc(records:Array, npc:String):Boolean {
        for (var i:Number = 0; i < records.length; i++) {
            if (records[i].npc == npc) return true;
        }
        return false;
    }

    public static function runAllTests():Void {
        passed = 0; failed = 0;
        var index:ItemObtainIndex = ItemObtainIndex.getInstance();
        index.reset(true);
        var shops:Object = {};
        shops["书中-CF6毒刺-35级"] = ["Glock 18"];
        shops["书中-CF6六一-A19"] = ["Glock 18"];
        shops["King"] = ["Glock 18"];
        shops["Shop Girl"] = ["Glock 18"];
        shops["书中-other"] = ["Glock 18"];
        index.buildIndex({}, shops, [], null);
        ItemUtil.itemDataDict = {};
        ItemUtil.itemDataDict["Glock 18"] = {use:"手枪", data:{level:1}};
        var projection:Object = TooltipInputProjection.forItem("Glock 18", null, null, "test");
        var records:Array = projection.projection.obtainRecords;
        check(records.length == 2, "all book shops are filtered from tooltip sources");
        check(hasNpc(records, "King"), "King remains available");
        check(hasNpc(records, "Shop Girl"), "Shop Girl remains available");
        check(!hasNpc(records, "书中-other") && !hasNpc(records, "书中-CF6毒刺-35级")
            && !hasNpc(records, "书中-CF6六一-A19"), "every book source is hidden");
        trace("TooltipBookShopFilterTest Tests Passed: " + passed);
        trace("TooltipBookShopFilterTest Tests Failed: " + failed);
    }
}
