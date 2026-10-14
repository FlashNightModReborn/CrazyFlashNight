import org.flashNight.arki.bullet.BulletComponent.Chain.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.naki.DataStructures.Dictionary;

/** 非敌方标准霰弹：共享有限预算，单体能力遵循旧衰减参照。 */
class org.flashNight.arki.bullet.BulletComponent.Chain.ShotgunPattern {
    public static var MAX_AGE:Number = 180;
    public var age:Number;
    public var hitCap:Number;
    public var projectionBuilds:Number;
    public var reference:ChainGroup;
    private var contacts:Object;
    private var geometryAge:Number;
    private var invA:Number;
    private var invB:Number;
    private var invC:Number;
    private var invD:Number;
    private var worldA:Number;
    private var worldB:Number;
    private var worldC:Number;
    private var worldD:Number;
    private var invAbsA:Number;
    private var invAbsB:Number;
    private var invAbsC:Number;
    private var invAbsD:Number;
    private var worldAbsA:Number;
    private var worldAbsB:Number;
    private var worldAbsC:Number;
    private var worldAbsD:Number;
    private var originX:Number;
    private var originY:Number;

    public function ShotgunPattern() {
        age = 0;
        hitCap = 0;
        projectionBuilds = 0;
        geometryAge = -1;
        contacts = null;
        reference = null;
    }

    /** 横向组装时守门；穿刺、透明等特殊弹继续走原规则。 */
    public static function bind(group:ChainGroup):Void {
        #include "../macros/FLAG_PIERCE.as"
        #include "../macros/FLAG_TRANSPARENCY.as"
        #include "../macros/FLAG_MELEE.as"
        #include "../macros/FLAG_EXPLOSIVE.as"
        var b:Object = group.bullet;
        if (b.霰弹分配模式 == 1
            && (b.flags & (FLAG_PIERCE | FLAG_TRANSPARENCY | FLAG_MELEE | FLAG_EXPLOSIVE)) == 0) {
            group.shotgun = new ShotgunPattern();
        }
    }

    /** 复制出生时已采样的数据，不抽新随机数、不创建 MC、不注册视觉组。
     * 复用旧聚合器的衰减、触地、倒序删除与精确逐次加法，保留单体命中概率。
     * 实际弹丸不随参照衰减；不同目标仍分享出生预算。 */
    public function captureReference(group:ChainGroup):Void {
        var b:Object = group.bullet;
        var rb:Object = {霰弹值:b.霰弹值, 子弹散射度:b.子弹散射度,
            _x:b._x, _y:b._y, xmov:b.xmov, Z轴坐标:b.Z轴坐标};
        var r:ChainGroup = new ChainGroup(null, rb, null, null);
        r.isDecayReference = true;
        r.aggregate = true;
        r.运动方向系数 = group.运动方向系数;
        r.余弦值 = group.余弦值;
        r.衰竭计数器 = group.衰竭计数器;
        r.最小盒高 = group.最小盒高;
        r.盒x = group.盒x; r.盒y = group.盒y;
        r.盒宽 = group.盒宽; r.盒高 = group.盒高;
        var list:Array = group.单元体列表;
        var copies:Array = r.单元体列表;
        for (var i:Number = 0; i < list.length; i++) {
            var u:ChainUnitData = list[i];
            var copy:ChainUnitData = ChainUnitManager.acquireUnitData();
            copy.mc = null;
            copy.nativeLive = false; copy.nativeSent = false;
            copy.x = u.x; copy.y = u.y;
            copy.rot = u.rot; copy.sin = u.sin; copy.cos = u.cos;
            ChainUnitManager.initializeAggregateUnit(r, copy);
            copies[i] = copy;
        }
        ChainUnitManager.prepareHorizontalAggregate(r);
        reference = r;
    }

    /** 整组退场与清场均回收参照；不进入 MC 池或原生预留账本。 */
    public function dispose():Void {
        var r:ChainGroup = reference;
        if (r != null) {
            r.__removed = true;
            var list:Array = r.单元体列表;
            for (var i:Number = 0; i < list.length; i++) ChainUnitManager.releaseUnitData(list[i]);
            list.length = 0;
            r.aggregateRuns.length = 0; r.aggregateSorted.length = 0;
            r.aggregateMin = null; r.aggregateMax = null;
            reference = null;
        }
        contacts = null;
    }

    public static function hasBudget(bullet:Object):Boolean {
        var sc:Number = bullet.霰弹值;
        return sc < -65535 ? (((-sc) & 0xFFFF) > 0) : (sc > 0);
    }

