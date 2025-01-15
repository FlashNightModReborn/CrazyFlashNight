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
    if(_root.通用UI层[identifier] != null){
        _root.通用UI层[identifier]._visible = true;
        return;
    }
    if(!_root.通用UI层.外部UI列表) _root.通用UI层.外部UI列表 = [];
    var UI = _root.通用UI层.attachMovie(identifier,identifier,_root.通用UI层.getNextHighestDepth());
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

