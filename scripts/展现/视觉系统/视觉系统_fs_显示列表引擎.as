// 定义显示列表系统
_root.显示列表 = {};

// 初始化显示列表系统
_root.显示列表.初始化 = function() {
    this.列表 = {};
    this.任务ID计数器 = 0;
};

_root.显示列表.初始化();

// 定义默认的播放动画方法
_root.显示列表.默认播放动画 = function(clip) {
    //_root.服务器.发布服务器消息(clip + "_播放到 ：" + clip._currentframe);
    if (clip._currentframe == clip._totalframes) {
        clip.gotoAndStop(1);
    } else {
        clip.nextFrame();
    }
};

// 优化后的添加影片剪辑方法
_root.显示列表.添加影片剪辑 = function(影片剪辑, 播放动画函数 /*, ...额外参数*/) {
    var 任务ID = ++this.任务ID计数器;
    var 参数数组 = arguments.length > 2 ? Array.prototype.slice.call(arguments, 2) : [];

    this.列表[任务ID] = {
        id: 任务ID,
        影片剪辑: 影片剪辑,
        是否播放中: true,
        播放动画: 播放动画函数 
            ? function() { 播放动画函数.apply(影片剪辑, 参数数组); }
            : function() { _root.显示列表.默认播放动画(影片剪辑); },
        参数数组: 参数数组
    };
    return 任务ID;
};

// 移除影片剪辑的方法
_root.显示列表.移除影片剪辑 = function(任务ID) {
    delete this.列表[任务ID];
};

// 暂停和继续播放的方法
_root.显示列表.暂停播放 = function(任务ID) {
    if (this.列表[任务ID]) {
        this.列表[任务ID].是否播放中 = false;
    }
};

_root.显示列表.继续播放 = function(任务ID) {
    if (this.列表[任务ID]) {
        this.列表[任务ID].是否播放中 = true;
    }
};

// 每帧更新播放列表的方法，检查影片剪辑是否已卸载
_root.显示列表.播放列表 = function() {
    for (var key in this.列表) {
        var item = this.列表[key];
        if (item.影片剪辑._x == undefined) {
            this.移除影片剪辑(key); // 如果影片剪辑已卸载，则移除
        } else if (item.是否播放中) {
            item.播放动画();
        }
    }
};
_root.显示列表
.预设列表初始化 = function() {
    var 默认播放动画 = _root.显示列表.默认播放动画;
    this.预设任务ID = this.添加影片剪辑(_root, function()
    {
        默认播放动画(_root.玩家信息界面.快捷药剂界面.姓名框);
        默认播放动画(_root.玩家信息界面.快捷药剂界面.姓名框.网格动画);
        默认播放动画(_root.玩家信息界面.主角hp显示界面.血槽内动画);
        默认播放动画(_root.玩家信息界面.主角hp显示界面.网格动画);
        默认播放动画(_root.玩家信息界面.主角hp显示界面.血槽光效);
    });
}

_root.显示列表.预设列表初始化();