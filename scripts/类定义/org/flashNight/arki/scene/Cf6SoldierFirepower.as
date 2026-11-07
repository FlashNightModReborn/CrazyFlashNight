import org.flashNight.gesh.object.ObjectUtil;

/** Actor-only gun budgets, rebuilt with normal firearm templates; no per-shot solve. */
class org.flashNight.arki.scene.Cf6SoldierFirepower {
    private static var necklace:Array=[0.06,0.10,0.14];
    private static var physicalCap:Array=[0.20,0.28,0.35];
    private static var magicCap:Array=[0.05,0.08,0.10];
    private static function index(slot:String):Number {
        return slot=="长枪"?0:slot=="手枪"?1:slot=="手枪2"?2:-1;
    }
    private static function selected(unit:Object,slot:String):Array {
        var p:Object=unit.cf6FirepowerProfile,i:Number=index(slot);
        if(typeof unit.cf6UnitIdentity!="string" || p.v!==1 || i<0 || p.s===0)return null;
        var cfg:Array=p.g[i],weapon:Object=unit[slot];
        if(!(cfg instanceof Array) || cfg.length!=6 || cfg[2]===0 || weapon.name!==cfg[0]
            || weapon.value.level!==cfg[5] || (weapon.value.tier || null)!==cfg[1])return null;
        return cfg;
    }
    public static function calculate(unit:Object,slot:String,W:Number,M:Number,K:Number,isRay:Boolean,isLong:Boolean):Number {
        var base:Number=W*(1+M)+K,cfg:Array=selected(unit,slot);
        if(cfg==null || isRay || !(W>0) || !isFinite(base) || !(base>0))return base;
        var p:Object=unit.cf6FirepowerProfile,cls:Number=p.c,q:Number=p.q,level:Number=Number(unit.等级);
        if(!(cls>=0 && cls<3) || !(q>0 && q<=1) || !isFinite(level))return base;
        var caches:Object=p.cache;
        if(caches==null){caches={};p.cache=caches;}
        var c:Object=caches[slot];
        if(c==null){c={};caches[slot]=c;}
        var old:Object=unit.被动技能.枪械攻击;
        var oldEnabled:Boolean=!!old.启用,oldLevel:Number=oldEnabled?Number(old.等级 || 0):0;
        if(c.W===W && c.M===M && c.K===K && c.level===level && c.stage===p.s
            && c.oldEnabled===oldEnabled && c.oldLevel===oldLevel && c.isLong===isLong)return c.power;
        var cap:Number=physicalCap[cls]*q,skill:Number=p.s===2?Number(cfg[3]):0,nano:Number=p.s===2?Number(cfg[4]):0;
        if(cfg[2]===2){q*=0.25;cap=Math.min(cap,magicCap[cls]);skill=0;nano=0;}
        var g:Number=q*Math.max(0,Math.min(120,4*level-120)),n:Number=q*necklace[cls],u:Number=0,k:Number=0,totalCap:Number=cap;
        if(skill>0){
            var requested:Number=isLong?0.5+0.03*skill:0.015*skill;
            var existing:Number=oldEnabled?(isLong?0.5+0.03*oldLevel:0.015*oldLevel):0;
            u=Math.max(0,requested-existing);k=oldEnabled?0:(isLong?30:20);
            totalCap=(isLong?0.75:0.45)*p.q;
            if(W*(1+M+u)+K+k>base*(1+totalCap)){skill=0;u=0;k=0;totalCap=cap;}
        }
        // Fixed Nano source consumes the SAME envelope; production shield gates remain.
        var floorPower:Number=W*(1+M+u)+K+k,ceiling:Number=base*(1+totalCap);
        nano=Math.max(0,Math.min(nano,Math.floor(0.025*(ceiling-floorPower)+0.000000001)));
        ceiling-=nano/0.025;
        var alpha:Number=1;
        if((W+g)*(1+M+n+u)+K+k>ceiling){
            var a:Number=g*n,b:Number=g*(1+M+u)+W*n,constant:Number=floorPower-ceiling;
            alpha=a>0?(-2*constant)/(b+Math.sqrt(Math.max(0,b*b-4*a*constant))):(b>0?-constant/b:0);
            alpha=Math.max(0,Math.min(1,alpha));
        }
        c.W=W;c.M=M;c.K=K;c.level=level;c.stage=p.s;c.oldEnabled=oldEnabled;c.oldLevel=oldLevel;c.isLong=isLong;
        c.baseline=base;c.alpha=alpha;c.skill=skill;c.nano=nano;c.cap=totalCap;c.growth=alpha*g;c.necklace=alpha*n;
        c.power=Math.min(ceiling,(W+alpha*g)*(1+M+alpha*n+u)+K+k);
        return c.power;
    }
    public static function applyPoison(unit:Object,slot:String,props:Object):Void {
        var cfg:Array=selected(unit,slot);
        if(cfg==null || cfg[2]!==1)return;
        var c:Object=unit.cf6FirepowerProfile.cache[slot];
        if(c.nano>0)props.毒=Math.max(Number(props.毒)||0,c.nano);
    }
}
