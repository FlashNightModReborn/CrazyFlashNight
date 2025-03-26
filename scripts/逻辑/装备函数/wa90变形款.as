_root.装备生命周期函数.wa90变形款初始化 = function(reflector:Object, paramObj:Object) 
{
   reflector.animationDuration = paramObj.animationDuration ? paramObj.animationDuration : 15;
   reflector.currentFrame = 1;
   reflector.animationTarget = paramObj.animationTarget ? paramObj.animationTarget : "动画";
   reflector.instanceContainer = paramObj.instanceContainer ? paramObj.instanceContainer : "长枪_引用";
   reflector.funcParam = paramObj.funcParam ? paramObj.funcParam : {攻击模式:"长枪"};

   var target:MovieClip = reflector.自机[reflector.instanceContainer][reflector.animationTarget];
   // 初始化动画状态
   target.gotoAndStop(reflector.currentFrame);
   var af:String = paramObj.actionFunc ? paramObj.actionFunc : "自机状态检测";
   // 状态判断函数
   reflector.actionFunc = _root.装备生命周期函数[af];

   reflector.funcType = paramObj.funcType ? paramObj.funcType : "FIRST_MATCH";
};

_root.装备生命周期函数.wa90变形款周期 = function(reflector:Object, paramObj:Object) 
{
   _root.装备生命周期函数.移除异常周期函数(reflector);
   
   if (reflector.actionFunc(reflector, reflector.funcParam))
   {
      if(reflector.currentFrame < reflector.animationDuration) 
      {
         reflector.currentFrame++;
      }
   }
   else 
   {
      if(reflector.currentFrame > 1) 
      {
         reflector.currentFrame--;
      }
   }
   var target:MovieClip = reflector.自机[reflector.instanceContainer][reflector.animationTarget];
   // 同步动画帧
   target.gotoAndStop(reflector.currentFrame);
};


_root.装备生命周期函数.自机状态检测 = function(reflector:Object, funcParam:Object) 
{
    switch(reflector.funcType) 
    {
        case "ANY_MATCH": // 任意条件满足即返回true
            for (var k in funcParam) {
                if (reflector.自机[k] === funcParam[k]) {
                    return true;
                }
            }
            return false;
            
        case "ALL_MATCH": // 全部条件满足才返回true
            for (var k in funcParam) {
                if (reflector.自机[k] !== funcParam[k]) {
                    return false;
                }
            }
            return true;
            
        case "FIRST_MATCH": // 默认模式：按顺序检查，第一个遇到的属性决定结果
        default:
            for (var k in funcParam) {
                return (reflector.自机[k] === funcParam[k]);
            }
            return false;
    }
};