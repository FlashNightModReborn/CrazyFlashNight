_root.装备生命周期函数.电感切割刃初始化 = function(反射对象, 参数对象) 
{
   反射对象.子弹属性 = 反射对象.子弹配置.bullet_0;//通过反射对象传参通讯
   反射对象.射线子弹属性 = 反射对象.子弹配置.bullet_1;
   反射对象.射线子弹属性.Z轴攻击范围 = 参数对象.rayZRange ? 参数对象.rayZRange : 200;
   反射对象.射线搜索距离 = 参数对象.raySearchDistance ? 参数对象.raySearchDistance : 900;
   反射对象.成功率 = 参数对象.probability ? 参数对象.probability : 3;

   反射对象.常时刀光样式 = 参数对象.normalStyle ? 参数对象.normalStyle : "白色蓝框";
   反射对象.轻载刀光样式 = 参数对象.lowStyle ? 参数对象.lowStyle : "蓝色幽灵";
   反射对象.重载刀光样式 = 参数对象.heavyStyle ? 参数对象.heavyStyle : "蓝色魅影";
   反射对象.超载刀光样式 = 参数对象.overStyle ? 参数对象.overStyle : "红色透明";

   反射对象.当前帧 = 1;
   反射对象.动画帧 = 1;
   反射对象.动画时长 = 15;

   反射对象.过载值 = 0;
   反射对象.过载阈值 = 参数对象.threshold ? 参数对象.threshold : 120;
   反射对象.过载释放值 = 参数对象.output ? 参数对象.output : 20;

   // 注册刀_引用同步事件，确保装扮重载时系统得知本武器依赖刀_引用
   反射对象.自机.syncRefs.刀_引用 = true;
};

_root.装备生命周期函数.电感切割刃周期 = function(反射对象, 参数对象) 
{
   _root.装备生命周期函数.移除异常周期函数(反射对象);
   var 自机 = 反射对象.自机;
   var 刀 = 自机.刀_引用;
   var 启动许可 = false;
   var 超载许可 = 反射对象.过载值 >= 反射对象.过载阈值;

   if(_root.兵器使用检测(自机))
   {
      var 刀光样式 = 超载许可 ? 反射对象.超载刀光样式 : 反射对象.常时刀光样式;
      if(反射对象.当前帧 < 反射对象.动画时长)
      {
         反射对象.当前帧++;
      }

      if (_root.兵器攻击检测(自机)) 
      {
         启动许可 = true;

         if(超载许可)
         {
            刀光样式 = 反射对象.超载刀光样式;
            if(_root.成功率(反射对象.成功率))
            {
               var 刀口 = 刀 ? 刀.刀口位置3 : null;
               if (刀口 && 刀口._parent)
               {
                  //_root.服务器.立即发送("[CFB-1] 坐标计算前 过载值=" + 反射对象.过载值);
                  var 坐标 = {x:刀口._x,y:刀口._y};
                  刀口._parent.localToGlobal(坐标);
                  _root.gameworld.globalToLocal(坐标);

                  //_root.服务器.立即发送("[CFB-2] findNearest前 x=" + 坐标.x + " y=" + 坐标.y);
                  var 目标 = TargetCacheManager.findNearestEnemyInRange(自机, 5, 反射对象.射线搜索距离);
                  //_root.服务器.立即发送("[CFB-3] findNearest后 目标=" + (目标 != null ? 目标._name : "null"));
                  if(目标 != null)
                  {
                     var 目标中心Y:Number = 目标._y - UnitUtil.calculateCenterOffset(目标);
                     var dx = 目标._x - 坐标.x;
                     var dy = 目标中心Y - 坐标.y;
                     反射对象.射线子弹属性.速度X = dx;
                     反射对象.射线子弹属性.速度Y = dy || 0.001;
                     反射对象.射线子弹属性.ZY比例 = (目标中心Y != 0) ? 目标.Z轴坐标 / 目标中心Y : 1;
                     反射对象.射线子弹属性.shootX = 坐标.x;
                     反射对象.射线子弹属性.shootY = 坐标.y;
                     反射对象.射线子弹属性.shootZ = 自机.Z轴坐标;
                     //_root.服务器.立即发送("[CFB-4] shoot传递-射线前 dx=" + dx + " dy=" + dy);
                     _root.子弹区域shoot传递(反射对象.射线子弹属性);
                     //_root.服务器.立即发送("[CFB-5] shoot传递-射线后");
                  }
                  else
                  {
                     反射对象.子弹属性.shootX = 坐标.x;
                     反射对象.子弹属性.shootY = 坐标.y;
                     反射对象.子弹属性.shootZ = 自机.Z轴坐标;
                     //_root.服务器.立即发送("[CFB-4b] shoot传递-普通弹前");
                     _root.子弹区域shoot传递(反射对象.子弹属性);
                     //_root.服务器.立即发送("[CFB-5b] shoot传递-普通弹后");
                  }
                  反射对象.过载值 -= 反射对象.过载释放值;
                  //_root.服务器.立即发送("[CFB-6] 周期完成 过载值=" + 反射对象.过载值);
               }
               // 刀口未就绪（装扮正在重载），本次跳过射击，不消耗过载值
            }
         }
         else
         {
            if(反射对象.过载值 < 反射对象.过载阈值 / 2)
            {
               刀光样式 = 反射对象.轻载刀光样式;
            }
            else
            {
               刀光样式 = 反射对象.重载刀光样式;
            }
         }   
      }

      //_root.服务器.立即发送("[CFB-7] processBladeTrail前 样式=" + 刀光样式);
      BladeMotionTrailsRenderer.processBladeTrail(自机, 自机.刀_引用, 刀光样式);
      //_root.服务器.立即发送("[CFB-8] processBladeTrail后");
   }
   else
   {
      if(反射对象.当前帧 > 1)
      {
         反射对象.当前帧--;
      }
   }

   反射对象.动画帧 = 反射对象.当前帧;
   刀.动画.gotoAndStop(反射对象.动画帧);

   if(启动许可)
   {
      反射对象.过载值++;
   }
   else if(反射对象.过载值 > 0)
   {
      反射对象.过载值--;
   }
//_root.服务器.发布服务器消息("电感切割刃周期");
};
