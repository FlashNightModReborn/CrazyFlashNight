// SaveManager remains in this original RSL. Its SharedObject namespace is the
// importing main movie, exactly as before the compiler partition.
this._lockroot = false;
this.stop();
var moduleRoot:MovieClip = _root;
var previousModules:Object = moduleRoot.__asLoaderModules;
if (previousModules != undefined) {
    if (previousModules.root === moduleRoot && previousModules.phase == "ready"
            && moduleRoot.__boot == undefined) {
        moduleRoot.__boot = {};
        previousModules.boot.attachMovie("asLoader", "_definitions", previousModules.boot.getNextHighestDepth());
        this.removeMovieClip();
    } else {
        moduleRoot.加载内容文本.text = "代码模块未完成加载，请重新启动游戏。";
        trace("[asLoaderModules] duplicate_or_failed_boot");
    }
} else {
    if (moduleRoot.__boot == undefined) moduleRoot.__boot = {};
    var moduleUrl:String = String(moduleRoot._url).split("?")[0].split("#")[0];
    var moduleBase:String = moduleUrl.substr(0, moduleUrl.lastIndexOf("/") + 1);
    var modules:Object = {root:moduleRoot, shell:this, phase:"shared", started:getTimer(),
        urls:{shared:moduleBase + "scripts/asLoaderShared.swf", boot:moduleBase + "scripts/asLoaderLogic.swf"}};
    moduleRoot.__asLoaderModules = modules;
    // Install the game allocator before either module runs its static constructors.
    #include "../引擎/引擎_lsy_根层级分配.as"

    // Define the facade on the original resident timeline, then keep that timeline
    // alive at a dynamic root depth. Assigning its functions to a fresh empty MC
    // would leave their AVM1 baseClip on the disposable authored instance.
    if (_global.__cf7InputIsolationBootstrapV1 == undefined && moduleRoot.GameInput == undefined) {
        var inputOwnerDepth:Number = 65530;
        while (inputOwnerDepth > 32767 && moduleRoot.getInstanceAtDepth(inputOwnerDepth) != undefined) inputOwnerDepth--;
        if (inputOwnerDepth == 32767) inputOwnerDepth = moduleRoot.getNextHighestDepth();
        this.swapDepths(inputOwnerDepth);
        this._name = "__cf7InputOwnerMC";
        this._visible = false;
        modules.inputOwner = this;
        var nativeKeyIsDown:Function = Key.isDown;
        var inputCell:Object = {
            passiveActive: moduleRoot.cf7R1PassiveInput == "1",
            bound:false, gateOpen:false, cancelSerial:0, comboImportCount:0,
            lastCommandSeq:0, lastImportedCommandSeq:0, actorInc:0, moduleInc:0, configInc:0, atomSeq:0,
            neutralWords:[0, 0, 0, 0, 0, 0, 0, 0], noEdges:[], phaseTrace:[],
            pressSerial:0, actorPressFloor:0, keyPresses:[], keyReleases:[]
        };
        inputCell.snapshot = {systemFrame:0, inputFrameSeq:0, keyboardEpoch:0,
            words:inputCell.neutralWords, edges:inputCell.noEdges};
        inputCell.isPassiveBound = function():Boolean { return inputCell.bound === true; };
        inputCell.getKeyboardEpoch = function():Number { return inputCell.snapshot.keyboardEpoch; };
        inputCell.getCancelSerial = function():Number { return inputCell.cancelSerial; };
        inputCell.isInputAdmitted = function():Boolean {
            return inputCell.passiveActive !== true || (inputCell.bound === true && inputCell.gateOpen === true);
        };
        inputCell.isInputCurrent = function(epoch:Number, cancelVersion:Number, configVersion:Number):Boolean {
            return inputCell.isInputAdmitted() && epoch === inputCell.snapshot.keyboardEpoch
                && cancelVersion === inputCell.cancelSerial && configVersion === inputCell.configInc;
        };
        inputCell.clearKeyPresses = function():Void {
            inputCell.keyPresses.length = 0;
            inputCell.keyReleases.length = 0;
        };
        inputCell.recordKeyEdges = function(edges:Array):Void {
            for (var i:Number = 0; i < edges.length; ++i) {
                var edge:Object = edges[i];
                if (edge.down) {
                    inputCell.keyPresses[edge.vk] = ++inputCell.pressSerial;
                } else {
                    inputCell.keyReleases[edge.vk] = inputCell.keyPresses[edge.vk];
                    inputCell.keyPresses[edge.vk] = 0;
                }
            }
        };
        inputCell.getKeyPress = function(vk:Number):Number {
            return inputCell.isInputAdmitted() ? (inputCell.keyPresses[vk] || 0) : 0;
        };
        inputCell.isCurrentActor = function(unit:Object):Boolean {
            return unit != null && inputCell.actorIdentity != null && unit.__cf7InputIdentity === inputCell.actorIdentity
                && moduleRoot.gameworld[moduleRoot.控制目标] === unit;
        };
        inputCell.getActorPress = function(unit:Object, vk:Number):Number {
            var press:Number = inputCell.getKeyPress(vk);
            return press > inputCell.actorPressFloor && inputCell.isCurrentActor(unit) ? press : 0;
        };
        inputCell.getRecentActorPress = function(unit:Object, vk:Number):Number {
            if (!inputCell.isInputAdmitted() || !inputCell.isCurrentActor(unit)) return 0;
            var press:Number = inputCell.keyPresses[vk] || inputCell.keyReleases[vk] || 0;
            return press > inputCell.actorPressFloor ? press : 0;
        };
        inputCell.wasActorPressReleased = function(unit:Object, vk:Number, press:Number):Boolean {
            return press > inputCell.actorPressFloor && inputCell.isCurrentActor(unit)
                && inputCell.isInputAdmitted() && inputCell.keyReleases[vk] === press;
        };
        inputCell.hasKeyDownEdge = function(vk:Number):Boolean {
            var edges:Array = inputCell.snapshot.edges;
            if (!inputCell.isInputAdmitted() || inputCell.reboundSystemFrame === inputCell.snapshot.systemFrame)
                return false;
            for (var i:Number = edges.length - 1; i >= 0; --i) {
                if (edges[i].vk === vk && edges[i].down) return true;
            }
            return false;
        };
        inputCell.getAdmittedEdgeCount = function():Number { return inputCell.snapshot.edges.length; };
        inputCell.getAdmittedEdge = function(index:Number):Object {
            var edge:Object = inputCell.snapshot.edges[index];
            return edge == null ? null : {seq:edge.seq, vk:edge.vk, down:edge.down};
        };
        inputCell.recordPhase = function(phase:String, systemFrame:Number):Void {
            var at:Number = systemFrame & 63;
            var phases:Array = inputCell.phaseTrace;
            var row:Object = phases[at];
            if (row == null || row.systemFrame !== systemFrame) {
                row = {systemFrame:systemFrame};
                phases[at] = row;
            }
            var snapshot:Object = inputCell.snapshot;
            row[phase] = {systemFrame:snapshot.systemFrame, inputFrameSeq:snapshot.inputFrameSeq,
                keyboardEpoch:snapshot.keyboardEpoch};
        };
        var keyFacade:Function = function(vk:Number):Boolean {
            // The native query is only reachable before this VM enters passive mode.
            if (inputCell.passiveActive !== true && inputCell.bound !== true) return nativeKeyIsDown(vk);
            if (vk !== (vk | 0) || vk < 0 || vk > 255) return false;
            var words:Array = inputCell.snapshot.words;
            return ((words[vk >>> 5] >>> (vk & 31)) & 1) !== 0;
        };
        ASSetPropFlags(Key, ["isDown"], 0, 7);
        Key.isDown = keyFacade;
        ASSetPropFlags(Key, ["isDown"], 7, 0);
        inputCell.facadeInstalled = Key.isDown === keyFacade;
        moduleRoot.GameInput = inputCell;
    }
    // Depth 65531 sits immediately below system managers (65532..65535) and well above
    // dynamic game layers (1024..32767), avoiding early-boot depth 0 collisions.
    modules.holder = moduleRoot.createEmptyMovieClip("__asLoaderCode", 65531);
    modules.holder._visible = false;
    modules.shared = modules.holder.createEmptyMovieClip("shared", 1);
    modules.boot = modules.holder.createEmptyMovieClip("boot", 2);
    modules.loader = new MovieClipLoader();
    modules.listener = {state:modules};
    modules.fail = function(state:Object, error:String):Void {
        if (state.root.__asLoaderModules !== state || state.phase == "failed") return;
        state.phase = "failed";
        clearInterval(state.timer);
        state.error = error;
        state.root.__boot.bootFailed = "module_load_failed";
        state.root.__boot.moduleLoadError = error;
        state.root.加载内容文本.text = "代码模块加载失败，请重新启动游戏。";
        trace("[asLoaderModules] failed=" + error);
    };
    // Callback authority lives on a plain object. A loaded clip can retarget;
    // neither its fields nor a removed shell's timeline variables own the load.
    modules.listener.onLoadError = function(target:MovieClip, error:String, status:Number):Void {
        var state:Object = this.state;
        if (state.root.__asLoaderModules !== state || state.phase == "ready" || state.phase == "failed") return;
        if ((state.phase == "shared" && target !== state.shared)
                || (state.phase == "boot" && target !== state.boot)) return;
        state.fail(state, state.phase + ":" + error + ":" + status);
    };
    modules.listener.onLoadInit = function(target:MovieClip):Void {
        var state:Object = this.state;
        if (state.root.__asLoaderModules !== state) return;
        target._lockroot = false;
        if (state.phase == "shared" && target === state.shared) {
            state.phase = "boot";
            state.started = getTimer();
            if (!state.loader.loadClip(state.urls.boot, state.boot)) state.fail(state, "boot:rejected");
        } else if (state.phase == "boot" && target === state.boot) {
            state.phase = "ready";
            clearInterval(state.timer);
            trace("[asLoaderModules] ready");
            // The resident facade and code clips survive the boot handoff.
            if (state.shell !== state.inputOwner) state.shell.removeMovieClip();
        }
    };
    modules.loader.addListener(modules.listener);
    modules.timer = setInterval(function(state:Object):Void {
        if (state.root.__asLoaderModules !== state) {clearInterval(state.timer); return;}
        if ((state.phase == "shared" || state.phase == "boot") && getTimer() - state.started > 60000)
            state.fail(state, state.phase + ":timeout");
    }, 250, modules);
    moduleRoot.加载内容文本.text = "加载游戏代码……";
    if (!modules.loader.loadClip(modules.urls.shared, modules.shared)) modules.fail(modules, "shared:rejected");
}
