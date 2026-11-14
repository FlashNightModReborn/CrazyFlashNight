import org.flashNight.arki.bullet.BulletComponent.Chain.ChainGroup;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBCollider;

/** 枪式横向齐射的实际弹群、首次接触和单目标额度。逐次查询复用本帧投影。 */
class org.flashNight.arki.bullet.BulletComponent.Chain.HorizontalShotCoverage {
    private static var NEAR:Number = 200;
    private static var FAR:Number = 240;
    public var targetLimit:Number, birthCount:Number, travel:Number;
    public var left:Number, right:Number, hitX:Number, hitY:Number;
    private var charge:Number, lastX:Number, lastY:Number, spreadAdvance:Number, tip:Number;
    private var frame:Number;
    public var x:Number, y:Number, oldX:Number, oldY:Number;
    private var valid:Boolean;
    public var forwardX:Number, forwardY:Number;
    private var normalX:Number, normalY:Number;
    private var bandLow:Number, bandHigh:Number, thickness:Number;
    private var sweepDX:Number, sweepDY:Number;
    private var top:Number, bottom:Number;

    public function HorizontalShotCoverage(g:ChainGroup) {
        birthCount = targetLimit = g.单元体列表.length;
        charge = g.衰竭计数器;
        lastX = g.bullet._x; lastY = g.bullet._y;
        travel = spreadAdvance = 0;
        frame = -1;
    }

    /** 沿用出生时的衰减曲线，折算为每目标额度。没有影子弹群或逐颗更新。 */
    public function advance(g:ChainGroup):Void {
        var b:Object = g.bullet;
        var dx:Number = b._x-lastX, dy:Number = b._y-lastY;
        travel += dy == 0 ? Math.abs(dx) : Math.sqrt(dx*dx+dy*dy);
        lastX = b._x; lastY = b._y;
        spreadAdvance += b.xmov*g.运动方向系数;
        if (targetLimit > 1) {
            charge += (targetLimit+b.子弹散射度)/25;
            // 与逐颗降至 limit < -charge 等价，包括正好碰到整数阈值的情况。
            targetLimit = Math.max(1, Math.min(targetLimit, Math.ceil(-charge)-1));
        }
    }

    /** 队列只用扩大后的窗口查询单位，消弹、地图与预警仍使用弹体本身的碰撞盒。 */
    public function sample(g:ChainGroup, box:Object):Void {
        var now:Number = _root.帧计时器.当前帧数;
        var b:Object = g.bullet;
        if (AABBCollider.zoneFrame != now) AABBCollider.refreshChainZoneAffine(now);
        var za:Number = AABBCollider.zoneA, zb:Number = AABBCollider.zoneB;
        var zc:Number = AABBCollider.zoneC, zd:Number = AABBCollider.zoneD;
        var nx:Number = za*b._x + zc*b._y + AABBCollider.zoneTx;
        var ny:Number = zb*b._x + zd*b._y + AABBCollider.zoneTy;
        var newFrame:Boolean = frame != now;
        if (newFrame) {
            oldX = frame == now-1 && valid ? x : nx;
            oldY = frame == now-1 && valid ? y : ny;
        }
        frame = now;
        x = nx; y = ny;
        sweepDX = x-oldX; sweepDY = y-oldY;
        var axisX:Number = za*g.ma+zc*g.mb, axisY:Number = zb*g.ma+zd*g.mb;
        var axisLen:Number = Math.sqrt(axisX*axisX+axisY*axisY);
        valid = axisLen > 0 && isFinite(axisLen) && isFinite(x+y);
        left = box.left; right = box.right; top = box.top; bottom = box.bottom;
        if (!valid) return;
        forwardX = axisX/axisLen; forwardY = axisY/axisLen;
        var vx:Number = za*b.xmov+zc*b.ymov, vy:Number = zb*b.xmov+zd*b.ymov;
        if (forwardX*vx + forwardY*vy < 0) { forwardX = -forwardX; forwardY = -forwardY; }
        normalX = -forwardY; normalY = forwardX;
        var normalScale:Number = (za*g.mc2+zc*g.md)*normalX + (zb*g.mc2+zd*g.md)*normalY;
        valid = normalScale != 0 && isFinite(normalScale);
        if (!valid) return;
        tip = g.盒宽 * axisLen * 0.5;
        var start:Number = g.盒y*normalScale;
        // 两端取弹心，厚度单独参与扫掠。
        var span:Number = Math.max(0,g.盒高-g.最小盒高);
        var end:Number = (g.盒y+span)*normalScale;
        bandLow = Math.min(start,end); bandHigh = Math.max(start,end);
        thickness = Math.abs(g.最小盒高*normalScale)*0.5;
        var supportX:Number = thickness*Math.abs(normalX), supportY:Number = thickness*Math.abs(normalY);
        left = Math.min(box.left, box.left-sweepDX) - supportX;
        right = Math.max(box.right, box.right-sweepDX) + supportX;
        top = Math.min(box.top, box.top-sweepDY) - supportY;
        bottom = Math.max(box.bottom, box.bottom-sweepDY) + supportY;
    }

