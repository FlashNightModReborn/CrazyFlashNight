import flash.display.BitmapData;
import flash.geom.Matrix;

/** Native RSL timelines and real attack callbacks. Only the final projectile is intercepted. */
class org.flashNight.arki.unit.Action.Melee.Cf6InstructorMeleeTest {
    private static var world:MovieClip,driver:MovieClip;
    private static var cases:Array,review:Array;
    private static var ticks:Number,passed:Number,failed:Number,pose:Number,stage:Number;

    private static function check(ok:Boolean,label:String):Void {
        if(ok)passed++;else {failed++;trace("[TEST_FAIL] Instructor melee: "+label);}
    }
    public static function runAllTests():Void {
        ticks=passed=failed=pose=stage=0;cases=[];review=[];
        org.flashNight.arki.unit.Action.Melee.Cf6SoldierAssetTest.prepareWorld(prepared);
    }
    private static function prepared(mc:MovieClip):Void {
        world=mc;world._x=45;world._y=31;world._xscale=117;world._yscale=112;
        check(org.flashNight.arki.unit.Action.Melee.Cf6SoldierAssetTest.preparationFailures()==0,"shared equipment and world loaded");
        _root.子弹区域shoot传递=emitted;
        for(var side:Number=0;side<2;side++){
            spawn("A","敌人-CF6特种教官",side,false,34,14,34);
            spawn("B","敌人-CF6持盾特种教官",side,true,93,51,93);
            spawn("shieldKnife","敌人-CF6持盾特种教官",side,false,93,14,34);
            spawn("cancelA","敌人-CF6特种教官",side,false,34,14,34);
            spawn("cancelB","敌人-CF6持盾特种教官",side,true,93,51,93);
            spawn("soldier","敌人-CF6特种兵",side,false,34,14,34);
            spawn("soldierShield","敌人-CF6持盾特种兵",side,true,93,51,93);
            spawn("elite","敌人-CF6特种精英",side,false,0,0,0);
        }
        driver=_root.createEmptyMovieClip("instructorMeleeDriver",_root.getNextHighestDepth());
        driver.onEnterFrame=function():Void {Cf6InstructorMeleeTest.tick();};
    }
    private static function spawn(mode:String,link:String,side:Number,bash:Boolean,total:Number,hit:Number,end:Number):Void {
        var c:Object={mode:mode,side:side,bash:bash,total:total,hit:hit,end:end,hits:0,done:0,endFrames:[],cancelled:false};
        c.first=bash?35:1;c.key=mode+"/"+side;c.interrupt=mode=="cancelA" || mode=="cancelB";
        var init:Object={fixtureRecord:c,fixtureTacticalModern:true,长枪:"M4A1战术版",手枪:"FR506",手枪2:"FR506"};
        c.u=world.attachMovie(link,"instructorMelee"+cases.length,world.getNextHighestDepth(),init);
        check(c.u!=null,"attach "+c.key);cases.push(c);
        if(side==0 && (mode=="A" || mode=="B"))review.push(c);
    }
    private static function emitted(data:Object):MovieClip {
        var u:MovieClip=world[data.发射者],c:Object=u.fixtureRecord;
        check(data.子弹种类=="近战子弹","only requested melee emits "+c.key);
        if(data.子弹种类!="近战子弹")return world;
        c.hits++;
        var body:MovieClip=u.man,area:MovieClip=data.区域定位area;
        check(body._currentframe==c.hit && c.hits==1 && !c.interrupt,"single emission at authored frame "+c.key+" got "+body._currentframe);
        check(area!=null && area===body.攻击点.area,"live helper belongs to active body "+c.key);
        var origin:Object={x:0,y:0};area._parent.localToGlobal(origin);
        var screenBounds:Object=area.getBounds(_root),local:Object=area.getBounds(u),bounds:Object=area.getBounds(world);
        world.globalToLocal(origin);
        check(isFinite(origin.x) && isFinite(origin.y) && Math.abs(origin.x-data.shootX)<0.25 && Math.abs(origin.y-data.shootY)<0.25
            && data.shootZ==u.Z轴坐标,"projectile uses marker in world space "+c.key);
        check(isFinite(bounds.xMin) && bounds.xMax>bounds.xMin && bounds.yMax>bounds.yMin && screenBounds.xMax>screenBounds.xMin,
            "live world and screen bounds "+c.key);
        check(data.子弹威力==(c.bash?60:100) && data.水平击退速度==(c.bash?24:2) && data.斩杀==(c.bash?0:5),"melee payload "+c.key);
        if(c.mode=="A" || c.mode=="B"){
            var witness:Object={x:c.bash?60:85,y:c.bash?-80:-75};
            u.localToGlobal(witness);
            check(area.hitTest(witness.x,witness.y,true),"authored blade or shield contact in screen space "+c.key);
            var outside:Object={x:110,y:c.bash?-80:-75};u.localToGlobal(outside);
            check(!area.hitTest(outside.x,outside.y,true),"same-height point beyond blade or shield stays clear "+c.key);
            var worldPoint:Object={x:witness.x,y:witness.y};world.globalToLocal(worldPoint);
            check(worldPoint.x>=bounds.xMin && worldPoint.x<=bounds.xMax && worldPoint.y>=bounds.yMin && worldPoint.y<=bounds.yMax
                && (worldPoint.x-u._x)*(c.side==0?1:-1)>0,"contact lies forward in world space "+c.key);
        }
        c.localBounds={xMin:local.xMin,yMin:local.yMin,xMax:local.xMax,yMax:local.yMax};
        trace("[INSTRUCTOR_MELEE_HIT] "+c.key+" frame="+body._currentframe+" world="+data.shootX+","+data.shootY+" bounds="+bounds.xMin+","+bounds.yMin+","+bounds.xMax+","+bounds.yMax);
        return world;
    }
    private static function tick():Void {
        ticks++;_root.帧计时器.当前帧数=ticks;
        for(var i:Number=0;i<cases.length;i++){
            var c:Object=cases[i],u:MovieClip=c.u;
            if(ticks==7){
                u.方向改变(c.side==0?"右":"左");
                c.finish=u.soldierFinishAttack;
                u.soldierFinishAttack=function(body:MovieClip):Void {
                    var rc:Object=this.fixtureRecord;
                    rc.endFrames.push(body._currentframe);
                    rc.finish.call(this,body);
                };
                u.soldierMeleeKind=c.bash?"bash":"knife";u.状态改变("近战");
                continue;
            }
            if(ticks<8)continue;
            if(u.状态=="近战" && c.mode!="elite"){
                var f:Number=u.man._currentframe;
                if(!c.seen)c.firstSeen=f;
                else if(!c.interrupt && (f<c.lastSeen || f>c.lastSeen+1))check(false,"sequence skips local poses "+c.key+" "+c.lastSeen+" -> "+f);
                c.lastSeen=f;
                c.seen=true;
                check(u.man._totalframes==c.total,"runtime length "+c.key);
                if(f==c.hit-1){c.windup=true;check(c.hits==0 && u.man.攻击点.area==null,"no early contact "+c.key);}
                if(c.interrupt && !c.cancelled && f>=c.first+4){
                    c.cancelled=true;u.状态改变("长枪站立");
                }
            }
        }
        if(ticks<115)return;
        for(var j:Number=0;j<cases.length;j++){
            var row:Object=cases[j],actor:MovieClip=row.u;
            if(row.interrupt || row.mode=="elite"){
                check(row.hits==0 && row.endFrames.length==0 && (!row.interrupt || row.cancelled),"cancelled or denied attack emits nothing "+row.key);
            }else{
                check(row.seen && row.firstSeen<=row.first+1 && row.lastSeen>=row.end-1 && row.windup
                    && row.hits==1 && row.done==1 && row.endFrames.length==1 && row.endFrames[0]==row.end,
                    "one natural recovery on final authored frame "+row.key+" ends="+row.endFrames+" hits="+row.hits+" done="+row.done);
                check(actor.soldierAttackOwner==null && actor.状态=="长枪站立","released attack owner and returned to idle "+row.key);
            }
        }
        if(typeof _root.cf6CaptureEndpoint!="string"){finish();return;}
        trace("[SOLDIER_CAPTURE_PROTOCOL] region-rle-v2");
        trace("[INSTRUCTOR_MELEE_REVIEW] 93");
        for(var n:Number=0;n<review.length;n++){
            var actorReview:MovieClip=review[n].u;
            actorReview.soldierDriver.removeMovieClip();
            var noop:Function=function():Void {};
            actorReview.行走=noop;actorReview.动画完毕=noop;actorReview.soldierTick=noop;
            actorReview.soldierBeginMelee=noop;actorReview.soldierBeginAttack=noop;actorReview.soldierMeleeHit=noop;
            actorReview.soldierStab=noop;actorReview.soldierFinishAttack=noop;
            actorReview.状态="近战";
            actorReview.gotoAndStop(review[n].bash?"持盾近战":"近战");
        }
        driver.onEnterFrame=function():Void {Cf6InstructorMeleeTest.reviewTick();};
    }
    private static function reviewTick():Void {
        if(pose==93){
            if(_root.cf6CapturePending>0 && _root.cf6CaptureWait++<300)return;
            check(_root.cf6CapturePending==0 && _root.cf6CaptureErrors==0,"every submitted pose acknowledged");
            finish();return;
        }
        var c:Object=review[pose<34?0:1],u:MovieClip=c.u;
        var frame:Number=pose+1,localFrame:Number=frame-(c.bash?34:0);
        if(stage==0){u.man.gotoAndStop(frame);stage=1;return;}
        check(u.man._currentframe==frame,"published review body at "+c.mode+"/"+frame);
        if(u.man.腰挂!=null)u.man.腰挂.syncHolsters();
        var bd:BitmapData=new BitmapData(400,300,true,0xffe8e6e2);
        var factor:Number=1.35,x:Number=175,y:Number=257;
        var info:Boolean=u.人物文字信息._visible;u.人物文字信息._visible=false;
        bd.draw(u,new Matrix(factor,0,0,factor,x,y));u.人物文字信息._visible=info;
        if(frame==c.hit){
            var helper:MovieClip=u.man.攻击点.area;
            var shown:Object=helper.getBounds(u),live:Object=c.localBounds;
            check(helper!=null && shown.xMax>shown.xMin && shown.yMax>shown.yMin,"published contact-frame geometry "+c.key);
            check(Math.abs(shown.xMin-live.xMin)<0.25 && Math.abs(shown.yMin-live.yMin)<0.25
                && Math.abs(shown.xMax-live.xMax)<0.25 && Math.abs(shown.yMax-live.yMax)<0.25,"review after registration matches original live emission "+c.key);
            var left:Number=Math.round(x+factor*shown.xMin),top:Number=Math.round(y+factor*shown.yMin);
            var right:Number=Math.round(x+factor*shown.xMax),bottom:Number=Math.round(y+factor*shown.yMax);
            check(left>=0 && top>=0 && right<bd.width && bottom<bd.height && right>left && bottom>top,"projected bounds fit capture "+c.key);
            trace("[INSTRUCTOR_MELEE_OVERLAY] instructor-"+c.mode+"-"+localFrame+" "+left+" "+top+" "+right+" "+bottom);
        }
        var pixels:Number=0;
        for(var py:Number=0;py<bd.height;py+=3)for(var px:Number=0;px<bd.width;px+=3)
            if(bd.getPixel(px,py)!=0xe8e6e2)pixels++;
        var key:String="instructor-"+c.mode+"-"+localFrame;
        check(pixels>100,"visible published actor "+key);
        trace("[SOLDIER_NATIVE_PIXELS] "+key+" "+pixels);
        org.flashNight.arki.unit.Action.Melee.Cf6SoldierAssetTest.writeNativeCapture(bd,key);
        bd.dispose();pose++;stage=0;
    }
    private static function finish():Void {
        delete driver.onEnterFrame;
        trace("Cf6InstructorMeleeTest: "+passed+" passed, "+failed+" failed; "+cases.length+" actual timeline cases");
        _root.instructorMeleeComplete();
    }
}
