import org.flashNight.arki.hud.PlayerHudService;
import org.flashNight.arki.hud.PlayerHudUnitHotWire;

class org.flashNight.arki.hud.PlayerHudUnitHotWireTest {
    private static function focusRows(n:Number):Array {
        var rows:Array = [];
        for (var i:Number=0; i<n; i++) rows.push({id:i+1,role:i==0?"protect":"boss",name:"焦点甲"+i,icon:"unit"+i,hp:[800,1000]});
        return rows;
    }
    private static function allyRows(n:Number):Object {
        var rows:Array = [];
        for (var i:Number=0; i<n; i++) {
            var r:Object={id:21+i,generation:7,slot:i,role:i<5?"merc":(i<10?"pet":"map"),name:"同伴乙"+i,icon:"ally"+i,
                hp:[800,1000],shield:[30,60],down:false};
            r["protected"]=false;
            rows.push(r);
        }
        return {rows:rows,overflow:[]};
    }
    private static function step(old:Array, dense:Boolean, n:Number):Array {
        var next:Array=old.concat();
        var limit:Number=dense?old.length:Math.min(1,old.length);
        for(var i:Number=0;i<limit;i++) {
            var r:Object={};
            for(var k:String in old[i]) if(old[i].hasOwnProperty(k)) r[k]=old[i][k];
            r.hp=[800+n+i*0.5,1000];
            if(r.shield!=undefined) { r.shield=[30+n,60]; r.down=n==10; }
            else if(n%2!=0) r.hits=2;
            else delete r.hits;
            next[i]=r;
        }
        return next;
    }
    private static function measure(f:Number,a:Number,dense:Boolean):Boolean {
        var focus:Array=focusRows(f), allies:Object=allyRows(a);
        var cold:Object={focusTarget:focus};
        if(a>0) cold.allies=allies;
        var tag:String=f+"-"+a+"-"+(dense?"dense":"sparse");
        trace("HOTTEST COLD "+tag+" "+PlayerHudService.testOnlyUnitPacket(cold,1,false));
        for(var n:Number=1;n<=16;n++) {
            var nextFocus:Array=step(focus,dense,n);
            var nextAllies:Object={rows:step(allies.rows,dense,n),overflow:allies.overflow};
            var groups:Object={focusTarget:nextFocus};
            if(a>0) groups.allies=nextAllies;
            var start:Number=getTimer(), mid:Number, finish:Number, plain:String, hot:String, plainMs:Number, hotMs:Number;
            if(n%2==1) {
                plain=PlayerHudService.testOnlyUnitPacket(groups,n+1,false); mid=getTimer();
                hot=PlayerHudUnitHotWire.encode(1,n+1,groups,focus,allies); finish=getTimer();
                plainMs=mid-start; hotMs=finish-mid;
            } else {
                hot=PlayerHudUnitHotWire.encode(1,n+1,groups,focus,allies); mid=getTimer();
                plain=PlayerHudService.testOnlyUnitPacket(groups,n+1,false); finish=getTimer();
                hotMs=mid-start; plainMs=finish-mid;
            }
            if(hot==null || hot.charAt(0)!="~") return false;
            trace("HOTTEST DATA "+tag+" "+n+" "+plainMs+" "+hotMs+" "+plain+" "+hot);
            focus=nextFocus;allies=nextAllies;
        }
        var replacement:Array=focus.concat();
        replacement[0]={id:999,name:"新身份",role:"boss",icon:"",hp:[700,1000]};
        return PlayerHudUnitHotWire.encode(1,18,{focusTarget:replacement},focus,allies)==null
            && PlayerHudUnitHotWire.encode(1,18,{focusTarget:null},focus,allies)==null
            && PlayerHudUnitHotWire.encode(1,18,{vitals:{},focusTarget:focus},focus,allies)==null;
    }
    private static function mixedTail():Boolean {
        var old:Object = allyRows(1), next:Object = {rows:step(old.rows,false,1),overflow:[]};
        var encoded:String = PlayerHudUnitHotWire.encodeUnitsOnly(3,8,null,false,next,true,null,old);
        if (encoded != "~1,3,8;a,0,21,7,801,1000,31,60,0") return false;
        var row:Object = next.rows[0];
        var fields:Array = ["id","generation","slot","name","icon","role","doll","protected","compact"];
        for (var i:Number=0; i<fields.length; i++) {
            var key:String = fields[i], previous = row[key];
            row[key] = "changed";
            if (PlayerHudUnitHotWire.encodeUnitsOnly(3,8,null,false,next,true,null,old) != null) return false;
            row[key] = previous;
        }
        var focus:Array = focusRows(65);
        return PlayerHudUnitHotWire.encodeUnitsOnly(3,8,step(focus,true,1),true,null,false,focus,null) == null;
    }
    public static function runAllTests():Void { run(); }
    public static function run():Void {
        var ok:Boolean=measure(4,0,false) && mixedTail();
        ok=measure(4,0,true)&&ok;
        ok=measure(8,20,false)&&ok;
        ok=measure(8,20,true)&&ok;
        trace("HOTTEST FINISH "+(ok?"PASS":"FAIL"));
    }
}
