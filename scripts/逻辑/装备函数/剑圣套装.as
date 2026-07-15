/** 剑圣五件套共享 context 与 gated 资源登记 helper。 */

_root.装备生命周期函数.剑圣装甲套装准备 = function(effect:Object, target:MovieClip):Object {
    return {
        target:target,
        frameStamp:0,
        placementChannels:{},
        attachments:[],
        attachmentPrecleanupRegistered:false
    };
};

_root.装备生命周期函数.剑圣装甲套装预计算周期 = function(effect:Object, context:Object):Void {
    context.frameStamp++;

    // placement 负责引用重建后的即时校正；同一肢体在动作时间轴内部仍会逐帧运动，
    // 因此预计算任务每帧对每个共享引用只采样一次，再由多个组件消费缓存。
    for (var referenceName:String in context.placementChannels) {
        var channel:Object = context.placementChannels[referenceName];
        var current:MovieClip = context.target[referenceName];
        if (current && current._parent) {
            _root.装备生命周期函数.剑圣套装刷新就位通道(context, channel, false);
        }
    }
};

/**
 * 将肢体局部基向量缓存到 target 本地坐标系，并同步唤醒所有消费者。
 * target-local 缓存可同时服务 target 与 target.底层背景中的挂件。
 */
_root.装备生命周期函数.剑圣套装刷新就位通道 = function(
    context:Object, channel:Object, notifyConsumers:Boolean):Boolean {
    var target:MovieClip = context.target;
    var source:MovieClip = target[channel.referenceName];
    if (!source || !source._parent) return false;

    var p0:Object = channel.targetP0;
    var pX:Object = channel.targetPX;
    var pY:Object = channel.targetPY;
    p0.x = 0; p0.y = 0;
    pX.x = 100; pX.y = 0;
    pY.x = 0; pY.y = 100;
    source.localToGlobal(p0);
    source.localToGlobal(pX);
    source.localToGlobal(pY);
    target.globalToLocal(p0);
    target.globalToLocal(pX);
    target.globalToLocal(pY);

    channel.source = source;
    channel.ready = true;
    channel.epoch++;

    if (notifyConsumers !== false) {
        for (var i:Number = 0; i < channel.consumers.length; i++) {
            var consumer:Object = channel.consumers[i];
            if (consumer && consumer.update) consumer.update(consumer.ref);
        }
    }
    return true;
};

/** 注册套装组件对某个 dressup 引用的共享 placement 消费。 */
_root.装备生命周期函数.剑圣套装登记就位消费者 = function(
    ref:Object, referenceName:String, update:Function):Boolean {
    var context:Object = ref ? ref.套装上下文 : null;
    var target:MovieClip = ref ? ref.自机 : null;
    if (!context || !target || !target.dispatcher || !referenceName || !update) return false;

    var channel:Object = context.placementChannels[referenceName];
    if (!channel) {
        channel = {
            referenceName:referenceName,
            source:null,
            ready:false,
            epoch:0,
            targetP0:{x:0, y:0},
            targetPX:{x:100, y:0},
            targetPY:{x:0, y:100},
            consumers:[]
        };
        context.placementChannels[referenceName] = channel;
        target.syncRefs[referenceName] = true;

        var placementHandler:Function = function(unit):Void {
            _root.装备生命周期函数.剑圣套装刷新就位通道(context, channel);
        };
        if (!_root.装备生命周期函数.剑圣套装登记事件(
            ref, target.dispatcher, referenceName, placementHandler, context)) {
            delete context.placementChannels[referenceName];
            return false;
        }
    }

    channel.consumers.push({ref:ref, update:update});
    if (channel.ready) {
        update(ref);
    } else {
        // 初始化时引用若已经完成 placement，可同步取得首个有效位置；未完成则由事件接管。
        _root.装备生命周期函数.剑圣套装刷新就位通道(context, channel);
    }
    return true;
};

/**
 * 将共享的 target-local 基向量转换到挂件实际容器。
 * channel 尚未就绪时宁可保持旧位置，也不消费已脱离显示树的 stale ref。
 */
