import org.flashNight.neur.Event.*;

_root.装备生命周期函数.火药燃气液压打桩机初始化 = function(反射对象, 参数对象) 
{
   var 自机 = 反射对象.自机;
   var 原长枪射击函数 = 自机.长枪射击;

   反射对象.长枪射击事件 = function(反射对象)
   {
      _root.服务器.发布服务器消息("触发长枪射击事件: " + 反射对象.标签名);
   }


   反射对象.自机.dispatcher.subscribeSingle("processShot", 反射对象.长枪射击事件)
};


_root.装备生命周期函数.火药燃气液压打桩机周期 = function(反射对象, 参数对象) 
{
   _root.装备生命周期函数.移除异常周期函数(反射对象);
   var 自机 = 反射对象.自机;
   var 枪 = 自机.长枪_引用;

};
