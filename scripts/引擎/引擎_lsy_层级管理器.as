_root.层级管理器 = new Object();
_root.层级管理器.highest = 1023; // 从1024开始创建新层级

_root.层级管理器.mouse = 65535; // 鼠标
_root.层级管理器.soundManager = 65534; // 音效管理器
_root.层级管理器.注释框 = 65533; // 注释框
_root.层级管理器.musicManager = 65532; // BGM管理器

//重写获取root新层级的函数
// _root.original_getNextHighestDepth = _root.getNextHighestDepth;
_root.getNextHighestDepth = function(){
    //从1024开始创建新层级
    _root.层级管理器.highest++;
    return _root.层级管理器.highest;
}

//每次跳转地图时调用
_root.层级管理器.检查层级范围 = function(){
    if(this.highest > 32767) this.highest = 1023;
}

_root.最上层加载外部动画 = function(动画路径){
	_root.外部动画加载壳mc._x = 0;
	_root.外部动画加载壳mc._y = 0;
	_root.外部动画加载壳mc._xscale = 100;
	_root.外部动画加载壳mc._yscale = 100;
	_root.外部动画加载壳mc.loadMovie(动画路径);
}

// _root.发布公告 = function(消息)
// {
// 	_root.叹号公告窗._visible = true;
// 	_root.叹号公告窗.gotoAndPlay(1);
// 	_root.叹号公告窗.txt = 消息;
// }
