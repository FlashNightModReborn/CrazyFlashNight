// boot 收尾：删掉 stage-wrap 注入的引导脚手架（_root.__boot 持有 f2..f41 及 chunk 子函数 f36_1.. 等约 33 个
// 一次性 wrapper），boot 完成后即死代码。删除回收这些函数对象 + 移除 _root 上唯一的 __boot 属性，避免常驻污染。
// （游戏 API 是各 staged 函数定义的 _root.X，已落在 _root 上，与 __boot 无关，不受影响。）
delete _root.__boot;
_root.play();
this.stop();
this.removeMovieClip();