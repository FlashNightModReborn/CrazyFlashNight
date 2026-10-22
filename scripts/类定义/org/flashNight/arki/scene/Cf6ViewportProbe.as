import flash.display.*;
import flash.geom.*;
class org.flashNight.arki.scene.Cf6ViewportProbe {
 public static function start():Void {



_root.stop();
Stage.scaleMode="showAll";Stage.align="TL";
var diagnostic:BitmapData=new BitmapData(1,1,true,0xFF44AA77);
trace("CF6ViewportARGB raw="+diagnostic.getPixel32(0,0)+" rgb="+diagnostic.getPixel(0,0)+" alpha="+(diagnostic.getPixel32(0,0)>>>24)+" literal="+0xFF44AA77);
diagnostic.dispose();
_root.__cf6ViewportProbe={cases:[{id:"A05",width:2218.6667,height:767.8293,scale:1.7066666666666668,spawn:[2031.7013,394.9227],layers:[{role:"background",url:"file:///C:/Program%20Files%20%28x86%29/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/flashswf/backgrounds/cf6/CF6_A05_BG.swf",x:-19.2,y:-57.0027},{role:"foreground",url:"file:///C:/Program%20Files%20%28x86%29/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/flashswf/backgrounds/cf6/CF6_A05_foreground.swf",x:189.44,y:0.9387,width:2068.3947,height:305.0667},{role:"door-exit-sequence",url:"file:///C:/Program%20Files%20%28x86%29/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/flashswf/backgrounds/cf6/CF6_DoorGrand1750.swf",x:774.3147,y:5.0347,width:682.6667,height:477.8667}]},{id:"A06",width:2560.0,height:767.8293,scale:1.7066666666666668,spawn:[1439.488,697.5147],layers:[{role:"background",url:"file:///C:/Program%20Files%20%28x86%29/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/flashswf/backgrounds/cf6/CF6_A06_BG.swf",x:-5.888,y:-57.0027},{role:"screen-fixed",url:"file:///C:/Program%20Files%20%28x86%29/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/flashswf/backgrounds/cf6/CF6_A06_sky.swf",x:0,y:-20,width:800,height:187}]},{id:"A08",width:1962.6667,height:699.7333,scale:1.7066666666666668,spawn:[410.5387,457.8987],layers:[{role:"background",url:"file:///C:/Program%20Files%20%28x86%29/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/flashswf/backgrounds/cf6/CF6_A08_BG.swf",x:0.0,y:0.0}]}],index:-1,serial:0,auto:true,records:[],runId:"morning-a05-a06-a08-r6"};
_root.createTextField("__probeCaption",100,8,520,1008,54);
_root.__probeCaption.textColor=0xFFFFFF;
_root.__probeCaption.multiline=true;
_root.__probeCaption.setNewTextFormat(new TextFormat("_sans",14));

_root.__cf6ProbeAlign=function():Void {
    var s:Object=_root.__cf6ViewportProbe, c:Object=s.current;
    for(var i:Number=0;i<s.entries.length;i++) {
        var e:Object=s.entries[i], p:Object=e.spec;
        if(p.role=="city-parallax") {e.holder._x=s.world._x/2+p.x*c.scale;e.holder._y=s.world._y+p.y*c.scale;}
    }
};
_root.__cf6ProbeLoad=function(index:Number):Void {
    var s:Object=_root.__cf6ViewportProbe;
    s.serial++;
    for(var previous:Number=0;previous<s.entries.length;previous++) {
        var old:Object=s.entries[previous];old.loader.removeListener(old.listener);
        if(old.target._parent!=undefined) old.loader.unloadClip(old.target);
    }
    if(s.bitmap!=undefined) {s.bitmap.dispose();s.bitmap=undefined;}
    if(s.surface!=undefined) s.surface.removeMovieClip();
    s.surface=_root.createEmptyMovieClip("__probeSurface"+s.serial,1);
    s.rear=s.surface.createEmptyMovieClip("rear",0);s.world=s.surface.createEmptyMovieClip("world",1);
    s.index=index;s.current=s.cases[index];s.pending=0;s.wait=0;s.entries=[];s.measured=false;
    var c:Object=s.current;
    for(var i:Number=0;i<c.layers.length;i++) {
        var p:Object=c.layers[i],rear:Boolean=p.role=="screen-fixed" || p.role=="city-parallax";
        var parent:MovieClip=rear ? s.rear : s.world;
        var holder:MovieClip=parent.createEmptyMovieClip("layer"+i,p.role=="background" ? 10 : rear ? i : p.role=="elevator-scroll" ? 0 : 20+i);
        holder._x=p.x;holder._y=p.y;
        if(rear) {holder._x=p.x*c.scale;holder._y=p.y*c.scale;}
        var count:Number=p.role=="elevator-scroll" ? 2 : 1;
        for(var part:Number=0;part<count;part++) {
            var mc:MovieClip=holder.createEmptyMovieClip("art"+part,part);
            var e:Object={serial:s.serial,spec:p,holder:holder,target:mc,part:part,scale:rear && p.role=="screen-fixed" ? Math.max(c.scale,1024/p.width) : c.scale};
            if(p.clip!=undefined) {
                var mask:MovieClip=holder.createEmptyMovieClip("mask"+part,10+part),r:Array=p.clip;
                mask.beginFill(0xFFFFFF);mask.moveTo(r[0],r[1]);mask.lineTo(r[0]+r[2],r[1]);
                mask.lineTo(r[0]+r[2],r[1]+r[3]);mask.lineTo(r[0],r[1]+r[3]);mask.endFill();
                e.mask=mask;
            }
            var listener:Object={entry:e};
            listener.onLoadInit=function(target:MovieClip):Void {
                var entry:Object=this.entry,s:Object=_root.__cf6ViewportProbe;
                trace("CF6ViewportLoadInit serial="+entry.serial+" current="+s.serial+" same="+(target===entry.target)+" ready="+entry.ready+" pending="+s.pending);
                if(entry.serial!==s.serial || target!==entry.target || entry.ready===true) return;
                entry.ready=true;target._xscale=target._yscale=entry.scale*100;
                if(entry.part==1) target._y=entry.spec.loopHeight;
                if(entry.mask!=undefined) target.setMask(entry.mask);
                s.pending--;
                trace("CF6ViewportLoadReady map="+s.current.id+" pending="+s.pending);
            };
            listener.onLoadError=function(target:MovieClip,error:String):Void {
                var entry:Object=this.entry,s:Object=_root.__cf6ViewportProbe;
                if(entry.serial!==s.serial || target!==entry.target || entry.ready===true) return;
                trace("CF6ViewportCoverage LoadError: "+this.entry.spec.url+" "+error);
                _root.__probeCaption.text="LOAD ERROR: "+this.entry.spec.url;
                _root.__cf6ViewportProbe.auto=false;
            };
            e.loader=new MovieClipLoader();e.listener=listener;e.loader.addListener(listener);
            s.entries.push(e);s.pending++;e.loader.loadClip(p.url,mc);
        }
    }
    _root.__probeCaption.text="仅显示验证 / 未部署 / loading "+c.id;
};
_root.__cf6ProbeMeasure=function():Void {
    var s:Object=_root.__cf6ViewportProbe,c:Object=s.current;
    trace("CF6ViewportMeasureBegin map="+c.id+" ms="+getTimer());
    for(var entryIndex:Number=0;entryIndex<s.entries.length;entryIndex++) {
        var snapshot:Object=s.entries[entryIndex],visual:MovieClip=snapshot.target;
        trace("CF6ViewportLayer map="+c.id+" role="+snapshot.spec.role+" width="+visual._width+" height="+visual._height+" visible="+visual._visible+" alpha="+visual._alpha+" frame="+visual._currentframe+" total="+visual._totalframes);
    }
    var minX:Number=Math.ceil(1024-c.width),minY:Number=Math.ceil(512-c.height);
    var ex:Number=Math.round(Math.min(0,Math.max(minX,412-c.spawn[0])));
    var ey:Number=Math.round(Math.min(0,Math.max(minY,412-c.spawn[1])));
    var poses:Array=[[0,0],[minX,0],[0,minY],[minX,minY],[ex,ey]];
    var sample:BitmapData=new BitmapData(1024,512,true,0);
    for(var i:Number=0;i<poses.length;i++) {
        s.world._x=poses[i][0];s.world._y=poses[i][1];_root.__cf6ProbeAlign();
        trace("CF6ViewportDrawBegin map="+c.id+" pose="+i+" ms="+getTimer());
        sample.fillRect(sample.rectangle,0);sample.draw(s.surface);
        trace("CF6ViewportDrawEnd map="+c.id+" pose="+i+" ms="+getTimer());
        var edge:Number=0,grid:Number=0;
        for(var x:Number=2;x<1022;x+=8) {
            if((sample.getPixel32(x,2)>>>24)==0) edge++;
            if((sample.getPixel32(x,509)>>>24)==0) edge++;
        }
        for(var y:Number=2;y<510;y+=8) {
            if((sample.getPixel32(2,y)>>>24)==0) edge++;
            if((sample.getPixel32(1021,y)>>>24)==0) edge++;
        }
        for(y=8;y<512;y+=16) for(x=8;x<1024;x+=16) if((sample.getPixel32(x,y)>>>24)==0) grid++;
        trace("CF6ViewportCoverage "+s.runId+" map="+c.id+" pose="+i+" x="+poses[i][0]+" y="+poses[i][1]+" edgeMissing="+edge+" gridMissing="+grid);
    }
    sample.dispose();s.world._x=ex;s.world._y=ey;_root.__cf6ProbeAlign();
    _root.__probeCaption.text="仅显示验证 / 未部署 / "+c.id+"  地图倍率 "+c.scale+"  镜头 1\n1:A01  2:A02  3:A10  4:A13  方向键:查看边界";
    s.measured=true;s.wait=0;
};
_root.createEmptyMovieClip("__cf6ViewportProbeTick",99);
_root.__cf6ViewportProbeTick.onEnterFrame=function():Void {
    var s:Object=_root.__cf6ViewportProbe;
    if(s.ticks==undefined) s.ticks=0;
    if(++s.ticks%90==0) trace("CF6ViewportTick map="+s.current.id+" pending="+s.pending+" wait="+s.wait+" measured="+s.measured);
    if(s.pending!=0) return;
    if(!s.measured) {if(++s.wait>8) _root.__cf6ProbeMeasure();return;}
    if(!s.auto || ++s.wait<5) return;
    if(s.index+1<s.cases.length) {_root.__cf6ProbeLoad(s.index+1);return;}
    trace("CF6ViewportCoverage Complete: "+s.runId+" maps="+s.cases.length);
    s.auto=false;if(s.cases.length>1) _root.__cf6ProbeLoad(1);
};
_root.__probeKeys={};
_root.__probeKeys.onKeyDown=function():Void {
    var s:Object=_root.__cf6ViewportProbe,code:Number=Key.getCode();
    if(s.auto || s.pending!=0) return;
    var maps:Array=["A01","A02","A10","A13"];
    if(code>48 && code<53) {
        for(var i:Number=0;i<s.cases.length;i++) if(s.cases[i].id==maps[code-49]) {_root.__cf6ProbeLoad(i);return;}
    }
    if(code==37) s.world._x=0;
    if(code==39) s.world._x=Math.ceil(1024-s.current.width);
    if(code==38) s.world._y=0;
    if(code==40) s.world._y=Math.ceil(512-s.current.height);
    _root.__cf6ProbeAlign();
};
Key.addListener(_root.__probeKeys);
trace("CF6ViewportCoverage Start: morning-a05-a06-a08-r6");
_root.__cf6ProbeLoad(0);

 }
}
