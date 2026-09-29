// Test-only original Flash renderer oracle. No game, save, Host or network commands.
// XML data is read from the same production file used by the game's bullet loader.
// The board survives completion so screenshots can be taken without timing a burst.
_root.__rayReference = {
    passed:0, failed:0, completed:false, sourceAttempt:0,
    sourceUrls:["../data/items/bullets_cases.xml", "data/items/bullets_cases.xml"],
    cases:[
        {id:"bagua_age0", bullet:"镇暴射线", age:0, key:"1"},
        {id:"bagua_age4", bullet:"镇暴射线", age:4, key:"2"},
        {id:"bagua_age8", bullet:"镇暴射线", age:8, key:"3"},
        {id:"bagua_fade11", bullet:"镇暴射线", age:11, key:"4"},
        {id:"tesla_age0", bullet:"磁暴射线-强化", age:0, key:"5"},
        {id:"tesla_age2", bullet:"磁暴射线-强化", age:2, key:"6"},
        {id:"resonance_age0", bullet:"谐振波射线-强化", age:0, key:"7"},
        {id:"resonance_age2", bullet:"谐振波射线-强化", age:2, key:"8"},
        {id:"tesla_basic_age2", bullet:"磁暴射线", age:2, key:"9"},
        {id:"flame_field", bullet:"喷火束", age:12, key:"F", continuous:true},
        {id:"thermal_field", bullet:"热能射线", age:2, key:"T"},
        {id:"thermal_enhanced_field", bullet:"热能射线-强化", age:2, key:"H"},
        {id:"prism_field", bullet:"光棱射线-强化", age:2, key:"P"}
    ]
};
_root.__rayReference.check = function(value:Boolean, name:String):Void {
    if (value) this.passed++;
    else { this.failed++; trace("[TEST_FAIL] RayReference: " + name); }
};
_root.__rayReference.label = function(parent:MovieClip, name:String, textValue:String,
        x:Number, y:Number, width:Number, size:Number, color:Number):Void {
    parent.createTextField(name, parent.getNextHighestDepth(), x, y, width, 28);
    var tf:TextField = parent[name];
    tf.selectable = false;
    tf.text = textValue;
    tf.setTextFormat(new TextFormat("_sans", size, color));
};
_root.__rayReference.child = function(node:XMLNode, wanted:String):XMLNode {
    for (var i:Number = 0; i < node.childNodes.length; i++) {
        var candidate:XMLNode = node.childNodes[i];
        if (candidate.nodeName == wanted) return candidate;
    }
    return null;
};
_root.__rayReference.describe = function(value:Object):String {
    var keys:Array = [];
    for (var key:String in value) {
        if (typeof value[key] != "function" && value[key] != undefined) keys.push(key);
    }
    keys.sort();
    var result:String = "";
    for (var i:Number = 0; i < keys.length; i++) {
        if (i > 0) result += "|";
        var entry = value[keys[i]];
        result += keys[i] + "=" + ((entry instanceof Array) ? entry.join(":") : String(entry));
    }
    return result;
};
_root.__rayReference.meta = function(sample:Object, frame:Number):Object {
    var kind:String = sample.cfg.rayMode.indexOf("pierce") >= 0 ? "pierce" : "main";
    var result:Object = {segmentKind:kind, hitIndex:0, intensity:1,
        isHit:false, hitPoints:null, damageHitPoints:null};
    if (sample.continuous) {
        var pulse:Number = Math.floor(Math.max(0, frame - 1) / 2) % 5;
        result.segmentKind = "flame";
        result.flameVfxKey = "reference:flame";
        result.flameVfxSerial = 1;
        result.targetLength = sample.cfg.rayLength;
        result.pulseIndex = pulse;
        result.pulseCount = 5;
        result.isHotPulse = pulse == 1 || pulse == 2;
        result.isDamagePulse = frame % 2 == 1;
        result.isBlocked = false;
        result.shotSeed = 271828;
    }
    return result;
};
_root.__rayReference.caps = function():Object {
    var names:Array = RayStyleRegistry.getStyleNames();
    var styles:Array = [];
    for (var i:Number = 0; i < names.length; i++) styles.push({index:i, id:names[i]});
    return {version:1, generation:1, native:true, styles:styles, maxArcs:1024, drawLimit:4096, configLimit:1024, lightingVersion:1, channelVersion:1};
};
_root.__rayReference.emitWire = function(sample:Object):Void {
    // reset before disconnect discards test visuals instead of restoring them into the board.
    RayVfxManager.reset();
    RayVisualBridge.disconnect();
    RayVfxManager.initWithContainer(this.bridgeWorld);
    RayVisualBridge.configure(this.caps());
    SceneCoordinateManager.effectOffset.setTo(0, 0);
    _root.暂停 = false;
    trace("[RAY_GPU_SCENE] " + sample.id);
    if (sample.continuous) {
        for (var frame:Number = 1; frame <= sample.age; frame++) {
            this.check(RayVisualBridge.trySpawn(60, 288, 60 + sample.cfg.rayLength, 288,
                sample.cfg, this.meta(sample, frame)), sample.id + " native continuous admission " + frame);
            trace("[RAY_GPU_WIRE] " + RayVisualBridge.flush());
        }
    } else {
        this.check(RayVisualBridge.trySpawn(60, 288, 60 + sample.cfg.rayLength, 288,
            sample.cfg, this.meta(sample, 0)), sample.id + " native admission");
        // An age-zero frame is represented by the real paused-clock path, never by editing F7.
        _root.暂停 = true;
        trace("[RAY_GPU_WIRE] " + RayVisualBridge.flush());
        _root.暂停 = false;
        for (var tick:Number = 1; tick <= sample.age; tick++) {
            trace("[RAY_GPU_WIRE] " + RayVisualBridge.flush());
        }
    }
    this.check(RayVisualBridge.getStats().active == 1, sample.id + " one final native visual");
    this.check(RayVisualBridge.getStats().tick == sample.age, sample.id + " exact production game tick");
};
_root.__rayReference.renderOriginal = function(sample:Object, index:Number):Void {
    this.rng = new SeededLinearCongruentialEngine(271828 + index * 997);
    var mc:MovieClip = this.board.createEmptyMovieClip("original" + index, 100 + index);
    mc.blendMode = "add";
    sample.mc = mc;
    var arc:Object = {startX:60, startY:288, endX:60 + sample.cfg.rayLength, endY:288,
        config:sample.cfg, meta:this.meta(sample, 0), vfxStyle:sample.cfg.vfxStyle, age:0, phaseAge:0};
    // Original createArc draws age zero, with no manager flicker applied until the first update.
    RayVfxManager.resetPools();
    RayStyleRegistry.renderArc(sample.cfg.vfxStyle, arc, 0, mc);
    for (var frame:Number = 1; frame <= sample.age; frame++) {
        arc.age = sample.continuous ? 1 : frame;
        arc.phaseAge = frame;
        arc.meta = this.meta(sample, frame);
        if (arc.age <= sample.cfg.visualDuration) {
            mc.clear();
            RayVfxManager.resetPools();
            RayStyleRegistry.renderArc(sample.cfg.vfxStyle, arc, 0, mc);
            mc._alpha = sample.cfg.flickerEnabled
                ? sample.cfg.flickerMin + VisualRandom.nextFloat() * (sample.cfg.flickerMax - sample.cfg.flickerMin)
                : 100;
        } else {
            // Production RVM does not redraw during fade. Keep the last hold-frame geometry.
            mc._alpha = 100 * (1 - (arc.age - sample.cfg.visualDuration) / sample.cfg.fadeOutDuration);
        }
    }
    this.check(mc._width > 0 && mc._height > 0, sample.id + " original renderer produced geometry");
    if (sample.id == "bagua_fade11") this.check(mc._alpha == 50, "Bagua age11 retains age9 geometry at half alpha");
    trace("[RAY_REFERENCE_ORIGINAL] scene=" + sample.id + "|age=" + sample.age
        + "|drawAge=" + (sample.continuous ? 1 : Math.min(sample.age, sample.cfg.visualDuration))
        + "|alpha=" + mc._alpha + "|lod=0|rngSeed=" + (271828 + index * 997)
        + "|bounds=" + mc._width + ":" + mc._height);
};
_root.__rayReference.show = function(index:Number):Void {
    this.selected = index;
    for (var i:Number = 0; i < this.cases.length; i++) {
        var sample:Object = this.cases[i];
        sample.mc._visible = false;
        sample.mc._xscale = sample.mc._yscale = 100;
        sample.mc._x = sample.mc._y = 0;
    }
    this.overviewLabels._visible = index < 0;
    if (index < 0) {
        var rowOrder:Array = [4, 5, 8, 6, 7];
        for (var row:Number = 0; row < rowOrder.length; row++) {
            var rowMc:MovieClip = this.cases[rowOrder[row]].mc;
            rowMc._visible = true;
            rowMc._y = 121 + row * 57 - 288;
        }
        for (var col:Number = 0; col < 4; col++) {
            var baguaMc:MovieClip = this.cases[col].mc;
            baguaMc._visible = true;
            baguaMc._xscale = baguaMc._yscale = 65;
            baguaMc._x = 40 + col * 250 - 60 * 0.65;
            baguaMc._y = 471 - 288 * 0.65;
        }
        this.board.detail.text = "Overview: source beam lengths retained; Bagua thumbnails 65%. Select a case for the matching F7 view.";
    } else {
        var current:Object = this.cases[index];
        current.mc._visible = true;
        var viewScale:Number = Math.min(1, 900 / current.cfg.rayLength);
        current.mc._xscale = current.mc._yscale = viewScale * 100;
        current.mc._x = 60 * (1 - viewScale);
        current.mc._y = 288 * (1 - viewScale);
        this.board.detail.text = current.id + " / " + current.bullet + " / L=" + current.cfg.rayLength
            + " / width=" + current.cfg.thickness + " / age=" + current.age
            + " / LOD0 / viewScale=" + viewScale;
    }
    trace("[RAY_REFERENCE_VIEW] index=" + index + "|scene="
        + (index < 0 ? "overview" : this.cases[index].id) + "|stage=" + Stage.width + ":" + Stage.height
        + "|boardScale=" + this.board._xscale / 100);
};
_root.__rayReference.onResize = function():Void {
    var state:Object = _root.__rayReference;
    var fit:Number = Math.min(Stage.width / 1024, Stage.height / 576);
    state.board._xscale = state.board._yscale = fit * 100;
    trace("[RAY_REFERENCE_VIEWPORT] stage=" + Stage.width + ":" + Stage.height
        + "|logical=1024:576|boardScale=" + fit);
};
_root.__rayReference.onKeyDown = function():Void {
    var state:Object = _root.__rayReference;
    var letter:String = String.fromCharCode(Key.getAscii()).toUpperCase();
    if (letter == "0") { state.show(-1); return; }
    for (var i:Number = 0; i < state.cases.length; i++) {
        if (letter == state.cases[i].key) { state.show(i); return; }
    }
};
_root.__rayReference.finish = function():Void {
    if (this.completed) return;
    this.completed = true;
    delete this.watch.onEnterFrame;
    RayVfxManager.reset();
    RayVisualBridge.disconnect();
    this.bridgeWorld.removeMovieClip();
    _root.暂停 = this.oldPause;
    SceneCoordinateManager.effectOffset.setTo(this.oldOffsetX, this.oldOffsetY);
    trace("RayReference Tests Passed: " + this.passed);
    trace("RayReference Tests Failed: " + this.failed);
    trace("[RAY_REFERENCE_READY] cases=" + this.cases.length + "|source=" + this.sourceUrl
        + "|originalRenderer=true|bodyOnly=true|logical=1024:576");
    trace("FocusedTestRunId ray-reference Complete: " + _root.__rayReferenceRunId);
    // Intentionally retain board/Key/Stage listeners. No cleanup destroys the evidence panel.
};
_root.__rayReference.loaded = function(ok:Boolean, document:XML):Void {
    if (this.completed) return;
    if (!ok) {
        this.sourceAttempt++;
        if (this.sourceAttempt < this.sourceUrls.length) { this.loadSource(); return; }
        this.check(false, "production XML could not be loaded");
        this.finish();
        return;
    }
    trace("[RAY_REFERENCE_SOURCE] " + this.sourceUrl);
    var rootNode:XMLNode = document.firstChild;
    var entries:Object = {};
    for (var i:Number = 0; i < rootNode.childNodes.length; i++) {
        var bulletNode:XMLNode = rootNode.childNodes[i];
        if (bulletNode.nodeName != "bullet") continue;
        var nameNode:XMLNode = this.child(bulletNode, "name");
        var attributeNode:XMLNode = this.child(bulletNode, "attribute");
        var configNode:XMLNode = this.child(attributeNode, "rayConfig");
        if (configNode == null) continue;
        var raw:Object = {};
        for (var j:Number = 0; j < configNode.childNodes.length; j++) {
            var field:XMLNode = configNode.childNodes[j];
            if (field.nodeType == 1) raw[field.nodeName] = field.firstChild.nodeValue;
        }
        entries[String(nameNode.firstChild.nodeValue)] = raw;
    }
    this.savedVisualNext = VisualRandom.nextFloat;
    this.visualNext = function():Number { return _root.__rayReference.rng.nextFloat(); };
    VisualRandom.nextFloat = this.visualNext;
    this.check(VisualRandom.nextFloat === this.visualNext, "isolated presentation RNG fixture installed");
    this.savedMathRandom = Math.random;
    this.mathCalls = 0;
    this.mathProbe = function():Number { _root.__rayReference.mathCalls++; return 0.5; };
    Math.random = this.mathProbe;
    this.mathWasReadOnly = Math.random !== this.mathProbe;
    if (this.mathWasReadOnly) {
        _global.ASSetPropFlags(Math, "random", 0, 4);
        Math.random = this.mathProbe;
    }
    this.check(Math.random === this.mathProbe, "game RNG consumption probe installed");
    var allPresent:Boolean = true;
    for (var c:Number = 0; c < this.cases.length; c++) {
        var sample:Object = this.cases[c];
        var source:Object = entries[sample.bullet];
        this.check(source != undefined, sample.id + " production XML bullet exists");
        if (source == undefined) { allPresent = false; continue; }
        sample.cfg = TeslaRayConfig.fromXML(source);
        this.check(sample.cfg.rayLength == Number(source.rayLength), sample.id + " full XML ray length retained");
        var overview:String = "null";
        if (c < 4) overview = "{\"x\":" + (40 + c * 250) + ",\"y\":471,\"scale\":0.65}";
        var order:Array = [4, 5, 8, 6, 7];
        for (var row:Number = 0; row < order.length; row++) {
            if (order[row] == c) overview = "{\"x\":60,\"y\":" + (121 + row * 57) + ",\"scale\":1}";
        }
        trace("[RAY_REFERENCE_CASE] {\"scene\":\"" + sample.id + "\",\"bullet\":\"" + sample.bullet
            + "\",\"style\":\"" + sample.cfg.vfxStyle + "\",\"age\":" + (sample.continuous ? 1 : sample.age)
            + ",\"phaseAge\":" + sample.age + ",\"start\":{\"x\":60,\"y\":288},\"end\":{\"x\":"
            + (60 + sample.cfg.rayLength) + ",\"y\":288},\"length\":" + sample.cfg.rayLength
            + ",\"width\":" + sample.cfg.thickness + ",\"lod\":0,\"isHit\":false,\"overview\":" + overview
            + ",\"singleViewScale\":" + Math.min(1, 900 / sample.cfg.rayLength) + "}");
        trace("[RAY_REFERENCE_XML] scene=" + sample.id + "|" + this.describe(source));
        trace("[RAY_REFERENCE_CONFIG] scene=" + sample.id + "|" + this.describe(sample.cfg));
        this.emitWire(sample);
        this.renderOriginal(sample, c);
    }
    Math.random = this.savedMathRandom;
    if (this.mathWasReadOnly) _global.ASSetPropFlags(Math, "random", 4, 0);
    VisualRandom.nextFloat = this.savedVisualNext;
    this.check(this.mathCalls == 0, "XML, original renderer and native bridge consume no gameplay RNG");
    if (allPresent) {
        this.show(-1);
        Stage.addListener(this);
        Key.addListener(this);
        this.onResize();
    }
    this.finish();
};
_root.__rayReference.loadSource = function():Void {
    this.sourceUrl = this.sourceUrls[this.sourceAttempt];
    this.document = new XML();
    this.document.ignoreWhite = true;
    this.document.onLoad = function(ok:Boolean):Void { _root.__rayReference.loaded(ok, this); };
    this.document.load(this.sourceUrl);
};

