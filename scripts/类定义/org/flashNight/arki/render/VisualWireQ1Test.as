import org.flashNight.arki.render.*;

class org.flashNight.arki.render.VisualWireQ1Test {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean,label:String):Void {
        if(value)passed++;else{failed++;trace("[TEST_FAIL] VisualWireQ1Test: "+label);}
    }
    private static function packet():String {
        BulletVisualProbe.flush();FrameBroadcaster.send();
        return _root.server.last.substring(_root.server.last.indexOf("\x05")+1);
    }
    public static function runAllTests():Void {
        passed=0;failed=0;
        var oldWorld:MovieClip=_root.gameworld, oldServer:Object=_root.server, oldTimer:Object=_root.帧计时器;
        var server:Object={isSocketConnected:true,last:""};
        server.sendSocketMessage=function(message:String):Boolean {server.last=message;return true;};
        server.sendServerMessage=function(message:String):Void {};
        _root.server=server;_root.帧计时器={当前帧数:11};
        var world:MovieClip=_root.createEmptyMovieClip("__q1World",_root.getNextHighestDepth());_root.gameworld=world;
        VisualWireService.retire();BulletVisualProbe.resetScene();
        BulletVisualProbe.configure({version:1,mode:"native",maxOrdinary:1024,maxTotal:16384,
            styles:[{ordinaryLinkage:"ordinary",gunChainUnitLinkage:"unit"}],gunChainPrefixes:["纵向联弹"]});
        var bullet:MovieClip=world.createEmptyMovieClip("b",1);bullet.子弹种类="ordinary";bullet._x=10;bullet._y=20;
        BulletVisualProbe.registerNormal(bullet);
        var legacy:String=packet();check(legacy.indexOf("Q1")!=0,"no offer keeps legacy");
        var sent:Array=[];VisualWireService.setSenderForTests(function(wire:String):Void {sent.push(wire);});
        var token:String="0123456789abcdef0123456789abcdef";
        var offer:Object={task:"visual_wire_offer",version:1,token:token,offerId:1,
            channels:{f5:["q1","legacy"],scenePose:["legacy"]},f5Quant:{profile:"q64-safe-v1",allowed:false,
                denominator:64,absXY:8192,maxCameraScale:4,maxCameraOffset:8192,maxAbsScalePercent:400,maxCatalogRadius:128,maxOutputScale:4}};
        offer.f5Quant.denominator=32;VisualWireService.handle(offer);
        check(sent.length==0,"malformed known quant profile cannot activate a wire choice");offer.f5Quant.denominator=64;
        VisualWireService.handle(offer);
        check(sent.length==1 && sent[0].indexOf("visual_wire_select")>=0,"offer selects Q1-R");
        check(VisualWireService.f5OfferId()==0,"offer alone cannot activate producer");
        var commit:Object={task:"visual_wire_commit",version:1,token:token,offerId:1,
            channels:{f5:"q1",scenePose:"legacy"},f5QuantProfile:"none",qAllowed:false};
        VisualWireService.handle(commit);
        var first:String=packet();var header:Array=first.split(";")[0].split("|");
        check(first.indexOf("Q1|1|")==0,"actual broadcaster emits Q1");
        check(first.split(";")[1]=="0,10,20","exact defaults omitted");
        check(Number(header[6])==0 && Number(header[5])==1,"wire switch preserves live tracking");
        check(bullet.__nativeVisualOwned===true && bullet._alpha===0,"wire switch preserves native ownership");
        VisualWireService.handle(commit);var second:String=packet();var next:Array=second.split(";")[0].split("|");
        check(next[2]===header[2] && Number(next[3])==Number(header[3])+1,"duplicate commit does not reset epoch or sequence");
        check(next[4]===header[4],"snapshot sequence advances independently from source frame");
        bullet._xscale=-100;bullet._rotation=45;
        var mirror:String=packet().split(";")[1];check(mirror.split(",")[0]=="48","rotation and mirror presence bits");
        check(mirror.split(",")[3]=="45" && mirror.split(",")[4]=="-100","optional order and mirrored value preserved");
        bullet.removeMovieClip();var empty:String=packet();check(empty.split(";").length==1 && empty.split("|")[5]=="0","empty snapshot clears without trailing row");
        VisualWireService.retire();check(VisualWireService.f5OfferId()==0,"disconnect retires format selection");
        check(packet().indexOf("Q1")!=0,"retired connection returns to legacy until new offer");
        sent.length=0;offer.f5Quant.profile="future-profile";VisualWireService.handle(offer);
        check(sent.length==1 && sent[0].indexOf('"none"')>=0,"unknown quant profile still chooses raw R with quant none");
        VisualWireService.retire();
        VisualWireService.setSenderForTests(null);BulletVisualProbe.disconnect();BulletVisualProbe.resetScene();
        world.removeMovieClip();_root.gameworld=oldWorld;_root.server=oldServer;_root.帧计时器=oldTimer;
        trace("VisualWireQ1Test Tests Passed: "+passed);trace("VisualWireQ1Test Tests Failed: "+failed);
    }
}
