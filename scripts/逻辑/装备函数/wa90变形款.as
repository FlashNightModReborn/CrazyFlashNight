_root.装备生命周期函数.wa90变形款初始化 = function(反射对象, 参数对象) 
{
   反射对象.animationDuration = 参数对象.animationDuration ? 参数对象.animationDuration : 15;
   反射对象.currentFrame = 1;
   反射对象.animationTarget = 参数对象.animationTarget ? 参数对象.animationTarget : "动画";
   反射对象.instanceContainer = 参数对象.instanceContainer ? 参数对象.instanceContainer : "长枪_引用";

   var target:MovieClip = 反射对象.自机[反射对象.instanceContainer][反射对象.animationTarget];
   // 初始化动画状态
   target.gotoAndStop(反射对象.currentFrame);
   var af:String = 参数对象.actionFunc ? 参数对象.actionFunc : "是否使用长枪";
   // 状态判断函数
   反射对象.actionFunc = _root.装备生命周期函数[af];
};

_root.装备生命周期函数.wa90变形款周期 = function(反射对象, 参数对象) 
{
   _root.装备生命周期函数.移除异常周期函数(反射对象);
   
   if(反射对象.actionFunc()) 
   {
      if(反射对象.currentFrame < 反射对象.animationDuration) 
      {
         反射对象.currentFrame++;
      }
   }
   else 
   {
      if(反射对象.currentFrame > 1) 
      {
         反射对象.currentFrame--;
      }
   }
   var target:MovieClip = 反射对象.自机[反射对象.instanceContainer][反射对象.animationTarget];
   // 同步动画帧
   target.gotoAndStop(反射对象.currentFrame);
};


_root.装备生命周期函数.是否使用长枪 = function(反射对象)
{
   return (反射对象.自机.攻击模式 === "长枪");
};