    /** 返回本次实际扫掠对目标的覆盖。普通霰弹只结算一次，可以计入目标剩余宽度。 */
    public function contact(g:ChainGroup, box:Object, z:Number, projectExit:Boolean):Number {
        if (!valid || box.right <= left || box.left >= right || box.bottom+z <= top || box.top+z >= bottom) return 0;
        var hw:Number = (box.right-box.left)*0.5, hh:Number = (box.bottom-box.top)*0.5;
        var cx:Number = box.left+hw, cy:Number = box.top+hh+z;
        var fx:Number = forwardX, fy:Number = forwardY;
        var d:Number = (x-cx)*fx+(y-cy)*fy;
        var half:Number = Math.abs(fx)*hw+Math.abs(fy)*hh;
        var from:Number = d-sweepDX*fx-sweepDY*fy;
        var near:Number = -half, far:Number = half;
        var hi:Number = Math.min(far,d), lo:Number = Math.max(near,Math.min(from,d));
        if (Math.max(d,from)+tip <= near || Math.min(d,from)-tip >= far) return 0;
        // 截取这一步已经扫过的区间；沿当前截面的散射方向估算真正落在框里的弹丸。
        // 斜射还需按两个世界轴截取，防止外包矩形的空角获得判定。
        var patchLo:Number = Math.max(near, Math.min(from,d)-tip);
        var patchHi:Number = Math.min(far, Math.max(from,d)+tip);
        var axialMid:Number = 0.5*(patchLo+patchHi);
        var axialRadius:Number = 0.5*(patchHi-patchLo);
        var normalOrigin:Number = (cx-x)*normalX+(cy-y)*normalY;
        var radius:Number = Math.abs(normalX)*hw+Math.abs(normalY)*hh;
        var low:Number = normalOrigin-radius-thickness, high:Number = normalOrigin+radius+thickness;
        var ox:Number = x+d*(-fx)+axialMid*fx-cx;
        var oy:Number = y+d*(-fy)+axialMid*fy-cy;
        var bound:Number, n1:Number, n2:Number;
        if (Math.abs(normalX) > 0.00001) {
            bound = hw+axialRadius*Math.abs(fx);
            n1=(-bound-ox)/normalX; n2=(bound-ox)/normalX;
            low=Math.max(low,Math.min(n1,n2)-thickness); high=Math.min(high,Math.max(n1,n2)+thickness);
        }
        if (Math.abs(normalY) > 0.00001) {
            bound = hh+axialRadius*Math.abs(fy);
            n1=(-bound-oy)/normalY; n2=(bound-oy)/normalY;
            low=Math.max(low,Math.min(n1,n2)-thickness); high=Math.min(high,Math.max(n1,n2)+thickness);
        }
        var mid:Number = Math.max(near,Math.min(far,(lo+hi)*0.5));
        var step:Number = d-from;
        var t:Number = step > 0 ? Math.max(0,Math.min(1,(d-mid)/step)) : 0;
        if (!(low < high && high > bandLow && low < bandHigh)) return 0;
        var n:Number = g.单元体列表.length;
        if (n < 1) return 0;
        hitX = Math.max(box.left,Math.min(box.right,x-t*sweepDX));
        hitY = Math.max(box.top+z,Math.min(box.bottom+z,y-t*sweepDY));
        var cover:Number = n;
        if (bandHigh > bandLow && n > 1) {
            cover = countBetween(n,low,high);
            if (projectExit && travel < FAR && spreadAdvance != 0 && Math.abs(fy)<0.000001 && g.bullet.ymov==0) {
                // 目标只领一次普通霰弹。直射时把退出目标前仍能相交的轨迹投回本截面。
                var speed:Number = Math.abs(g.bullet.xmov);
                if (speed > 0) {
                    var endSpread:Number = spreadAdvance + Math.max(0,far-d+tip)/speed*g.bullet.xmov*g.运动方向系数;
                    if (endSpread*spreadAdvance > 0) {
                        var ratio:Number = spreadAdvance/endSpread;
                        cover = countBetween(n,Math.min(low,low*ratio),Math.max(high,high*ratio));
                    } else if (low < 0 && high > 0) {
                        cover = n;
                    } else {
                        var flip:Number = endSpread/spreadAdvance;
                        if (low >= 0) cover = countBetween(n,low,Infinity)+(flip < 0 ? countBetween(n,-Infinity,low/flip) : 0);
                        else cover = countBetween(n,-Infinity,high)+(flip < 0 ? countBetween(n,high/flip,Infinity) : 0);
                    }
                }
            }
        }
        // 有效覆盖的首次判定至少一段。衰减只对真实覆盖设置上限。
        cover = Math.max(1,Math.min(n,cover));
        if (travel > NEAR && cover > targetLimit)
            cover += (targetLimit-cover)*Math.min(1,(travel-NEAR)/(FAR-NEAR));
        return cover;
    }

    private function countBetween(n:Number,low:Number,high:Number):Number {
        if (high <= bandLow || low >= bandHigh) return 0;
        var overlap:Number = Math.min(high,bandHigh)-Math.max(low,bandLow);
        return (low<=bandLow ? 1 : 0)+(high>=bandHigh ? 1 : 0)+(n-2)*overlap/(bandHigh-bandLow);
    }
}
