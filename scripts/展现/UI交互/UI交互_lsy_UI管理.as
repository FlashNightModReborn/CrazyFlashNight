_root.加载外部UI = function(url){
    _root.通用UI层.外部导入UI界面._visible = true;
    if(url != _root.通用UI层.外部UIURL){
        _root.通用UI层.外部UIURL = url;
        _root.通用UI层.外部导入UI界面._x = 0;
        _root.通用UI层.外部导入UI界面._y = 0;
        _root.通用UI层.外部导入UI界面._xscale = 100;
        _root.通用UI层.外部导入UI界面._yscale = 100;
        _root.通用UI层.外部导入UI界面.loadMovie(url);
    }
}

_root.从库中加载外部UI = function(identifier){
    var UI = _root.通用UI层[identifier];
    if(UI != null){
        UI._visible = true;
        return UI;
    }
    if(!_root.通用UI层.外部UI列表) _root.通用UI层.外部UI列表 = [];
    UI = _root.通用UI层.attachMovie(identifier,identifier,_root.通用UI层.getNextHighestDepth());
    _root.通用UI层.外部UI列表.push(UI);
    return UI;

}

_root.卸载外部UI = function(){
    _root.通用UI层.外部UIURL = null;
    _root.通用UI层.外部导入UI界面.unloadMovie();
    for(var i = 0; i<_root.通用UI层.外部UI列表.length; i++){
        _root.通用UI层.外部UI列表[i].removeMovieClip();
    }
    _root.通用UI层.外部UI列表 = null;
}


//全屏UI层管理
_root.从库中加载全屏UI = function(identifier){
    if(_root.全屏UI层.当前UI != null) _root.卸载全屏UI();
    _root.全屏UI层.当前UI = _root.全屏UI层.attachMovie(identifier, identifier, 0);
    return _root.全屏UI层.当前UI;
}

_root.卸载全屏UI = function(){
    _root.全屏UI层.当前UI.removeMovieClip();
    _root.全屏UI层.当前UI = null;
    _root.全屏UI层.引导界面.unloadMovie();
}

_root.加载引导界面 = function(filename){
    _root.全屏UI层.引导界面._visible = true;
    _root.全屏UI层.引导界面._alpha = 100;
    _root.全屏UI层.引导界面.loadMovie("flashswf/UI/引导界面合集/" + filename + ".swf");
}

_root.最上层发布文字提示 = function(消息){
    _root.全屏UI层.文字提示列表.push(消息);
    if(_root.全屏UI层.getActiveTextCount() == 0){
        _root.全屏UI层.tickCOunt = 0;
    }
}