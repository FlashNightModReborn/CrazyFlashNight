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
            // Loaded code clips persist for the AVM1 lifetime. Only the small
            // public RSL instance is retired; the boot host owns its own handoff.
            state.shell.removeMovieClip();
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
