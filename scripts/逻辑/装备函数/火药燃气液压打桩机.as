import org.flashNight.neur.Event.*;

_root.装备生命周期函数.火药燃气液压打桩机初始化 = function(reflector:Object, paramObj:Object) 
{
   var target:MovieClip = reflector.自机;
   var r:Object = reflector; // 闭包持有引用

   target.dispatcher.subscribeSingle("processShot", function(target:MovieClip, weaponType:String)
   {
      if(weaponType == "长枪"){
         r.flag = true;
      }
   })

   r.currentframe = 1;
   r.flag = false;
};


/**
 * 火药燃气液压打桩机的装备生命周期函数
 * @param reflector:Object - 反射器对象，包含动画状态和目标
 * @param paramObj:Object - 参数对象(当前未使用)
 */
_root.装备生命周期函数.火药燃气液压打桩机周期 = function(reflector:Object, paramObj:Object) {
    // 移除异常周期函数
    _root.装备生命周期函数.移除异常周期函数(reflector);
    
    // 获取目标对象
    var target:MovieClip = reflector.自机;
    
    // 帧控制逻辑
    if (reflector.flag === true) {
        // 如果标志为真，重置到指定帧
        reflector.currentframe = 2;
    } else if (reflector.currentframe > 1) {
        // 增加当前帧
        reflector.currentframe++;
        
        // 循环检查
        if (reflector.currentframe > 60) {
            reflector.currentframe = 1;
        }
    }
    
    // 重置标志
    reflector.flag = false;
    
    // 应用动画帧
    target.长枪_引用.动画.gotoAndStop(reflector.currentframe);
};