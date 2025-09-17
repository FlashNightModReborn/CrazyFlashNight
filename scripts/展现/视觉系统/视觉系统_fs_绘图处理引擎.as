_root.绘图引擎 = {};

_root.绘图引擎.绘制矩形 = function(影片剪辑:MovieClip, xMin:Number, yMin:Number, xMax:Number, yMax:Number, 线条颜色:Number, 线条宽度:Number, 线条透明度:Number) {
    if (影片剪辑) {
        // 设置默认值
        线条颜色 = (线条颜色 != undefined) ? 线条颜色 : 0xFF0000; // 默认红色
        线条宽度 = (线条宽度 != undefined) ? 线条宽度 : 1;       // 默认1像素宽
        线条透明度 = (线条透明度 != undefined) ? 线条透明度 : 100; // 默认100%不透明度

        影片剪辑.lineStyle(线条宽度, 线条颜色, 线条透明度);

        影片剪辑.moveTo(xMin, yMin);
        影片剪辑.lineTo(xMax, yMin);
        影片剪辑.lineTo(xMax, yMax);
        影片剪辑.lineTo(xMin, yMax);
        影片剪辑.lineTo(xMin, yMin);
    }
};

_root.绘图引擎.绘制扇形 = function(影片剪辑:MovieClip, 中心点X:Number, 中心点Y:Number, 半径:Number, 起始角度:Number, 扇形角度:Number, 线条颜色:Number, 线条宽度:Number, 线条透明度:Number) {
    // 设置默认值
    线条颜色 = (线条颜色 != undefined) ? 线条颜色 : 0xFF0000; // 默认红色
    线条宽度 = (线条宽度 != undefined) ? 线条宽度 : 1;       // 默认1像素宽
    线条透明度 = (线条透明度 != undefined) ? 线条透明度 : 100; // 默认100%不透明度

    if (影片剪辑) {
        影片剪辑.lineStyle(线条宽度, 线条颜色, 线条透明度);
        
        影片剪辑.moveTo(中心点X, 中心点Y);
        var 结束角度 = 起始角度 + 扇形角度;
        影片剪辑.lineTo(中心点X + Math.cos(起始角度 * (Math.PI / 180)) * 半径, 中心点Y + Math.sin(起始角度 * (Math.PI / 180)) * 半径);

        if (扇形角度 > 0) {
            for (var 角度 = 起始角度; 角度 <= 结束角度; 角度++) {
                var 弧度 = 角度 * (Math.PI / 180);
                影片剪辑.lineTo(中心点X + Math.cos(弧度) * 半径, 中心点Y + Math.sin(弧度) * 半径);
            }
        } else {
            for (var 角度 = 起始角度; 角度 >= 结束角度; 角度--) {
                var 弧度 = 角度 * (Math.PI / 180);
                影片剪辑.lineTo(中心点X + Math.cos(弧度) * 半径, 中心点Y + Math.sin(弧度) * 半径);
            }
        }
        影片剪辑.lineTo(中心点X, 中心点Y);
    }
};

// 通用的绘制线条函数
_root.绘图引擎.绘制线条 = function(影片剪辑:MovieClip, 点集:Array, 线条颜色:Number, 线条宽度:Number, 线条透明度:Number) {
    if (影片剪辑 == undefined || 点集 == undefined || 点集.length < 2) return; // 校验点集

    线条颜色 = (线条颜色 != undefined) ? 线条颜色 : 0xFF0000; // 默认红色
    线条宽度 = (线条宽度 != undefined) ? 线条宽度 : 1; // 默认宽度为1
    线条透明度 = (线条透明度 != undefined) ? 线条透明度 : 100; // 默认100%不透明

    影片剪辑.lineStyle(线条宽度, 线条颜色, 线条透明度); // 设置线条样式
    影片剪辑.moveTo(点集[0].x, 点集[0].y);
    for (var i = 1; i < 点集.length; i++) {
        影片剪辑.lineTo(点集[i].x, 点集[i].y);
    }
};

// 通用的绘制闭合线条函数
_root.绘图引擎.绘制闭合线条 = function(影片剪辑:MovieClip, 点集:Array, 线条颜色:Number, 线条宽度:Number, 线条透明度:Number) {
    if (影片剪辑 == undefined || 点集 == undefined || 点集.length < 3) return; // 校验点集，闭合线条至少需要3个点

    线条颜色 = (线条颜色 != undefined) ? 线条颜色 : 0xFF0000; // 默认红色
    线条宽度 = (线条宽度 != undefined) ? 线条宽度 : 1; // 默认宽度为1
    线条透明度 = (线条透明度 != undefined) ? 线条透明度 : 100; // 默认100%不透明

    影片剪辑.lineStyle(线条宽度, 线条颜色, 线条透明度); // 设置线条样式
    影片剪辑.moveTo(点集[0].x, 点集[0].y);
    for (var i = 1; i < 点集.length; i++) {
        影片剪辑.lineTo(点集[i].x, 点集[i].y);
    }
    影片剪辑.lineTo(点集[0].x, 点集[0].y); // 回到起点闭合形状
};

// 通用的绘制形状函数
_root.绘图引擎.绘制形状 = function(影片剪辑:MovieClip, 点集:Array, 填充颜色:Number, 线条颜色:Number, 线条宽度:Number, 填充透明度:Number, 线条透明度:Number) {
    if (影片剪辑 == undefined || 点集 == undefined || 点集.length < 3) return; // 校验点集，至少需要3个点来形成一个闭合形状
    
    填充透明度 = (填充透明度 != undefined) ? 填充透明度 : 100; // 默认填充透明度为100%

    // 设置线条样式，包括颜色、透明度和宽度
    if (线条颜色 != undefined) {
        线条宽度 = (线条宽度 != undefined) ? 线条宽度 : 1;
        线条透明度 = (线条透明度 != undefined) ? 线条透明度 : 100;
        影片剪辑.lineStyle(线条宽度, 线条颜色, 线条透明度);
    } else {
        影片剪辑.lineStyle(); // 不绘制线条
    }

    // 设置填充颜色和透明度
    if (填充颜色 != undefined) {
        影片剪辑.beginFill(填充颜色, 填充透明度);
    } else {
        影片剪辑.beginFill(填充颜色, 100); // 默认不透明
    }

    // 绘制形状
    影片剪辑.moveTo(点集[0].x, 点集[0].y);
    for (var i = 1; i < 点集.length; i++) {
        影片剪辑.lineTo(点集[i].x, 点集[i].y);
    }
    影片剪辑.lineTo(点集[0].x, 点集[0].y); // 闭合形状
    影片剪辑.endFill(); // 结束填充
};


_root.绘图引擎.渲染线框 = function(mc:MovieClip):Void {
    // 参数 mc：要渲染边框的 MovieClip
    // 调用 ClipFrameRenderer.renderClipFrame 实现
    org.flashNight.arki.render.ClipFrameRenderer.renderClipFrame(mc);
};

// 2. 渲染动态残影
_root.绘图引擎.渲染残影 = function(mc:MovieClip, style:String):Void {
    // 参数 mc：要渲染残影的 MovieClip
    //       style：传入给 TrailRenderer 的样式标识
    org.flashNight.arki.render.ClipFrameRenderer.renderClipTrail(mc, style);
};



_root.绘图引擎.加载位图数据 = function():Void{
    org.flashNight.arki.component.Effect.BitmapEffectRenderer.loadBloodstains();
}
_root.绘图引擎.渲染血迹 = function(x, y):Void{
    org.flashNight.arki.component.Effect.BitmapEffectRenderer.renderBloodstain(x, y);
}