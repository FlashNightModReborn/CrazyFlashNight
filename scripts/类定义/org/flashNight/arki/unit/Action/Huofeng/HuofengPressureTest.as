import org.flashNight.arki.unit.Action.Huofeng.*;
import org.flashNight.arki.component.StatHandler.ImpactHandler;

/** Exact control-clock regressions plus ImpactHandler fed by real native hits.
 * Impact ledgers deliberately do not move/knock down the collision targets;
 * they compare identical settled primary damage, not human combat acceptance. */
class org.flashNight.arki.unit.Action.Huofeng.HuofengPressureTest {
    private static var caseId:Number,contacts:Number,primary:Number,expected:Number;
    private static var current:Object,previous:Object,clockPulses:Array;
    private static function ledger():Object {
        return {hp:10000000,防御力:1,韧性系数:100,躲闪率:10,remainingImpactForce:0};
    }
    public static function beginCase(id:Number):Void {
        caseId=id;contacts=primary=expected=0;current=ledger();previous=ledger();
    }
    public static function contact(kind:String,bullet:Object,damage:Number,check:Function):Void {
        if(kind!=="normal" && kind!=="run" && kind!=="spin" && caseId!=27 && caseId!=28)return;
        var rate:Number=bullet.击倒率;
        check(isFinite(damage) && damage>0 && isFinite(rate) && rate>0,"settled native hit has a finite positive impact denominator");
        if(!(damage>0) || !(rate>0) || !isFinite(rate))return;
        var oldRate:Number=kind==="normal" ? 50 : (kind==="run" || kind==="spin" ? 40 : rate);
        if(kind==="run" || kind==="spin")check(rate==10,"run/spin ordinary contacts retain native cold impact");
        ImpactHandler.settleImpactForce(damage,rate,current);
        ImpactHandler.settleImpactForce(damage,oldRate,previous);
        contacts++;primary+=damage;expected+=damage*50/rate;
    }
    public static function endCase(check:Function):Void {
        if(contacts<1)return;
        check(Math.abs(current.remainingImpactForce-expected)<.001,"real ImpactHandler accumulates settled primary damage once per contact");
        if(caseId<18 || caseId>=29)check(current.remainingImpactForce>=previous.remainingImpactForce*4-.001,"mace no longer divides the already-split impact budget again");
        trace("HuofengNativeTest Impact: case="+caseId+" contacts="+contacts+" primary="+primary+" current="+current.remainingImpactForce+" previous="+previous.remainingImpactForce+" ratio="+(current.remainingImpactForce/previous.remainingImpactForce));
    }
    private static function step(fixture:Object,n:Number):Void {
        _root.帧计时器.当前帧数=n;HuofengAction.tick(fixture.unit.man);
    }
    public static function repeatContract(make:Function,check:Function):Void {
        var emit:Function=HuofengCombat.emit,tryCancel:Function=HuofengInput.tryCancel;
        HuofengCombat.emit=function(u:MovieClip,a:Object):Void{HuofengPressureTest.clockPulses.push(_root.帧计时器.当前帧数);};
        HuofengInput.tryCancel=function():Boolean{return false;};
        var f:Object=make("normal",0);clockPulses=[];
        for(var i:Number=1;i<=82;i++){
            step(f,i);
            if(i>=71 && i<=74)check(f.unit.man.shown==[84,88,92,95][i-71],"held bridge samples authored return pose "+i);
        }
        check(clockPulses.length==31 && clockPulses[29]==70 && clockPulses[30]==82,"held fifth-to-first contacts are twelve frames apart");
        check(f.action.cycle==1 && f.action.stage==0 && f.action.frame==8 && !f.action.cancelled,"same owner restarts first stage without going idle");
        check(f.runtime.state.primaryReadyFrame==101,"new first stage owns its recovery gate");
        f.unit.removeMovieClip();

        f=make("normal",0);clockPulses=[];
        for(i=1;i<=74;i++){if(i==72)f.unit.动作A=false;step(f,i);}
        check(f.action.cancelled && f.unit.recovered && clockPulses.length==30,"release in short return never starts an unwanted next attack");
        check(f.runtime.state.primaryReadyFrame==74,"short return releases old primary cooldown without a hidden 95-frame wait");
        f.unit.removeMovieClip();

        f=make("normal",0);clockPulses=[];
        f.unit.跳=function():Void{this.jumped=true;};
        for(i=1;i<=72;i++){if(i==72)f.unit.动作B=true;step(f,i);}
        check(f.action.cancelled && f.unit.jumped && clockPulses.length==30,"jump interrupts the bridge before a new first stage");
        f.unit.removeMovieClip();

        f=make("normal",0);clockPulses=[];
        HuofengInput.tryCancel=function(u:MovieClip,a:Object):Boolean{
            if(_root.帧计时器.当前帧数!=72)return false;
            u.skillAccepted=true;HuofengAction.cancel(a.owner,a,false);return true;
        };
        for(i=1;i<=72;i++)step(f,i);
        check(f.action.cancelled && f.unit.skillAccepted && clockPulses.length==30,"accepted skill keeps priority over held repetition");
        f.unit.removeMovieClip();

        f=make("normal",0);clockPulses=[];
        HuofengInput.tryCancel=function(u:MovieClip,a:Object):Boolean{return _root.帧计时器.当前帧数>=72;};
        for(i=1;i<=74;i++)step(f,i);
        check(f.action.cancelled && f.unit.recovered,"rejected held skill cannot freeze short recovery");
        f.unit.removeMovieClip();

        f=make("normal",0);clockPulses=[];
        HuofengInput.tryCancel=function():Boolean{return false;};
        for(i=1;i<=71;i++)step(f,i);
        _root.暂停=true;step(f,72);
        check(f.action.recovery==2 && f.unit.man.shown==84,"pause freezes short return pose and clock");
        _root.暂停=false;step(f,73);step(f,73);
        check(f.action.recovery==3 && f.unit.man.shown==88,"resume advances once and duplicate callback cannot consume another pose");
        f.unit.攻击模式="兵器";step(f,74);
        check(f.action.cancelled && clockPulses.length==30,"weapon switch cancels held repetition before any new contact");
        f.unit.removeMovieClip();
        HuofengCombat.emit=emit;HuofengInput.tryCancel=tryCancel;
    }
}
