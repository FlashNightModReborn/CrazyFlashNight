import org.flashNight.arki.scene.*;
import org.flashNight.arki.unit.Action.Shoot.ShootInitCore;
import org.flashNight.arki.item.BaseItem;
/** Independent arithmetic anchors plus cache, source isolation and real initializer routing. */
class org.flashNight.arki.scene.Cf6SoldierFirepowerTest {
    private static var passed:Number,failed:Number;
    private static function check(ok:Boolean,label:String):Void {
        if(ok)passed++;else{failed++;trace("[FAIL] Cf6SoldierFirepowerTest "+label);}
    }
    private static function close(a:Number,b:Number):Boolean {return isFinite(a) && Math.abs(a-b)<0.00001;}
    private static function unit(r:Array):Object {
        var slot:String=r[1]==0?"长枪":r[1]==1?"手枪":"手枪2";
        var cfg:Array=[r[5],r[6],r[7],r[8],r[9],r[10]],guns:Array=[null,null,null];guns[r[1]]=cfg;
        var u:Object={cf6UnitIdentity:r[0],等级:r[2],被动技能:{},cf6FirepowerProfile:{v:1,c:r[3],q:r[4],s:2,g:guns}};
        u[slot]=new BaseItem(r[5],{level:r[10],tier:r[6],mods:[],shot:7},1);
        return u;
    }
    public static function runAllTests():Void {
        passed=failed=0;
        var rows:Array=Cf6SoldierFirepowerFixture.cases();
        check(rows.length==282,"282 independent selected-slot anchors");
        for(var i:Number=0;i<rows.length;i++){
            var r:Array=rows[i],u:Object=unit(r),slot:String=r[1]==0?"长枪":r[1]==1?"手枪":"手枪2";
            var expected:Number=r[11];u.cf6FirepowerProfile.s=0;
            check(close(ShootInitCore.calculateWeaponPower(u,slot,r[11],false),expected),r[0]+" "+slot+" A");
            u.cf6FirepowerProfile.s=1;
            check(close(ShootInitCore.calculateWeaponPower(u,slot,r[11],false),r[12]),r[0]+" "+slot+" B");
            u.cf6FirepowerProfile.s=2;
            var power:Number=ShootInitCore.calculateWeaponPower(u,slot,r[11],false);
            check(close(power,r[13]),r[0]+" "+slot+" C");
            check(u[slot].value.shot==7 && u[slot].value.mods.length==0 && u[slot].value.power==undefined,
                r[0]+" weapon snapshot unchanged");
            check(u.伤害加成==undefined && u.装备枪械威力加成==undefined && u.毒==undefined && u.被动技能.枪械攻击==undefined,
                r[0]+" actor globals and native passive unchanged");
            var poison:Object={毒:9};Cf6SoldierFirepower.applyPoison(u,slot,poison);
            check(poison.毒==9,r[0]+" pre-existing poison kept by max");
            if(r[7]!=0){
                var c:Object=u.cf6FirepowerProfile.cache[slot];
                check(close(c.power*0.025+c.nano,r[11]*0.025*(1+c.cap)) || c.power*0.025+c.nano<r[11]*0.025*(1+c.cap),
                    r[0]+" combined raw/nano ceiling");
                check(close(ShootInitCore.calculateWeaponPower(u,slot,r[11],false),power),r[0]+" repeated initialization does not compound");
                check(close(ShootInitCore.calculateWeaponPower(u,"刀",r[11],false),r[11]),r[0]+" melee excluded");
                check(close(ShootInitCore.calculateWeaponPower(u,"长枪副武器",r[11],false),r[11]),r[0]+" underbarrel excluded");
                check(close(ShootInitCore.calculateWeaponPower(u,slot,r[11],true),r[11]),r[0]+" ray excluded");
                u[slot].name="other";
                check(close(ShootInitCore.calculateWeaponPower(u,slot,r[11],false),r[11]),r[0]+" changed weapon source excluded");
            }
        }
        r=rows[0];u=unit(r);slot="长枪";
        var p0:Number=ShootInitCore.calculateWeaponPower(u,slot,r[11],false);
        u.等级=60;var p1:Number=ShootInitCore.calculateWeaponPower(u,slot,r[11],false);
        check(p1>p0,"level refresh invalidates cached projection");
        delete u.cf6UnitIdentity;
        check(close(ShootInitCore.calculateWeaponPower(u,slot,r[11],false),r[11]),"ordinary actors/player unchanged");
        // An already enabled native passive is counted once, even in a C-qualified slot.
        for(i=0;i<rows.length;i++)if(rows[i][0]=="CF6-M-IV" && rows[i][1]==0){r=rows[i];break;}
        u=unit(r);u.被动技能.枪械攻击={启用:true,等级:1};
        var baseline:Number=r[11]*1.53+30;
        var actual:Number=ShootInitCore.calculateWeaponPower(u,"长枪",r[11],false);
        var cap:Number=u.cf6FirepowerProfile.cache.长枪.cap;
        check(actual>=baseline && actual<=baseline*(1+cap)+0.00001,"existing passive preserved and not doubled");
        check(u.被动技能.枪械攻击.等级==1,"native skill identity untouched");
        trace("Cf6SoldierFirepowerTest: "+passed+" passed, "+failed+" failed; 282 independent slot anchors");
        if(failed>0)trace("[TEST_FAIL] Cf6SoldierFirepowerTest suite failed");
    }
}
