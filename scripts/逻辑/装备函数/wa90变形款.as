_root.装备生命周期函数.wa90变形款初始化 = function(反射对象, 参数对象) 
{
   反射对象.animationDuration = 参数对象.animationDuration ? 参数对象.animationDuration : 15;
   反射对象.当前帧 = 1;
   反射对象.animationTarget = 参数对象.animationTarget ? 参数对象.animationTarget : "动画";
   
   var target:MovieClip = 反射对象.自机.长枪_引用[反射对象.animationTarget]
   // 初始化动画状态
   target.gotoAndStop(反射对象.当前帧);

   // 状态判断函数
   反射对象.是否展开 = function() 
   {
      return (反射对象.自机.攻击模式 === "长枪");
   };
};

_root.装备生命周期函数.wa90变形款周期 = function(反射对象, 参数对象) 
{
   _root.装备生命周期函数.移除异常周期函数(反射对象);
   
   if(反射对象.是否展开()) 
   {
      if(反射对象.当前帧 < 反射对象.animationDuration) 
      {
         反射对象.当前帧++;
      }
   }
   else 
   {
      if(反射对象.当前帧 > 1) 
      {
         反射对象.当前帧--;
      }
   }
   var target:MovieClip = 反射对象.自机.长枪_引用[反射对象.animationTarget]
   // 同步动画帧
   target.gotoAndStop(反射对象.当前帧);
};