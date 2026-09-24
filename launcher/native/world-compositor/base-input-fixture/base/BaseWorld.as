stop();
Stage.scaleMode = "showAll";
Stage.align = "TL";
var denyIntact:Boolean = SharedObject.getLocal === _global.__b1DenySharedObject;
if (denyIntact) {
    var world:MovieClip = _root.attachMovie("基地场景-医务室", "gameworld", 1);
    var actor:MovieClip = world.attachMovie("主角-男", "b1Actor", 10);
    actor._x = 420; actor._y = 430;
    var sceneAttached:Boolean = world != undefined;
    var actorAttached:Boolean = actor != undefined;
    var hasRealRootInitializer:Boolean = typeof _root.初始化玩家模板 == "function";
    _global.__b1Emit('{"kind":"B1_REAL_ASSET_ATTACHMENT","storageDenialIntact":true,"sceneAttached":' + sceneAttached + ',"actorAttached":' + actorAttached + ',"hasRootInitializer":' + hasRealRootInitializer + ',"actorReady":false,"inputGranted":false}');
} else {
    _global.__b1Emit('{"kind":"B1_REAL_ASSET_ATTACHMENT","storageDenialIntact":false,"actorReady":false,"inputGranted":false}');
}
