// 重构后的残影系统，基于矢量绘制，不再使用 BitmapData

_root.残影系统 = {};

_root.残影系统.初始化 = function() {
    this.残影数量 = 5;
    this.残影变动间隔帧数 = 1;
    this.残影存在时间 = _root.帧计时器.每帧毫秒 * this.残影数量 * this.残影变动间隔帧数;
    this.残影变动时间 = this.残影存在时间 / this.残影数量;
    this.残影刷新时间 = this.残影变动时间 / this.残影数量;
    this.残影透明度衰减 = 100 / this.残影数量;
};

_root.残影系统.初始化();

_root.残影系统.绘制元件 = function(影片剪辑, 参数) {
    this.绘制到画布(影片剪辑, _root.色彩引擎.初级调整颜色(影片剪辑, 参数));
};

_root.残影系统.绘制线条 = function(点集, 颜色, 线条宽度) {
    var 画布 = this.获得当前画布();
    if (点集 == undefined || 点集.length < 2) return;

    颜色 = 颜色 == undefined ? 0xFF0000 : 颜色;
    线条宽度 = 线条宽度 == undefined ? 1 : 线条宽度;

    画布.lineStyle(线条宽度, 颜色, 100);
    画布.moveTo(点集[0].x, 点集[0].y);
    for (var i = 1; i < 点集.length; i++) {
        画布.lineTo(点集[i].x, 点集[i].y);
    }
};

_root.残影系统.绘制闭合线条 = function(点集, 颜色, 线条宽度) {
    var 画布 = this.获得当前画布();
    if (点集 == undefined || 点集.length < 3) return;

    颜色 = 颜色 == undefined ? 0xFF0000 : 颜色;
    线条宽度 = 线条宽度 == undefined ? 1 : 线条宽度;

    画布.lineStyle(线条宽度, 颜色, 100);
    画布.moveTo(点集[0].x, 点集[0].y);
    for (var i = 1; i < 点集.length; i++) {
        画布.lineTo(点集[i].x, 点集[i].y);
    }
    画布.lineTo(点集[0].x, 点集[0].y);
};

_root.残影系统.绘制形状 = function(点集, 填充颜色, 线条颜色, 线条宽度, 填充透明度, 线条透明度) {
    var 画布 = this.获得当前画布();
    if (点集 == undefined || 点集.length < 3) return;
    
    填充透明度 = 填充透明度 == undefined ? 100 : 填充透明度;

    if (线条颜色 != undefined) {
        线条宽度 = 线条宽度 == undefined ? 1 : 线条宽度;
        线条透明度 = 线条透明度 == undefined ? 100 : 线条透明度;
        画布.lineStyle(线条宽度, 线条颜色, 线条透明度);
    } else {
        画布.lineStyle();
    }

    if (填充颜色 != undefined) {
        画布.beginFill(填充颜色, 填充透明度);
    } else {
        画布.beginFill(填充颜色, 100);
    }

    画布.moveTo(点集[0].x, 点集[0].y);
    for (var i = 1; i < 点集.length; i++) {
        画布.lineTo(点集[i].x, 点集[i].y);
    }
    画布.lineTo(点集[0].x, 点集[0].y);
    画布.endFill();
};

_root.残影系统.绘制到画布 = function(影片剪辑, 调整颜色) {
    if (!影片剪辑)
        return;
    var 画布 = this.获得当前画布();
    if (!调整颜色)
        调整颜色 = _root.色彩引擎.空调整颜色;

    // 清空当前画布的矢量绘制
    画布.clear();
    
    // 利用 duplicateMovieClip 复制影片剪辑的矢量内容到当前画布
    var ghostName = "ghost_" + 画布.getNextHighestDepth();
    影片剪辑.duplicateMovieClip(ghostName, 画布.getNextHighestDepth());
    var ghost = 画布[ghostName];
    
    // 累积从影片剪辑到游戏世界的所有变换矩阵
    var mc = 影片剪辑;
    var totalMatrix = new flash.geom.Matrix();
    var 游戏世界 = _root.gameworld;
    while (mc != undefined && mc != 游戏世界) {
        var mtx = mc.transform.matrix;
        totalMatrix.concat(mtx);
        mc = mc._parent;
    }
    // 为简化，这里直接应用累积的平移；比例、旋转可按需要进一步计算
    ghost._x = totalMatrix.tx;
    ghost._y = totalMatrix.ty;
    ghost._xscale = 影片剪辑._xscale;
    ghost._yscale = 影片剪辑._yscale;
    
    // 应用颜色调整（如果有）
    if (调整颜色) {
        ghost.transform.colorTransform = 调整颜色;
    }
};

_root.残影系统.获得当前画布 = function() {
    if (!this.当前画布) {
        var 残影系统挂载层 = _root.gameworld.deadbody;
        if (残影系统挂载层.残影画布池.length > 0) {
            this.当前画布 = 残影系统挂载层.残影画布池.pop();
        } else {
            this.当前画布 = this.创建画布(残影系统挂载层);
        }
        var 画布 = this.当前画布;
        画布._visible = true;
        画布._alpha = 100;
        画布.循环任务ID = _root.帧计时器.添加任务(this.画布循环任务, this.残影刷新时间, this.残影数量, 画布, 残影系统挂载层);
        画布.循环次数 = this.残影数量;
        画布.当前循环次数 = 1;
        画布.onUnload = function() {
            _root.帧计时器.移除任务(画布.循环任务ID);
            _root.残影系统.当前画布 = null;
        };
    }
    return this.当前画布;
};

_root.残影系统.画布循环任务 = function(画布, 残影系统挂载层) {
    if (画布.当前循环次数 >= 画布.循环次数) {
        画布._visible = false;
        画布.clear();
        残影系统挂载层.残影画布池.push(画布);
    } else {
        画布._alpha -= _root.残影系统.残影透明度衰减;
        if (画布.当前循环次数 === 1 && _root.残影系统.当前画布 === 画布) {
            _root.残影系统.当前画布 = null;
        }
        画布.当前循环次数++;
    }
};

_root.残影系统.创建画布 = function(残影系统挂载层) {
    if (!残影系统挂载层.残影系统存在) {
        残影系统挂载层.残影系统存在 = true;
        残影系统挂载层.残影画布数量 = 0;
        残影系统挂载层.残影画布池 = [];
    }
    var 画布 = 残影系统挂载层.createEmptyMovieClip("画布" + ++残影系统挂载层.残影画布数量, 残影系统挂载层.getNextHighestDepth());
    画布.clear();
    return 画布;
};