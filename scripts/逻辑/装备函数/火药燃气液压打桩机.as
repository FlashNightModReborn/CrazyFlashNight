_root.装备生命周期函数.火药燃气液压打桩机初始化 = function(reflector:Object, paramObj:Object) {
    var target:MovieClip = reflector.自机;
    
    // 创建状态机
    reflector.fsm = new FSM_StateMachine(null, null, null);
    
    // 创建共享数据
    reflector.fsm.data = {
        currentframe: 1,
        flag: false,
        target: target
    };
    
    // 创建空闲状态 - 当设备处于帧1时
    var idleState = new FSM_Status(
        // onAction - 空闲状态下只需保持当前帧
        function():Void {
            this.data.target.长枪_引用.动画.gotoAndStop(this.data.currentframe);
        },
        // onEnter - 进入空闲状态时重置到帧1
        function():Void {
            this.data.currentframe = 1;
            this.data.target.长枪_引用.动画.gotoAndStop(this.data.currentframe);
        },
        // onExit - 退出时无需特殊处理
        null
    );
    
    // 创建激活状态 - 当动画正在播放时(帧2-60)
    var activeState = new FSM_Status(
        // onAction - 激活状态下递增帧数
        function():Void {
            this.data.currentframe++;
            this.data.target.长枪_引用.动画.gotoAndStop(this.data.currentframe);
        },
        // onEnter - 进入激活状态时从帧2开始
        function():Void {
            this.data.currentframe = 2;
            this.data.target.长枪_引用.动画.gotoAndStop(this.data.currentframe);
        },
        // onExit - 退出时无需特殊处理
        null
    );
    
    // 将状态添加到状态机
    reflector.fsm.AddStatus("IDLE", idleState);
    reflector.fsm.AddStatus("ACTIVE", activeState);
    
    // 设置状态转换
    // 从IDLE到ACTIVE的转换，当flag为true时
    reflector.fsm.transitions.push("IDLE", "ACTIVE", function():Boolean {
        return this.data.flag === true;
    });
    
    // 从ACTIVE到IDLE的转换，当动画完成时
    reflector.fsm.transitions.push("ACTIVE", "IDLE", function():Boolean {
        return this.data.currentframe > 60;
    });
    
    // 启动状态机（IDLE 为默认首状态，start 触发 IDLE.onEnter）
    reflector.fsm.start();
    
    // 订阅长枪射击事件
    target.dispatcher.subscribe("长枪射击", function() {
        reflector.fsm.data.flag = true;
    });
};

/**
 * 火药燃气液压打桩机的装备生命周期函数
 * @param reflector:Object - 反射器对象，包含动画状态和目标
 * @param paramObj:Object - 参数对象(当前未使用)
 */
_root.装备生命周期函数.火药燃气液压打桩机周期 = function(reflector:Object, paramObj:Object) {
    // 移除异常周期函数
    _root.装备生命周期函数.移除异常周期函数(reflector);
    
    // 处理状态机逻辑
    reflector.fsm.onAction();
    
    // 处理完成后重置标志
    reflector.fsm.data.flag = false;
};