_root.装备生命周期函数.剑圣套装读取就位基向量 = function(
    ref:Object, referenceName:String, container:MovieClip,
    p0:Object, pX:Object, pY:Object):Boolean {
    var context:Object = ref ? ref.套装上下文 : null;
    var target:MovieClip = ref ? ref.自机 : null;
    var channel:Object = context ? context.placementChannels[referenceName] : null;
    if (!target || !container || !channel || !channel.ready ||
        !channel.source || !channel.source._parent) return false;

    p0.x = channel.targetP0.x; p0.y = channel.targetP0.y;
    pX.x = channel.targetPX.x; pX.y = channel.targetPX.y;
    pY.x = channel.targetPY.x; pY.y = channel.targetPY.y;
    target.localToGlobal(p0);
    target.localToGlobal(pX);
    target.localToGlobal(pY);
    container.globalToLocal(p0);
    container.globalToLocal(pX);
    container.globalToLocal(pY);
    return true;
};

_root.装备生命周期函数.剑圣套装登记事件 = function(
    ref:Object, dispatcher:Object, eventName:String, handler:Function, scope:Object):Boolean {
    if (!dispatcher || !handler) return false;
    if (!dispatcher.subscribe(eventName, handler, scope)) return false;
    var registered:Boolean = org.flashNight.arki.unit.UnitComponent.Initializer.SetEffectController.registerResource(
        ref,
        function():Void { dispatcher.unsubscribe(eventName, handler, scope); }
    );
    if (!registered) dispatcher.unsubscribe(eventName, handler, scope);
    return registered;
};

_root.装备生命周期函数.剑圣套装登记挂件 = function(
    ref:Object, target:MovieClip, weaponName:String):Boolean {
    var context:Object = ref.套装上下文;
    if (!context) return false;
    context.attachments.push({ref:ref, weaponName:weaponName});

    // 旧实现会在 UnitReInitialized 分发期间移除挂件。保留这一可观察时序，
    // 但整套只注册一个预清理订阅，避免五个组件各自监听同一事件。
    if (!context.attachmentPrecleanupRegistered) {
        var precleanup:Function = function(unit):Void {
            for (var i:Number = 0; i < context.attachments.length; i++) {
                var entry:Object = context.attachments[i];
                var layer:MovieClip = target.底层背景;
                if (layer && layer[entry.weaponName]) layer[entry.weaponName].removeMovieClip();
                if (target[entry.weaponName]) target[entry.weaponName].removeMovieClip();
                entry.ref.weapon = null;
            }
        };
        if (!_root.装备生命周期函数.剑圣套装登记事件(
            ref, target.dispatcher, "UnitReInitialized", precleanup, context)) return false;
        context.attachmentPrecleanupRegistered = true;
    }

    return org.flashNight.arki.unit.UnitComponent.Initializer.SetEffectController.registerResource(
        ref,
        function():Void {
            var layer:MovieClip = target.底层背景;
            if (layer && layer[weaponName]) layer[weaponName].removeMovieClip();
            if (target[weaponName]) target[weaponName].removeMovieClip();
            ref.weapon = null;
        }
    );
};

_root.装备生命周期函数.剑圣套装登记Buff = function(
    ref:Object, manager:Object, buffId:String):Boolean {
    if (!manager || !buffId) return false;
    return org.flashNight.arki.unit.UnitComponent.Initializer.SetEffectController.registerResource(
        ref,
        function():Void {
            manager.removeBuff(buffId);
            manager.update(0);
        }
    );
};

_root.装备生命周期函数.剑圣套装登记战技恢复 = function(
    ref:Object, target:MovieClip, slot:String, oldSkill:Object):Boolean {
    return org.flashNight.arki.unit.UnitComponent.Initializer.SetEffectController.registerResource(
        ref,
        function():Void {
            target.主动战技[slot] = oldSkill;
            if (ref.是否为主角 && _root.玩家信息界面 &&
                _root.玩家信息界面.玩家必要信息界面 &&
                _root.玩家信息界面.玩家必要信息界面.战技栏) {
                _root.玩家信息界面.玩家必要信息界面.战技栏.战技栏图标刷新();
            }
        }
    );
};
