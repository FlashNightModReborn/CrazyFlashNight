_root.导弹模版 = {};


_root.导弹模板.导弹飞行 = function()
{
   if(this.飞行状态[this.飞行状态阶段].燃料耗尽 === true and this.飞行状态阶段 < this.飞行状态.length -1)
   {
        this.飞行状态阶段 += 1;
   }
   this.飞行时间 += 1;
   this.飞行状态[this.飞行状态阶段].飞行();
};

_root.导弹模板.导弹运行 = function()
{
    this.探测头.寻找攻击目标();
    _root.导弹模板.导弹飞行();
};

_root.导弹模板.初始化导弹 = function(导弹参数)
{
    this.导弹参数 = 导弹参数;
    this.探测头 = this.导弹参数.探测头;
    this.战斗部 = this.导弹参数.战斗部;

    this.飞行状态 = this.导弹参数.飞行状态;
    this.飞行状态阶段 = 0;
    this.导弹飞行 = _root.导弹模板.导弹飞行;
    this.飞行时间 = 0;
    
    this.onEnterFrame = _root.导弹模板.导弹运行;
};


/*
onClipEvent(load){
   子弹名 = _parent._name;
   基准速度 = 20;
   加速度 = 0.25;
   速度 = _root.basic_random() * 3;
   旋转角度 = _parent._rotation + 15 - _root.basic_random() * 30;
   _parent._x += 30 - _root.basic_random() * 30;
   _parent._y += (- _root.basic_random()) * 30;
   上抛速度 = _root.basic_random() * -5 - 5;
   上抛阻力 = 0.4;
   修正角度 = 0;
   转向速度 = 36;
   飞行阻力 = 0.02;
   转向阻力 = 0.05;
   速度上限 = 5;
   转向动力 = 18;
   转向速度下限 = 5;
   锁定延迟 = -4;
   锁定范围 = 2000;
   是否为敌人 = !_root.gameworld.子弹区域[子弹名].子弹敌我属性值;
   攻击目标 = "无";
   瞄准许可 = false;
   初始_x = _parent._x + _parent._parent._x;
   初始_y = _parent._y + _parent._parent._y;
   导弹坐标 = {x:初始_x,y:初始_y};
   锁定坐标 = {x:初始_x,y:初始_y};
   敌人 = null;
   敌人_x = 0;
   敌人_y = 0;
   敌人_z = 0;
   敌人名 = "无";
   d_min = 锁定范围;
   d = infinity;
   敌人_敌我属性 = undefined;
   待检测元件 = this;
   循环记数 = 0;
   发射速度 = Math.sqrt(Math.pow(_root.gameworld.子弹区域[子弹名].xmov,2) + Math.pow(_root.gameworld.子弹区域[子弹名].ymov,2));
   _root.gameworld.子弹区域[子弹名].xmov = 0;
   _root.gameworld.子弹区域[子弹名].ymov = 0;
   发射者名 = _root.gameworld.子弹区域[子弹名].发射者名;
   Z轴坐标 = _root.gameworld.子弹区域[子弹名].Z轴坐标;
   this.转换导弹坐标 = function()
   {
      导弹坐标.x = _parent._x + _parent._parent._x;
      导弹坐标.y = _parent._y + _parent._parent._y;
   };
   this.寻找攻击目标 = function()
   {
      敌人_x = 0;
      敌人_y = 0;
      敌人名 = "无";
      d_min = 锁定范围;
      if(攻击目标 == "无")
      {
         for(§each§ in _root.gameworld)
         {
            敌人_敌我属性 = _root.gameworld[eval("each")].是否为敌人;
            if(是否为敌人 != 敌人_敌我属性 and _root.gameworld[eval("each")].hp > 0)
            {
               敌人_x = _root.gameworld[eval("each")]._x;
               敌人_y = _root.gameworld[eval("each")]._y;
               敌人名 = _root.gameworld[eval("each")]._name;
               d = Math.abs(敌人_x - 导弹坐标.x) + 5 * Math.abs(敌人_y - 初始_y);
               if(d_min > d)
               {
                  d_min = d;
                  攻击目标 = 敌人名;
                  敌人_z = _root.gameworld[eval("each")].Z轴坐标;
                  锁定坐标.x = 敌人_x;
                  锁定坐标.y = 敌人_y - 30;
               }
            }
         }
         if(攻击目标 != "无")
         {
            瞄准许可 = true;
            加速度 += 1.25;
            速度上限 = 80;
            上抛速度 = _root.basic_random() * -5 - 5;
         }
      }
   };
   this.onEnterFrame = function()
   {
      if(上抛速度 < 0)
      {
         上抛速度 += 上抛阻力;
      }
      if(上抛速度 > 0)
      {
         上抛速度 = 0;
      }
      if(速度 < 速度上限)
      {
         速度 = 速度 + 加速度 - 速度 * 飞行阻力;
      }
      旋转角度 = _parent._rotation;
      this.转换导弹坐标();
      锁定延迟 += 1;
      if(锁定延迟 and 攻击目标 == "无")
      {
         this.寻找攻击目标();
         锁定延迟 = -29;
      }
      if(瞄准许可 and 转向动力)
      {
         转向动力 -= 1;
         修正角度 = (Math.atan2(锁定坐标.y - 导弹坐标.y,锁定坐标.x - 导弹坐标.x) + 360) % 360 * (180 / Math.PI) - 旋转角度;
         if(修正角度 > 转向速度)
         {
            修正角度 = 转向速度;
         }
         else if(修正角度 + 转向速度 < 0)
         {
            修正角度 = -1 * 转向速度;
         }
         else if(!(修正角度 <= 转向速度 and 修正角度 >= -1 * 转向速度))
         {
            修正角度 = 0;
         }
         if(速度 > 转向速度下限)
         {
            速度 -= Math.abs(修正角度 * 转向阻力);
         }
      }
      else
      {
         修正角度 = 0;
      }
      旋转角度 = 修正角度 + 旋转角度;
      _parent._rotation = 旋转角度;
      dx = Math.cos(旋转角度 * (Math.PI / 180)) * 速度 * 发射速度 / 基准速度;
      dy = Math.sin(旋转角度 * (Math.PI / 180)) * 速度 * 发射速度 / 基准速度;
      _parent._x += dx;
      _parent._y += dy + 上抛速度;
   };
*/