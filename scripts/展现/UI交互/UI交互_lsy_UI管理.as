_root.加载外部UI = function(url){
    _root.外部导入UI界面._visible = true;
    _root.外部导入UI界面.loadMovie(url);
}

_root.卸载外部UI = function(){
    _root.外部导入UI界面.unloadMovie();
}