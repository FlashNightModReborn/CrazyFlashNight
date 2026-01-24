// ============================================================
// 初始化
// ============================================================

_root.装备生命周期函数.贯空天盖手套初始化 =  function(反射对象, 参数对象)
{
    var 自机 = 反射对象.自机;
    参数对象 = 参数对象 || {};
};

// ============================================================
// 周期
// ============================================================
_root.装备生命周期函数.贯空天盖手套周期 = function(反射对象, 参数对象)
{
	//_root.装备生命周期函数.移除异常周期函数(反射对象);
    var 自机 = 反射对象.自机;
   if (自机._name == _root.控制目标 && 自机.攻击模式 === "空手")
   {
      var 装备栏 = _root.物品栏.装备栏;
      var 头部装备 = 装备栏.getNameString("头部装备");
      var 上装装备 = 装备栏.getNameString("上装装备");
      var 战技列表 = ["咒针","伸手及月"];
      if(头部装备 == "登上明星"){
         战技列表.push("登上明星");
      }
      if(上装装备 == "贯空天盖上衣"){
         战技列表.push("回归枢机之光");
      }
      if(!装备栏.getItem("手部装备").value.当前战技){
         装备栏.getItem("手部装备").value.当前战技 = 0;
      }
		if (Key.isDown(_root.武器变形键))
		{
			if (!按键中)
			{
            装备栏.getItem("手部装备").value.当前战技 += 1;
				if (装备栏.getItem("手部装备").value.当前战技 >= 战技列表.length)
				{
					装备栏.getItem("手部装备").value.当前战技 = 0;
				}
				if (装备栏.getItem("手部装备").value.当前战技 == 3 && 自机.回归枢机之光发射数 && 自机.回归枢机之光发射数 >= 5)
				{
					装备栏.getItem("手部装备").value.当前战技 = 0;
               _root.发布消息("[回归枢机之光]发射数已达到本张地图的上限，当前战技切换为["+ 战技列表[装备栏.getItem("手部装备").value.当前战技] + "]");
				}else{
               _root.发布消息("当前战技切换为["+ 战技列表[装备栏.getItem("手部装备").value.当前战技] + "]");
            }
			}
			按键中 = true;
		}
		else
		{
			按键中 = false;
		}
   }
};

/*====================================================================
 * 登上明星初始化（持久柔光拖尾）
 * 说明：
 *   - 独立拖尾系统，适用于单个 MovieClip（如明星子弹）
 *   - 拖尾更长（16帧历史）、更持久（透明度衰减慢）
 *   - 颜色：#F8C7FF（淡紫粉）
 *   - 保留伪Z效果：近景略粗略亮，远景略细略暗
 *   - 自动采样位置，自动绘制，无需外部干预
 *===================================================================*/
_root.装备生命周期函数.登上明星初始化 = function (clip:MovieClip):Void {
    // 初始化拖尾存储
    clip.trail = [];

    // 拖尾参数（可被 clip._parent 覆盖）
    var maxTrailLength:Number = (clip._parent && clip._parent.明星拖尾长度 != undefined) 
        ? clip._parent.明星拖尾长度 : 20; // 更长拖尾

    var fadeInoutBase:Number = (clip._parent && clip._parent.明星拖尾透明度 != undefined)
        ? clip._parent.明星拖尾透明度 : 100; // 基础透明度（起点）

    var fadeStep:Number = (clip._parent && clip._parent.明星拖尾衰减 != undefined)
        ? clip._parent.明星拖尾衰减 : 3; // 衰减更慢（原为15）

    var baseWidth:Number = (clip._parent && clip._parent.明星拖尾粗细 != undefined)
        ? clip._parent.明星拖尾粗细 : 15;

    var nearGain:Number = (clip._parent && clip._parent.明星近景增粗 != undefined)
        ? clip._parent.明星近景增粗 : 0.3;

    var farDarken:Number = (clip._parent && clip._parent.明星远景暗化 != undefined)
        ? clip._parent.明星远景暗化 : 0.25;

    // 颜色：#F8C7FF → RGB(248,199,255)
    var trailColor:Number = 0xF8C7FF;

    // ==== 预填充轨迹（关键！）====
    var initialLength:Number = (clip._parent && clip._parent.预填充节点 != undefined) 
        ? clip._parent.预填充节点 :Math.min(3, maxTrailLength);
    var speedX:Number, speedY:Number;

    // 尝试从父级获取速度
    if (clip._parent.xmov != undefined && clip._parent.ymov != undefined) {
        speedX = clip._parent.xmov;
        speedY = clip._parent.ymov;
    } else {
        // 从旋转推导（假设速度大小为 8）
        var rad:Number = clip._rotation * Math.PI / 180;
        speedX = Math.cos(rad) * 8;
        speedY = Math.sin(rad) * 8;
    }

    // 反向生成历史点
    for (var k:Number = 0; k < initialLength; k++) {
        var xTrail:Number = clip._x - speedX * k;
        var yTrail:Number = clip._y - speedY * k;
        var gTrail:Object = {x: xTrail, y: yTrail};
        clip._parent.localToGlobal(gTrail);
        gTrail.zn = 0;
        clip.trail.push(gTrail);
    }
    clip.trail.reverse(); // 保证最新点在 trail[0]

    // ==== 帧循环 ====
    clip.onEnterFrame = function():Void {
        if (_root.暂停) return;

        // 采样当前位置
        var globalPos:Object = {x: this._x, y: this._y};
        this._parent.localToGlobal(globalPos);
        globalPos.zn = 0;
        this.trail.unshift(globalPos);
        if (this.trail.length > maxTrailLength) {
            this.trail.pop();
        }

        // 2. 绘制拖尾（在父容器上绘制，或新建 Sprite；这里假设在 clip 自身绘制）
        // 但通常拖尾应在更高层级绘制（避免旋转影响），此处为简化，在 clip 上绘制
        // 若需更佳效果，建议在专用拖尾层绘制。此处保持与原逻辑一致。
        this.clear();

        if (this.trail.length > 1) {
            for (var t:Number = 0; t < this.trail.length - 1; t++) {
                var p1:Object = this.trail[t];
                var p2:Object = this.trail[t + 1];

                var l1:Object = {x: p1.x, y: p1.y};
                var l2:Object = {x: p2.x, y: p2.y};
                this._parent.globalToLocal(l1); // 转回本地坐标（相对于父级）
                this._parent.globalToLocal(l2);

                // 透明度：起点高，缓慢衰减
                var alpha:Number = Math.max(10, fadeInoutBase - t * fadeStep);

                // 伪Z调制
                var znAvg:Number = (p1.zn + p2.zn) * 0.5;
                if (znAvg > 1) znAvg = 1; else if (znAvg < -1) znAvg = -1;

                // 线宽：基础 + 近景增粗
                var widthGain:Number = 1 + nearGain * Math.max(0, znAvg);
                var lineWidth:Number = Math.max(0.6, baseWidth - t * 1) * widthGain;

                // 远景暗化
                var farFactor:Number = 1 - farDarken * Math.max(0, -znAvg);
                var drawAlpha:Number = alpha * farFactor;

                this.lineStyle(lineWidth, trailColor, drawAlpha);
                this.moveTo(l1.x, l1.y);
                this.lineTo(l2.x, l2.y);
            }
        }
    };
};