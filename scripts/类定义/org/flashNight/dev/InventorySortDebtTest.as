import org.flashNight.arki.item.*;
import org.flashNight.arki.item.itemCollection.*;
import org.flashNight.naki.DataStructures.*;

/** 同一操作输入比较旧/新排序，并直接计数真正的建树调用。 */
class org.flashNight.dev.InventorySortDebtTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean,name:String):Void {
        if(value) passed++; else { failed++; trace("[FAIL] InventorySortDebt "+name); }
    }
    private static function makeInventory(values:Array):ArrayInventory {
        var inv:ArrayInventory=new ArrayInventory(null,12);
        for(var i:Number=0;i<values.length;i++) inv.add(i*2+1,{name:values[i][0],value:values[i][1]});
        return inv;
    }
    private static function measure(inv:ArrayInventory, method:String, legacy:Boolean):Object {
        var api:Object=org.flashNight.naki.DataStructures.TreeSet;
        var original:Function=api.buildFromArray;
        var counter:Object={count:0};
        api.buildFromArray=function(values:Array,cmp:Function,kind:String):TreeSet {
            counter.count++;
            return original.call(api,values,cmp,kind);
        };
        var before:Number=inv.getMutationRevision();
        try {
            if(legacy) org.flashNight.dev.ItemSortUtilLegacy.sortInventory(inv,method);
            else ItemSortUtil.sortInventory(inv,method);
        } finally { api.buildFromArray=original; }
        return {calls:counter.count,revisionDelta:inv.getMutationRevision()-before,
            items:inv.getItemArray(),indexes:inv.getIndexes()};
    }
    public static function runAllTests():Void {
        passed=0;failed=0;
        ItemUtil.itemDataDict={Alpha:{name:"Alpha",type:"消耗品",use:"食品",price:3,id:1},
            Beta:{name:"Beta",type:"消耗品",use:"食品",price:2,id:2},
            Gamma:{name:"Gamma",type:"消耗品",use:"食品",price:5,id:3}};
        ItemUtil.equipmentDict={};ItemUtil.materialDict={};ItemUtil.informationMaxValueDict={};
        var cases:Array=[[["Beta",2],["Alpha",3]],[["Alpha",2],["Alpha",3],["Beta",1]],[],[["Gamma",1]],[["Beta",2],["Gamma",2],["Alpha",2]]];
        var methods:Array=["byName","byValue","byID","byType","byPrice"];
        for(var c:Number=0;c<cases.length;c++) {
            for(var m:Number=0;m<methods.length;m++) {
                var oldResult:Object=measure(makeInventory(cases[c]),methods[m],true);
                var nextResult:Object=measure(makeInventory(cases[c]),methods[m],false);
                check(oldResult.items.length==nextResult.items.length,"item count "+c+"/"+m);
                check(oldResult.indexes.join(",")==nextResult.indexes.join(","),"indexes "+c+"/"+m);
                check(oldResult.revisionDelta==nextResult.revisionDelta,"revision "+c+"/"+m);
                for(var i:Number=0;i<oldResult.items.length;i++) {
                    check(oldResult.items[i].name==nextResult.items[i].name&&oldResult.items[i].value==nextResult.items[i].value,"item value/order "+c+"/"+m+"/"+i);
                }
                check(nextResult.calls==oldResult.calls-2,"two redundant tree builds removed "+c+"/"+m);
            }
        }
        trace("InventorySortDebtTest passed="+passed+" failed="+failed);
    }
}
