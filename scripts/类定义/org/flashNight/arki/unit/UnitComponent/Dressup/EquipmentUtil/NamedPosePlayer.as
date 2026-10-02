import flash.geom.Matrix;

/** 常驻单帧总装的完整姿态播放器；不决定攻击、耗弹或人物动作。 */
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.NamedPosePlayer {
    private var data:Object;
    private var rig:MovieClip;
    private var identity:Object;
    private var nodes:Array;
    private var transforms:Array;
    private var lastStates:Array;
    private var ammoNodes:Array;
    private var ammoDirty:Boolean;
    private var lastAmmo:Number;
    public var lastWriteCount:Number;

    public function NamedPosePlayer(source:Object) {
        data = source;
        nodes = []; transforms = []; lastStates = []; ammoNodes = [];
        lastAmmo = -1; ammoDirty = true; lastWriteCount = 0;
    }

    public function bind(target:MovieClip):Boolean {
        if (!target._parent) return false;
        if (rig === target && target.__namedPoseIdentity === identity && identity != undefined) return true;
        var nextNodes:Array = [];
        var nextTransforms:Array = [];
        var nextStates:Array = [];
        var nextAmmo:Array = [];
        var targets:Array = data.targets;
        for (var i:Number = 0; i < targets.length; i++) {
            var node:MovieClip = target[targets[i].name];
            if (typeof node != "movieclip") return false;
            nextNodes[i] = node;
            nextTransforms[i] = new Matrix();
            nextStates[i] = -2;
            if (targets[i].variants.ammo_live != undefined) {
                node.live._alpha = 100;
                node.spent._alpha = 100;
                nextAmmo.push(node);
            }
        }
        rig = target; identity = {};
        rig.__namedPoseIdentity = identity;
        nodes = nextNodes; transforms = nextTransforms; lastStates = nextStates; ammoNodes = nextAmmo;
        lastAmmo = -1; ammoDirty = true;
        return true;
    }

    public function applyPose(poseId:Number):Boolean {
        if (!rig._parent || rig.__namedPoseIdentity !== identity) return false;
        var pose:String = data.poses[poseId];
        if (!pose || pose.length != nodes.length) return false;
        var targets:Array = data.targets;
        lastWriteCount = 0;
        for (var i:Number = 0; i < nodes.length; i++) {
            var stateId:Number = pose.charCodeAt(i) - 1;
            if (lastStates[i] === stateId) continue;
            var state:String = data.states[stateId];
            var values:String = data.matrices[state.charCodeAt(1)-1];
            var pool:Array = data.numbers;
            var transform:Matrix = transforms[i];
            var node:MovieClip = nodes[i];
            transform.a = pool[values.charCodeAt(0)-1]; transform.b = pool[values.charCodeAt(1)-1];
            transform.c = pool[values.charCodeAt(2)-1]; transform.d = pool[values.charCodeAt(3)-1];
            transform.tx = pool[values.charCodeAt(4)-1]; transform.ty = pool[values.charCodeAt(5)-1];
            node.transform.matrix = transform;
            node._alpha = pool[state.charCodeAt(2)-1] * 100;
            var partIndex:Number = state.charCodeAt(0) - 2;
            node._visible = partIndex >= 0 && targets[i].kind != "anchor";
            if (targets[i].variants.ammo_live != undefined) {
                var part:String = data.parts[partIndex];
                node.live._visible = part == "ammo_live";
                node.spent._visible = part == "ammo_spent";
                ammoDirty = true;
            }
            lastStates[i] = stateId;
            lastWriteCount++;
        }
        return true;
    }

    /** 三窗口是剩余弹药的比例示意，真实容量和消耗由射击系统维护。 */
    public function setAmmo(liveSlots:Number):Void {
        if (liveSlots < 0) liveSlots = 0;
        if (liveSlots > 3) liveSlots = 3;
        if (!ammoDirty && lastAmmo === liveSlots) return;
        for (var i:Number = 0; i < ammoNodes.length; i++) {
            var node:MovieClip = ammoNodes[i];
            node.live._visible = i < liveSlots;
            node.spent._visible = i >= liveSlots;
        }
        lastAmmo = liveSlots; ammoDirty = false;
    }

    public function getAnchor(name:String):MovieClip {
        if (!rig._parent || rig.__namedPoseIdentity !== identity) return null;
        return rig[name];
    }

    /** 读取单件在指定完整姿态的矩阵，不推进显示与播放时钟。 */
    public function getTargetMatrix(name:String, poseId:Number):Matrix {
        var pose:String = data.poses[poseId];
        if (!pose) return null;
        for (var i:Number = 0; i < data.targets.length; i++) {
            if (data.targets[i].name != name) continue;
            var state:String = data.states[pose.charCodeAt(i)-1];
            if (state.charCodeAt(0) < 2) return null;
            var row:String = data.matrices[state.charCodeAt(1)-1];
            var pool:Array = data.numbers;
            return new Matrix(pool[row.charCodeAt(0)-1],pool[row.charCodeAt(1)-1],pool[row.charCodeAt(2)-1],
                pool[row.charCodeAt(3)-1],pool[row.charCodeAt(4)-1],pool[row.charCodeAt(5)-1]);
        }
        return null;
    }

    public function reset():Void {
        if (identity != undefined && rig.__namedPoseIdentity === identity) delete rig.__namedPoseIdentity;
        rig = null; identity = null;
        nodes = []; transforms = []; lastStates = []; ammoNodes = [];
        lastAmmo = -1; ammoDirty = true;
    }

    /** 在动作边界重排采样，保持首末与关键阶段；返回完整姿态直接索引。 */
    public static function composePath(source:Object, segments:Array, ticks:Number):Object {
        if (!source || !(segments instanceof Array) || segments.length == 0
                || isNaN(ticks) || !isFinite(ticks) || ticks < 2 || ticks != (ticks | 0)) return null;
        var allPoses:Array = [];
        var allClips:Array = [];
        var allFrames:Array = [];
        var required:Array = [0];
        var s:Number;
        var f:Number;
        for (s = 0; s < segments.length; s++) {
            var descriptor:Object = segments[s];
            var clip:Object = source.clips[descriptor.clip];
            if (!(clip.frames instanceof Array) || clip.frames.length == 0) return null;
            var from:Number = descriptor.from != undefined ? descriptor.from : 0;
            var to:Number = descriptor.to != undefined ? descriptor.to : clip.frames.length - 1;
            if (isNaN(from) || isNaN(to) || from < 0 || to < from || to > clip.frames.length - 1
                    || from != (from | 0) || to != (to | 0)) return null;
            var offset:Number = allPoses.length;
            for (f = from; f <= to; f++) {
                allPoses.push(clip.frames[f]);
                allClips.push(descriptor.clip);
                allFrames.push(f);
            }
            for (var m:Number = 0; m < clip.milestones.length; m++) {
                var milestone:Number = clip.milestones[m];
                if (milestone >= from && milestone <= to) required.push(offset + milestone - from);
            }
        }
        if (allPoses.length == 0) return null;
        var last:Number = allPoses.length - 1;
        required.push(last);
        required.sort(Array.NUMERIC);
        var chosen:Array = [];
        for (s = 0; s < required.length; s++) {
            if (s == 0 || required[s] != required[s - 1]) chosen.push(required[s]);
        }
        if (ticks < 2) ticks = 2;
        // 极短自定义预算时，优先移除静止或变化最少的中间采样，首末始终保留。
        while (chosen.length > ticks) {
            var removeIndex:Number = 1;
            var minimum:Number = 1000000;
            for (s = 1; s < chosen.length - 1; s++) {
                var before:String = source.poses[allPoses[chosen[s - 1]]];
                var current:String = source.poses[allPoses[chosen[s]]];
                var after:String = source.poses[allPoses[chosen[s + 1]]];
                var score:Number = 0;
                for (f = 0; f < current.length; f++) {
                    if (before.charCodeAt(f) != current.charCodeAt(f)) score++;
                    if (current.charCodeAt(f) != after.charCodeAt(f)) score++;
                }
                if (score < minimum) { minimum = score; removeIndex = s; }
            }
            chosen.splice(removeIndex, 1);
        }
        // 把剩余采样分给最长间隔，不逐帧重放前缀。
        while (chosen.length < ticks && chosen.length < allPoses.length) {
            var gapIndex:Number = -1;
            var gap:Number = 1;
            for (s = 0; s < chosen.length - 1; s++) {
                var candidate:Number = chosen[s + 1] - chosen[s];
                if (candidate > gap) { gap = candidate; gapIndex = s; }
            }
            if (gapIndex < 0) break;
            chosen.splice(gapIndex + 1, 0, chosen[gapIndex] + (gap >> 1));
        }
        var result:Object = {poses:[],clips:[],frames:[]};
        for (s = 0; s < ticks; s++) {
            var index:Number = chosen[s < chosen.length ? s : chosen.length - 1];
            result.poses.push(allPoses[index]);
            result.clips.push(allClips[index]);
            result.frames.push(allFrames[index]);
        }
        return result;
    }
}
