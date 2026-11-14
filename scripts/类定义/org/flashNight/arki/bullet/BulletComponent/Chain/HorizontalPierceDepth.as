import org.flashNight.arki.bullet.BulletComponent.Chain.ChainGroup;
import org.flashNight.arki.bullet.BulletComponent.Chain.HorizontalShotCoverage;
import org.flashNight.naki.DataStructures.Dictionary;

/** 单个目标内首次覆盖和新增穿深的段数。普通穿刺与次级穿刺共用该账本。 */
class org.flashNight.arki.bullet.BulletComponent.Chain.HorizontalPierceDepth {
    public static var EFFICIENCY:Number = 0.9;
    private static var WIDTH:Number = 55.93986512;
    public var efficiency:Number;
    public var segments:Number;
    private var ledger:Object;

    public function HorizontalPierceDepth() {
        efficiency = EFFICIENCY;
        ledger = {};
    }

    public function prepare(g:ChainGroup,unit:Object,box:Object,z:Number):Boolean {
        segments = 0;
        var s:HorizontalShotCoverage = g.shotCoverage;
        var cover:Number = s.contact(g,box,z,false);
        if (!(cover > 0)) return false;
        var fx:Number=s.forwardX, fy:Number=s.forwardY;
        var x:Number=s.x, y:Number=s.y, oldX:Number=s.oldX, oldY:Number=s.oldY;
        var hw:Number=(box.right-box.left)*0.5, hh:Number=(box.bottom-box.top)*0.5;
        var cx:Number=box.left+hw, cy:Number=box.top+hh+z;
        var owner:Object = unit.dispatcher != null ? unit.dispatcher : unit;
        var id:Number = owner.__dictUID;
        if (id === undefined) id = Dictionary.getStaticUID(owner);
        var state:Object = ledger[id];
        if (state == undefined) {
            // 固定该目标首次入射的方向；追踪转向不能用新轴反复重置穿深。
            state = ledger[id] = {fx:fx,fy:fy,depth:0,logDepth:0,coverage:0,remainder:0};
        }
        var ux:Number = state.fx, uy:Number = state.fy;
        var extent:Number = Math.abs(ux)*hw+Math.abs(uy)*hh;
        var depth:Number = Math.min(2*extent, Math.max(0,(x-cx)*ux+(y-cy)*uy+extent));
        // 首次接触只领取从本次步长进入后实际走过的部分（目标在弹心生成亦适用）。
        if (state.coverage == 0) {
            var startDepth:Number = Math.min(depth,Math.max(0,(oldX-cx)*ux+(oldY-cy)*uy+extent));
            state.depth = startDepth; state.origin = startDepth;
        }
        var credit:Number = state.remainder;
        if (cover > state.coverage) {
            credit += cover-state.coverage;
            state.coverage = cover;
        }
        // 只奖励子弹自身前进形成的新深度。停弹、目标位移和重复扫过都不追加。
        var advance:Number=(x-oldX)*ux+(y-oldY)*uy;
        if (depth > state.depth && advance > 0.000001) {
            var logDepth:Number = Math.log(1+(depth-state.origin)/WIDTH)*1.4426950408889634;
            credit += efficiency*cover*(logDepth-state.logDepth);
            state.depth = depth; state.logDepth = logDepth;
        }
        segments = Math.floor(credit+0.0000001);
        state.remainder = Math.max(0,credit-segments);
        if (segments <= 0) return false;
        return true;
    }
}
