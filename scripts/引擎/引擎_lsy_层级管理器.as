#include "../引擎/引擎_lsy_根层级分配.as"

_root.层级管理器.mouse = 65535; // 鼠标
_root.层级管理器.soundManager = 65534; // 音效管理器
_root.层级管理器.注释框 = 65533; // 注释框
_root.层级管理器.musicManager = 65532; // BGM管理器
// 65531 预留给 asLoaderBootstrap.as 的 _root.__asLoaderCode 持久代码模块容器

//每次跳转地图时调用
_root.层级管理器.检查层级范围 = function(){
    if(this.highest > 32767) this.highest = 1023;
}

_root.最上层加载外部动画 = function(动画路径, 是否暂停){
	_root.外部动画加载壳mc._x = 0;
	_root.外部动画加载壳mc._y = 0;
	_root.外部动画加载壳mc._xscale = 100;
	_root.外部动画加载壳mc._yscale = 100;
	org.flashNight.arki.scene.CutsceneService.play(动画路径, 是否暂停 === true);
}

// _root.发布公告 = function(消息)
// {
// 	_root.叹号公告窗._visible = true;
// 	_root.叹号公告窗.gotoAndPlay(1);
// 	_root.叹号公告窗.txt = 消息;
// }
