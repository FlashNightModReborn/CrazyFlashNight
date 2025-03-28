// 文件路径：org/flashNight/arki/unit/Action/Shoot/ShootCore.as
class org.flashNight.arki.unit.Action.Shoot.ShootCore {
    /**
     * 内核函数：处理持续射击的通用逻辑
     * @param core           当前作战对象（自机）
     * @param attackMode     攻击模式（用作方法名称拼接）
     * @param shootSpeed     射击速度
     * @param params         参数对象，包含各个包装函数不同的配置项：
     *   - shootingStateName: String, 如 "主手射击中" 或 "副手射击中"
     *   - actionFlagName   : String, 如 "动作A" 或 "动作B"
     *   - prefix           : String, 帧名称后缀（主手为空，副手为 "2"）
     *   - bulletAttrKeys   : Array, 需要重置角度偏移的子弹属性键，如 ["子弹属性"] 或 ["子弹属性", "子弹属性2"]
     *   - shootBulletAttrKey: String, 实际用于射击时的子弹属性键
     *   - gunPath          : String, 指定枪口位置的路径，如 "枪.枪.装扮.枪口位置"
     *   - taskName         : String, 帧计时器中任务的名称，如 "keepshooting" 或 "keepshooting2"
     *   - playerBulletField: String, 玩家界面中需要更新的子弹数属性，如 "子弹数" 或 "子弹数_2"
     * @return Boolean       返回是否处于持续射击状态
     */
    public static function continuousShoot(core:Object, attackMode:String, shootSpeed:Number, params:Object):Boolean {
        core.射击最大后摇中 = false;
        if(!core.man.射击许可标签){
            core[params.shootingStateName] = false;
            _root.帧计时器.移除任务(core[params.taskName]);
            return false;
        }
        // 重置各指定子弹属性的角度偏移
        for(var i:Number = 0; i < params.bulletAttrKeys.length; i++){
            var key:String = params.bulletAttrKeys[i];
            core.man[key].角度偏移 = 0;
        }
        
        // 默认动画帧名称
        var jumpFrameName:String = "射击" + params.prefix;
        if(_root.控制目标 === core._name && !core.上下移动射击){
            if(core.下行){
                for(var j:Number = 0; j < params.bulletAttrKeys.length; j++){
                    var key2:String = params.bulletAttrKeys[j];
                    core.man[key2].角度偏移 = 30;
                }
                jumpFrameName = "下射击" + params.prefix;
            } else if(core.上行){
                for(var j:Number = 0; j < params.bulletAttrKeys.length; j++){
                    var key3:String = params.bulletAttrKeys[j];
                    core.man[key3].角度偏移 = -30;
                }
                jumpFrameName = "上射击" + params.prefix;
            }
        }
        
        core[params.shootingStateName] = false;
        if(core[params.actionFlagName]){
            core.man.gotoAndPlay(jumpFrameName);
            // 根据参数中指定的路径依次取得枪口位置
            var gunRef:Object = core.man;
            var parts:Array = params.gunPath.split(".");
            for(var k:Number = 0; k < parts.length; k++){
                gunRef = gunRef[parts[k]];
            }
            // 调用具体射击方法（方法名由 attackMode 与 "射击" 拼接得到）
            core[params.shootingStateName] = core[attackMode + "射击"](gunRef, core.man[params.shootBulletAttrKey]);
            var magazineRemaining:Number = core[attackMode + "弹匣容量"] - core[attackMode + "射击次数"][core[attackMode]];
            if(_root.控制目标 === core._name)
                _root.玩家信息界面.玩家必要信息界面[params.playerBulletField] = magazineRemaining;
            if(magazineRemaining <= 0)
                core[params.shootingStateName] = false;
            core.射击最大后摇中 = core[params.shootingStateName];
            if(shootSpeed > 300){
                _root.帧计时器.添加或更新任务(core, "结束射击后摇", function(target:Object):Void {
                    target.射击最大后摇中 = false;
                }, 300, core);
            }
        }
        
        if(core[params.shootingStateName])
            return true;
        _root.帧计时器.移除任务(core[params.taskName]);
        return false;
    }
}
