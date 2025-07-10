_root.对话框UI = new Object();

_root.对话框UI.loadPortraitDict = new Object();
_root.对话框UI.loadPortraitList = new Array();

//使用BaseLoader导入list
var portraitLoader = new org.flashNight.gesh.xml.LoadXml.BaseXMLLoader("flashswf/portraits/list.xml");
portraitLoader.load(function(data:Object):Void {
    var portraits = data.portrait;
    for (var i=0; i<portraits.length; i++) {
        _root.对话框UI.loadPortraitDict[data.portrait[i]] = {instance:null, depth:i};
    }
}, function():Void {
    onError();
});

_root.对话框UI.清理外部立绘缓存 = function(保留数量){
    if(isNaN(保留数量)) 保留数量 = 3;
    if(保留数量 < 0) 保留数量 = 0;
    if(this.loadPortraitList.length > 保留数量){
        var cutlen = this.loadPortraitList.length - 保留数量;
        for(var i = cutlen - 1; i > -1; i--){
            var portraitInfo = this.loadPortraitDict[this.loadPortraitList[i]];
            portraitInfo.instance.removeMovieClip();
            portraitInfo.instance = null;
        }
        this.loadPortraitList.splice(0, cutlen);
        // _root.发布消息("清理",cutlen,"个外部立绘缓存");
    }
}




_root.对话框UI.刷新内容 = function(){
    var dialogueInfo = 本轮对话内容[对话进度];
    if (dialogueInfo[3] != undefined){
        this._visible = true;
        var 上句人物名字 = 人物名字;
        if (dialogueInfo[0] == "角色名" || dialogueInfo[0] == _root.角色名){
            人物名字 = _root.角色名;
        }else{
            人物名字 = dialogueInfo[0];
        }
        人物称号 = _root.获得翻译(dialogueInfo[1]);
        if (人物称号 == null){
            人物称号 = "";
        }
        头像图标帧名 = dialogueInfo[2];
        if (头像图标帧名 == null || 头像图标帧名 == ""){
            头像图标帧名 = "无头像";
        }
        if (头像图标帧名 == "主角模板" && 上句人物名字 != 人物名字){
            肖像.肖像.gotoAndStop("刷新");
        }
        对话内容 = dialogueInfo[3];
        人物表情 = dialogueInfo[4];
        if (人物表情 == null) 人物表情 = "普通";
        对话对象 = dialogueInfo[5];
        // 直接加载立绘 / 从外部文件导入立绘
        if(_root.对话框UI.loadPortraitDict[头像图标帧名] != null){
            刷新外部导入立绘();
        }else {
            刷新立绘();
        }
        // 加载对话图片
        对话图片 = dialogueInfo[6];
        if (typeof 对话图片 == "string" && 对话图片 != ""){
            if (对话图片 == "close"){
                _root.图片容器.卸载图片();
            }else{
                _root.图片容器.加载图片(对话图片);
            }
        }
        // 
        打字内容 = "";
        this.onEnterFrame = function(){
            打字(对话内容);
        };
    }else{
        gotoAndStop("close");
    }
}

_root.对话框UI.刷新立绘 = function(){
    if(this.当前立绘 !== 肖像) this.当前立绘._visible = false;
    this.肖像._visible = true;
    this.当前立绘 = 肖像;
    肖像.gotoAndStop(头像图标帧名);
    肖像.肖像.stop();
    肖像.肖像.gotoAndStop(人物表情);
    肖像.肖像.man.头.头.基本款.gotoAndStop(人物表情);
}

_root.对话框UI.刷新外部导入立绘 = function(){
    this.肖像._visible = false;
    var portraitInfo = _root.对话框UI.loadPortraitDict[头像图标帧名];
    if(portraitInfo.instance == null){
        portraitInfo.instance = this.外部立绘层.createEmptyMovieClip(头像图标帧名, portraitInfo.depth);
        _root.对话框UI.loadPortraitList.push(头像图标帧名);
        portraitInfo.instance.loadMovie("flashswf/portraits/" + 头像图标帧名 + ".swf");
    }
    if(this.当前立绘 !== portraitInfo.instance) this.当前立绘._visible = false;
    portraitInfo.instance._visible = true;
    portraitInfo.instance.gotoAndStop(人物表情);
    this.当前立绘 = portraitInfo.instance;
}

_root.对话框UI.打字 = function(fonts){
    if (this.i < length(fonts)){
        this.是否打印完毕 = false;
        打字内容 += fonts.substr(this.i, 1);
        this.i = this.i + 1;
    }
    if (this.i >= length(fonts)){
        结束打字();
    }
}

_root.对话框UI.结束打字 = function(){
    if (!this.是否打印完毕){
        打字内容 = 对话内容;
        delete this.onEnterFrame;
        对话进度++;
        this.是否打印完毕 = true;
        this.i = 0;
    }
}

_root.对话框UI.下一句 = function(){
    if (对话进度 < 对话条数){
        if (this.是否打印完毕){
            刷新内容();
        }else{
            结束打字();
        }
    }else{
        gotoAndStop("close");
    }
}

_root.对话框UI.close = function(){
    this._visible = false;
    本轮对话内容 = [];
    对话条数 = 0;
    人物名字 = null;
    人物表情 = null;
    _root.暂停 = false;
    图片容器.卸载图片();
    // if (结束对话后是否跳转帧){
    //     _root.淡出动画.淡出跳转帧(结束对话后跳转帧);
    //     结束对话后跳转帧 = "";
    //     结束对话后是否跳转帧 = false;
    // }
    if(this.followingEvent.name){
        if(this.followingEvent.args){
           _root.gameworld.dispatcher.publish.apply(_root.gameworld.dispatcher, this.followingEvent.args);
        }else{
            _root.gameworld.dispatcher.publish(this.followingEvent.name);
        }
        this.followingEvent = null;
    }
}


_root.对话框UI.初始化对话框界面 = function(对话框界面:MovieClip){
    对话框界面.刷新内容 = _root.对话框UI.刷新内容;
    对话框界面.打字 = _root.对话框UI.打字;
    对话框界面.结束打字 = _root.对话框UI.结束打字;
    对话框界面.下一句 = _root.对话框UI.下一句;
    对话框界面.close = _root.对话框UI.close;

    对话框界面.刷新立绘 = _root.对话框UI.刷新立绘;
    对话框界面.刷新外部导入立绘 = _root.对话框UI.刷新外部导入立绘;

    对话框界面.gotoAndStop("close");
}


_root.初始化人物立绘 = function(target){
    target.stop();
    target.gotoAndStop(target._parent._parent.人物表情);
}
