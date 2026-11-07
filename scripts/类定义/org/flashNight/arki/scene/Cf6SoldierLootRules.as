import org.flashNight.gesh.object.PersistedSnapshot;

/** Pure packet/quota rules. No inventory, RNG, save, actor or UI side effects. */
class org.flashNight.arki.scene.Cf6SoldierLootRules {
    public static function whole(value,minimum:Number,maximum:Number):Boolean {
        return typeof value=="number" && isFinite(value) && Math.floor(value)==value && value>=minimum && value<=maximum;
    }
    public static function create(roster:String,policy:String):Object {
        return {v:2,rosterVersion:roster,policyVersion:policy,records:{},prd:{},sequence:0,
            packages:0,pairs:0,weaponInstances:0,materials:0};
    }
    private static function emptyObject(value):Boolean {
        if(value==null || typeof value!="object" || value instanceof Array)return false;
        for(var key:String in value)return false;
        return true;
    }
    /** AMF0 may read an empty array as an empty object. Repair only the known
     * packet/item array fields on a detached copy; never erase malformed data
     * or revise a prior version's durable outcome, quota or full item value. */
    public static function normalizeLedger(raw:Object):Object {
        if(raw==null)return {ok:true,changed:false,feature:raw};
        if(raw.v!==2)return {ok:false,changed:false,error:"future_cf6_loot"};
        var candidate:Object=PersistedSnapshot.cloneData(raw),changed:Boolean=false;
        for(var key:String in candidate.records){
            var packet:Object=candidate.records[key];
            if(emptyObject(packet.items)){packet.items=[];changed=true;}
            if(emptyObject(packet.consumables)){packet.consumables=[];changed=true;}
            if(packet.items instanceof Array)for(var i:Number=0;i<packet.items.length;i++){
                var value:Object=packet.items[i].value;
                if(typeof value=="object" && emptyObject(value.mods)){value.mods=[];changed=true;}
            }
        }
        return validLedger(candidate)?{ok:true,changed:changed,feature:changed?candidate:raw}
            :{ok:false,changed:false,error:"invalid_cf6_loot"};
    }
    public static function normalizeSaveData(data:Object):Boolean {
        var raw:Object=data.ext.bookRun.cf6SoldierLoot;
        if(raw==null)return true;
        var normalized:Object=normalizeLedger(raw);
        if(!normalized.ok)return false;
        if(normalized.changed)data.ext.bookRun.cf6SoldierLoot=normalized.feature;
        return true;
    }
    public static function validWeapon(item:Object):Boolean {
        if(item==null || typeof item.name!="string" || item.name=="" || typeof item.lastUpdate!="number" || !isFinite(item.lastUpdate)
            || item.value==null || typeof item.value!="object" || item.value instanceof Array
            || !whole(item.value.level,1,13) || !(item.value.mods instanceof Array))return false;
        if(item.name=="G1111" && typeof item.value.isRocketMode!="boolean")return false;
        var denied:Array=["cf6G1111FixedMode","cf6G1111Action","__g1111Owner","__cf6G1111",
            "__cf6DangerAction","autoTarget","targetMovieClip","dangerPermit","cf6DamageGroup","cf6BoundTarget"];
        for(var i:Number=0;i<denied.length;i++)if(item[denied[i]]!==undefined || item.value[denied[i]]!==undefined)return false;
        var seen:Object={};
        for(i=0;i<item.value.mods.length;i++){
            var name:String=item.value.mods[i];
            if(typeof name!="string" || name=="" || seen["$"+name])return false;
            seen["$"+name]=true;
        }
        return dataOnly(item,0);
    }
    private static function dataOnly(value,depth:Number):Boolean {
        var kind:String=typeof value;
        if(kind=="function" || kind=="movieclip" || depth>32)return false;
        if(kind=="number")return isFinite(value);
        if(value==null || kind!="object")return kind!="undefined";
        for(var key:String in value)if(!dataOnly(value[key],depth+1))return false;
        return true;
    }
    public static function validPacket(packet:Object):Boolean {
        if(packet==null || packet.schema!="cf6-loot-packet.v2" || typeof packet.sourceKey!="string" || packet.sourceKey==""
            || typeof packet.unitIdentity!="string" || packet.unitIdentity=="" || typeof packet.spawnIdentity!="string" || packet.spawnIdentity==""
            || typeof packet.rosterVersion!="string" || typeof packet.configurationFingerprint!="string"
            || !(packet.items instanceof Array) || !(packet.consumables instanceof Array)
            || packet.items.length>2 || packet.consumables.length>2 || packet.roll.recorded!==true
            || typeof packet.roll.gateEvaluated!="boolean" || typeof packet.roll.hit!="boolean"
            || !isFinite(packet.roll.nominalPercent) || packet.roll.nominalPercent<0 || packet.roll.nominalPercent>100
            || !isFinite(packet.roll.luckBonus) || packet.roll.luckBonus<0 || packet.roll.luckBonus>.5
            || typeof packet.roll.prdPoolKey!="string" || packet.roll.prdPoolKey=="")return false;
        var kind:String=packet.kind;
        if(kind=="none")return packet.state=="DECIDED_MISS" && !packet.roll.hit
            && packet.items.length==0 && packet.consumables.length==0
            && (packet.roll.gateEvaluated?packet.roll.reason=="roll_miss":packet.roll.reason=="quota_exhausted" || packet.roll.reason=="ineligible");
        if(packet.state!="DECIDED_HIT" && packet.state!="COMMIT_PENDING" && packet.state!="OWNED")return false;
        if(!packet.roll.hit || !packet.roll.gateEvaluated)return false;
        if(packet.roll.reason=="first_weapon_guarantee"){
            if(kind!="longgun" || typeof packet.roll.naturalHit!="boolean"
                || !whole(packet.roll.guaranteeAfter,1,158) || !whole(packet.roll.eligibleOrdinal,packet.roll.guaranteeAfter,158))return false;
        }else if(packet.roll.reason!="roll_hit")return false;
        if(kind=="longgun" && packet.items.length!=1 || kind=="sidearm_pair" && packet.items.length!=2
            || kind=="mod_material" && (packet.items.length!=1 || packet.consumables.length!=0))return false;
        if(kind!="longgun" && kind!="sidearm_pair" && kind!="mod_material")return false;
        for(var i:Number=0;i<packet.items.length;i++){
            var item:Object=packet.items[i];
            if(kind=="mod_material"){
                if(typeof item.name!="string" || item.name=="" || !whole(item.value,1,1) || !isFinite(item.lastUpdate))return false;
            }else if(!validWeapon(item))return false;
        }
        var seen:Object={};
        for(i=0;i<packet.consumables.length;i++){
            item=packet.consumables[i];
            if(typeof item.name!="string" || item.name=="" || !whole(item.value,1,1000000)
                || !isFinite(item.lastUpdate) || seen["$"+item.name])return false;
            seen["$"+item.name]=true;
        }
        return kind=="mod_material" || packet.consumables.length>0;
    }
    public static function validLedger(ledger:Object):Boolean {
        if(ledger==null || ledger.v!==2 || typeof ledger.rosterVersion!="string" || typeof ledger.policyVersion!="string"
            || ledger.records==null || ledger.records instanceof Array || ledger.prd==null || ledger.prd instanceof Array
            || !whole(ledger.sequence,0,10000))return false;
        var packages:Number=0,pairs:Number=0,weapons:Number=0,materials:Number=0,records:Number=0,guarantees:Number=0,sources:Object={};
        for(var key:String in ledger.records){
            var packet:Object=ledger.records[key];records++;
            if(!validPacket(packet) || key!=="u."+packet.unitIdentity || sources["$"+packet.sourceKey])return false;
            sources["$"+packet.sourceKey]=true;
            if(packet.roll.reason=="first_weapon_guarantee")guarantees++;
            if(packet.kind=="none")continue;
            packages++;
            if(packet.kind=="sidearm_pair"){pairs++;weapons+=2;}
            if(packet.kind=="longgun")weapons++;
            if(packet.kind=="mod_material")materials++;
        }
        return records<=158 && guarantees<=1 && packages<=6 && pairs<=2 && weapons<=8 && materials<=2
            && ledger.packages===packages && ledger.pairs===pairs && ledger.weaponInstances===weapons && ledger.materials===materials;
    }
    public static function available(ledger:Object,snapshot:Object,weights:Object):Object {
        var result:Object={longgun:0,sidearm_pair:0,mod_material:0,total:0};
        if(ledger.packages>=6)return result;
        if(ledger.weaponInstances<8 && validWeapon(snapshot.primary))result.longgun=weights.longgun;
        if(ledger.pairs<2 && ledger.weaponInstances<=6 && validWeapon(snapshot.left) && validWeapon(snapshot.right))result.sidearm_pair=weights.sidearm_pair;
        if(ledger.materials<2 && typeof snapshot.material=="string" && snapshot.material!="")result.mod_material=weights.mod_material;
        if(!whole(result.longgun,0,1000) || !whole(result.sidearm_pair,0,1000) || !whole(result.mod_material,0,1000))return null;
        result.total=result.longgun+result.sidearm_pair+result.mod_material;return result;
    }
    /** Count only frozen, evaluated deaths; cancelled/ineligible identities are not pity progress. */
    public static function eligibleDeaths(ledger:Object):Number {
        var count:Number=0;
        for(var key:String in ledger.records)if(ledger.records[key].roll.gateEvaluated===true)count++;
        return count;
    }
    public static function firstWeaponDue(ledger:Object,pool:Object,policy:Object,eligible:Boolean):Boolean {
        if(policy.firstWeaponGuarantee==null)return false;
        var threshold=policy.firstWeaponGuarantee.afterEligibleDeaths;
        return eligible && whole(threshold,1,158) && ledger.weaponInstances===0 && pool.longgun>0
            && eligibleDeaths(ledger)+1>=threshold;
    }
    public static function choose(weights:Object,randomValue:Number):String {
        if(weights==null || !(weights.total>0) || !isFinite(randomValue) || randomValue<0 || randomValue>=1)return "none";
        var value:Number=randomValue*weights.total;
        if(value<weights.longgun)return "longgun";
        if(value<weights.longgun+weights.sidearm_pair)return "sidearm_pair";
        return "mod_material";
    }
    public static function ammoQuote(snapshot:Object,kind:String,packCost:Function):Array {
        var names:Array=[],totals:Object={};
        var slots:Array=kind=="longgun"?[snapshot.primaryAmmo]:kind=="sidearm_pair"?[snapshot.leftAmmo,snapshot.rightAmmo]:[];
        for(var i:Number=0;i<slots.length;i++){
            var attrs:Object=slots[i];
            if(typeof attrs.clipname!="string" || attrs.clipname=="" || !whole(attrs.capacity,1,1000000))return null;
            var cost:Number=packCost(attrs.capacity,0,attrs.capacity);
            if(!addAmmo(names,totals,attrs.clipname,cost))return null;
        }
        var sub:Object=snapshot.subAmmo;
        if(kind=="longgun" && sub!=null){
            if(!whole(sub.capacity,1,1000000) || typeof sub.reserveName!="string" || sub.reserveName=="")return null;
            var subCost:Number;
            if(sub.consumeMode=="onLoadGroup")subCost=sub.clipCostPerLoad;
            else if(sub.consumeMode=="onFire")subCost=sub.fireCost*sub.capacity;
            else return null;
            if(!whole(subCost,0,1000000))return null;
            if(subCost>0 && !addAmmo(names,totals,sub.reserveName,subCost))return null;
        }
        if(names.length>2)return null;
        var result:Array=[];
        for(i=0;i<names.length;i++)result.push({name:names[i],value:totals["$"+names[i]],lastUpdate:snapshot.lastUpdate});
        return result;
    }
    private static function addAmmo(names:Array,totals:Object,name:String,count:Number):Boolean {
        if(!whole(count,1,1000000))return false;
        var key:String="$"+name;
        if(totals[key]===undefined){totals[key]=0;names.push(name);}
        totals[key]+=count;return whole(totals[key],1,1000000);
    }
    public static function packet(header:Object,snapshot:Object,kind:String,roll:Object,consumables:Array):Object {
        var items:Array=[];
        if(kind=="longgun")items=[snapshot.primary];
        else if(kind=="sidearm_pair")items=[snapshot.left,snapshot.right];
        else if(kind=="mod_material")items=[{name:snapshot.material,value:1,lastUpdate:snapshot.lastUpdate}];
        return {schema:"cf6-loot-packet.v2",sourceKey:header.sourceKey,unitIdentity:header.unitIdentity,
            spawnIdentity:header.spawnIdentity,rosterVersion:header.rosterVersion,
            configurationFingerprint:header.configurationFingerprint,kind:kind,
            state:kind=="none"?"DECIDED_MISS":"DECIDED_HIT",
            items:PersistedSnapshot.cloneArrayData(items),consumables:PersistedSnapshot.cloneArrayData(consumables),
            roll:PersistedSnapshot.cloneData(roll)};
    }
    public static function reserve(ledger:Object,packet:Object):Boolean {
        if(ledger==null || ledger.records==null || ledger.records instanceof Array
            || !validPacket(packet) || ledger.records["u."+packet.unitIdentity]!==undefined)return false;
        for(var key:String in ledger.records)if(ledger.records[key].sourceKey===packet.sourceKey)return false;
        if(packet.roll.reason=="first_weapon_guarantee" && (ledger.weaponInstances!==0
            || packet.roll.eligibleOrdinal!==eligibleDeaths(ledger)+1))return false;
        if(packet.kind!="none" && (ledger.packages>=6
            || packet.kind=="sidearm_pair" && (ledger.pairs>=2 || ledger.weaponInstances>6)
            || packet.kind=="longgun" && ledger.weaponInstances>=8
            || packet.kind=="mod_material" && ledger.materials>=2))return false;
        ledger.records["u."+packet.unitIdentity]=PersistedSnapshot.cloneData(packet);
        if(packet.kind!="none")ledger.packages++;
        if(packet.kind=="sidearm_pair"){ledger.pairs++;ledger.weaponInstances+=2;}
        if(packet.kind=="longgun")ledger.weaponInstances++;
        if(packet.kind=="mod_material")ledger.materials++;
        return true;
    }
}