_root.__rayReference.oldPause = _root.暂停;
_root.__rayReference.oldOffsetX = SceneCoordinateManager.effectOffset.x;
_root.__rayReference.oldOffsetY = SceneCoordinateManager.effectOffset.y;
_root._quality = "HIGH";
Stage.scaleMode = "noScale";
Stage.align = "TL";
RayVfxManager.reset();
RayVisualBridge.disconnect();
_root.__rayReference.bridgeWorld = _root.createEmptyMovieClip("rayReferenceBridgeWorld", 78120);
_root.__rayReference.bridgeWorld._visible = false;
_root.__rayReference.board = _root.createEmptyMovieClip("rayReferenceBoard", 78121);
var __rrBoard:MovieClip = _root.__rayReference.board;
__rrBoard.beginFill(0x000000, 100);
__rrBoard.moveTo(0, 0); __rrBoard.lineTo(1024, 0); __rrBoard.lineTo(1024, 576);
__rrBoard.lineTo(0, 576); __rrBoard.lineTo(0, 0); __rrBoard.endFill();
_root.__rayReference.label(__rrBoard, "title", "AS2 original ray reference / production XML / LOD 0", 16, 6, 980, 17, 0xE8EAF0);
_root.__rayReference.label(__rrBoard, "detail", "Loading production bullet XML...", 16, 548, 996, 12, 0xA8BACB);
_root.__rayReference.overviewLabels = __rrBoard.createEmptyMovieClip("overviewLabels", 300);
for (var __rrI:Number = 0; __rrI < _root.__rayReference.cases.length + 1; __rrI++) {
    var __rrChoice:Object = _root.__rayReference.cases[__rrI - 1];
    var __rrButton:MovieClip = __rrBoard.createEmptyMovieClip("choose" + __rrI, 400 + __rrI);
    __rrButton.caseIndex = __rrI - 1;
    __rrButton._x = 16 + (__rrI % 7) * 142;
    __rrButton._y = 36 + Math.floor(__rrI / 7) * 28;
    __rrButton.beginFill(0x263444, 100);
    __rrButton.moveTo(0, 0); __rrButton.lineTo(137, 0); __rrButton.lineTo(137, 24);
    __rrButton.lineTo(0, 24); __rrButton.lineTo(0, 0); __rrButton.endFill();
    _root.__rayReference.label(__rrButton, "caption", __rrI == 0 ? "0 overview"
        : __rrChoice.key + " " + __rrChoice.id, 3, 2, 132, 10, 0xE0E8F0);
    __rrButton.onRelease = function():Void {
        if (_root.__rayReference.completed && _root.__rayReference.failed == 0) {
            _root.__rayReference.show(this.caseIndex);
        }
    };
}
var __rrRows:Array = [4, 5, 8, 6, 7];
for (var __rrRow:Number = 0; __rrRow < __rrRows.length; __rrRow++) {
    var __rrRowCase:Object = _root.__rayReference.cases[__rrRows[__rrRow]];
    _root.__rayReference.label(_root.__rayReference.overviewLabels, "row" + __rrRow,
        __rrRowCase.id + " / " + __rrRowCase.bullet, 60, 94 + __rrRow * 57, 850, 12, 0x8696A8);
}
for (var __rrCol:Number = 0; __rrCol < 4; __rrCol++) {
    _root.__rayReference.label(_root.__rayReference.overviewLabels, "bagua" + __rrCol,
        _root.__rayReference.cases[__rrCol].id + " / 65%", 40 + __rrCol * 250, 522, 230, 12, 0xA8BACB);
}
_root.__rayReference.onResize();
_root.__rayReference.watch = _root.createEmptyMovieClip("rayReferenceWatch", 78122);
_root.__rayReference.started = getTimer();
_root.__rayReference.watch.onEnterFrame = function():Void {
    var state:Object = _root.__rayReference;
    if (!state.completed && getTimer() - state.started > 25000) {
        state.check(false, "bounded XML reference load timed out");
        state.finish();
    }
};
_root.__rayReference.loadSource();
