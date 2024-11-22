_root.当前效果总数 = 0;
_root.当前画面效果总数 = 0;
_root.画面效果存在时间 = 1 * 1000;

_root.效果系统 = {};

// 初始化效果池
_root.效果系统.初始化效果池 = function() {
    var 游戏世界 = _root.gameworld;
    游戏世界.可用效果池 = {};
    _root.当前效果总数 = 0;

    // 设置 `可用效果池` 为不可枚举
    _global.ASSetPropFlags(游戏世界, ["可用效果池"], 1, true);
};

// 获取或创建原型效果（懒加载）
_root.效果系统.获取或创建原型效果 = function(效果种类) {
    var 游戏世界 = _root.gameworld;
    if (this.效果映射表[效果种类].原型) {
        return this.效果映射表[效果种类].原型;
    }
    var 世界效果 = 游戏世界.效果;
    var 原型效果 = 世界效果.attachMovie(效果种类, "prototype_" + 效果种类, 世界效果.getNextHighestDepth());
    原型效果._visible = false; // 原型效果不可见
    this.效果映射表[效果种类].原型 = 原型效果;
    return 原型效果;
};

// 创建效果（使用原型模式和懒加载）
_root.效果系统.创建效果 = function(效果种类, myX, myY) {
    var 原型效果 = this.获取或创建原型效果(效果种类);
    var 游戏世界 = _root.gameworld;
    var 世界效果 = 游戏世界.效果;
    var 效果深度 = 世界效果.getNextHighestDepth();
    var 创建的效果 = 原型效果.duplicateMovieClip(效果种类 + " " + 效果深度, 效果深度);
    创建的效果._x = myX;
    创建的效果._y = myY;
    创建的效果._visible = true;
    this.初始化效果行为(创建的效果);
    return 创建的效果;
};

// 初始化效果行为
_root.效果系统.初始化效果行为 = function(效果) {
    效果.old_removeMovieClip = 效果.removeMovieClip;

    效果.removeMovieClip = function(是否销毁) {
        if (!_root.帧计时器.是否死亡特效 || 是否销毁) {
            this.old_removeMovieClip();
        } else {
            var 效果池 = _root.gameworld.可用效果池[this.效果种类];
            if (!效果池) {
                效果池 = _root.gameworld.可用效果池[this.效果种类] = [];
            }
            delete this.onEnterFrame;
            this.stop();
            this._visible = false;
            效果池.push(this);
            _root.当前效果总数--;
        }
    };

    效果.onUnload = function() {
        this.removeMovieClip(true);
    };
};

// 发射效果
_root.效果 = function(效果种类, myX, myY, 方向, 必然触发) {
    if (!效果种类) return;

    if (_root.是否视觉元素 && (_root.当前效果总数 <= _root.效果上限 || _root.成功率(_root.效果上限 / 5)) || 必然触发) {
        var 游戏世界 = _root.gameworld;
        if (!游戏世界.可用效果池) _root.效果系统.初始化效果池();
        var 效果池 = 游戏世界.可用效果池[效果种类];

        if (效果池.length > 0) {
            var 新效果 = 效果池.pop();
            新效果._x = myX;
            新效果._y = myY;
            新效果._visible = true;
            新效果.gotoAndPlay(1);
        } else {
            var 新效果 = _root.效果系统.创建效果(效果种类, myX, myY);
        }

        if (新效果) {
            新效果._x = myX;
            新效果._y = myY;
            新效果._xscale = 方向;
            _root.当前效果总数++;
        }

        return 新效果;
    }
};

// 发射画面效果
_root.画面效果 = function(效果种类, myX, myY, 方向, 必然触发) {
    if (_root.是否视觉元素 && (_root.当前画面效果总数 <= _root.画面效果上限 || _root.成功率(_root.画面效果上限 / 5)) || 必然触发) {
        var 效果深度 = _root.getNextHighestDepth();
        var 效果名 = "mc" + 效果深度;
        _root.attachMovie(效果种类, 效果名, 效果深度);
        _root[效果名]._x = myX;
        _root[效果名]._y = myY;
        _root[效果名]._xscale = 方向;
        _root.当前画面效果总数++;

        // 添加定时器，销毁画面效果
        var 定时器ID = _root.帧计时器.添加单次任务(function() {
            _root.当前画面效果总数--;
        }, _root.画面效果存在时间);
    }
};