    /** 暂停由统一 tick 守门；上限兜住停弹/特殊运动，不延长原射程。 */
    public function advance(group:ChainGroup):Boolean {
        age++;
        if (age > MAX_AGE || !hasBudget(group.bullet)) {
            ChainUnitManager.removeGroup(group);
            group.bullet.removeMovieClip();
            return false;
        }
        var r:ChainGroup = reference;
        var b:Object = group.bullet;
        var rb:Object = r.bullet;
        rb._x = b._x; rb._y = b._y;
        rb.xmov = b.xmov; rb.Z轴坐标 = b.Z轴坐标;
        rb.子弹散射度 = b.子弹散射度;
        // 参照 shotgun 恒为 null，复用旧生产更新，不递归推进新模式。
        _root.联弹系统.横向联弹更新(r);
        return true;
    }

    /** 在闪避、伤害和事件之前拒绝重复接触；只保存 dispatcher 数字身份。 */
    public function prepareContact(group:ChainGroup, target:Object, area:Object, zOffset:Number):Boolean {
        if (!hasBudget(group.bullet) || target.dispatcher == undefined) return false;
        var uid:Number = target.dispatcher.__dictUID;
        if (contacts != null && contacts[uid] === true) return false;
        hitCap = calculateCap(group, area, zOffset);
        if (!(hitCap > 0)) return false;
        if (contacts == null) contacts = {};
        if (uid === undefined) uid = Dictionary.getStaticUID(target.dispatcher);
        contacts[uid] = true;
        return true;
    }

    /** 四轴 SAT：世界 X/Y 与组本地 X/Y；无数组、角点或多边形分配。 */
    private function overlaps(box:ChainGroup, cx:Number, cy:Number, hw:Number, hh:Number,
                              lx:Number, rx:Number, ly:Number, ry:Number):Boolean {
        var x:Number = box.盒x, y:Number = box.盒y;
        var w:Number = box.盒宽, h:Number = box.盒高;
        if (!(lx + rx > x && lx - rx < x + w
            && ly + ry > y && ly - ry < y + h)) return false;
        var bx:Number = x + w * 0.5;
        var by:Number = y + h * 0.5;
        var dx:Number = cx - worldA * bx - worldC * by;
        var dy:Number = cy - worldB * bx - worldD * by;
        var wx:Number = (worldAbsA * w + worldAbsC * h) * 0.5 + hw;
        var wy:Number = (worldAbsB * w + worldAbsD * h) * 0.5 + hh;
        return dx < wx && dx > -wx && dy < wy && dy > -wy;
    }

    /** 每个实际更新步缓存一次逆矩阵。参照决定单体段数及是否有旧有效弹道；
     * 实际包围盒再守门，防止已经消耗/触地的弹丸产生接触。 */
    public function calculateCap(group:ChainGroup, area:Object, zOffset:Number):Number {
        if (geometryAge != age) {
            var frame:Number = _root.帧计时器.当前帧数;
            if (AABBCollider.zoneFrame != frame) AABBCollider.refreshChainZoneAffine(frame);
            var za:Number = AABBCollider.zoneA, zb:Number = AABBCollider.zoneB;
            var zc:Number = AABBCollider.zoneC, zd:Number = AABBCollider.zoneD;
            var a:Number = za * group.ma + zc * group.mb;
            var b:Number = zb * group.ma + zd * group.mb;
            var c:Number = za * group.mc2 + zc * group.md;
            var d:Number = zb * group.mc2 + zd * group.md;
            var det:Number = a * d - b * c;
            if (det == 0 || (det - det) != 0) return 0;
            invA = d / det; invB = -b / det; invC = -c / det; invD = a / det;
            worldA = a; worldB = b; worldC = c; worldD = d;
            invAbsA = invA < 0 ? -invA : invA; invAbsB = invB < 0 ? -invB : invB;
            invAbsC = invC < 0 ? -invC : invC; invAbsD = invD < 0 ? -invD : invD;
            worldAbsA = a < 0 ? -a : a; worldAbsB = b < 0 ? -b : b;
            worldAbsC = c < 0 ? -c : c; worldAbsD = d < 0 ? -d : d;
            var bullet:Object = group.bullet;
            originX = za * bullet._x + zc * bullet._y + AABBCollider.zoneTx;
            originY = zb * bullet._x + zd * bullet._y + AABBCollider.zoneTy;
            geometryAge = age;
            projectionBuilds++;
        }
        var cx:Number = (area.left + area.right) * 0.5 - originX;
        var cy:Number = (area.top + area.bottom) * 0.5 + zOffset - originY;
        var hw:Number = (area.right - area.left) * 0.5;
        var hh:Number = (area.bottom - area.top) * 0.5;
        var lx:Number = invA * cx + invC * cy;
        var rx:Number = invAbsA * hw + invAbsC * hh;
        var ly:Number = invB * cx + invD * cy;
        var ry:Number = invAbsB * hw + invAbsD * hh;
        if (!overlaps(group,cx,cy,hw,hh,lx,rx,ly,ry)) return 0;
        var r:ChainGroup = reference;
        if (r == null || !overlaps(r,cx,cy,hw,hh,lx,rx,ly,ry)) return 0;
        var count:Number = group.单元体列表.length;
        var cap:Number = r.bullet.霰弹值;
        return cap < count ? cap : count;
    }
}
