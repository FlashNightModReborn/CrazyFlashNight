// _root.鼠标 兼容代理
//
// 主时间轴旧鼠标 MovieClip 移除后，旧 UI 仍会调用：
//   _root.鼠标.gotoAndStop(...)
//   _root.鼠标.物品图标容器.attachMovie(...)
// 本代理只保留兼容接口。手型视觉交给 Launcher WebView overlay；
// 物品拖拽图标暂留 AS2 端，并且只在拖拽期间同步位置。

if (_root.鼠标代理 == undefined) _root.鼠标代理 = {};

_root.鼠标代理.普通状态 = "normal";
_root.鼠标代理.当前状态 = "normal";
_root.鼠标代理.拖拽中 = false;
_root.鼠标代理.上次发送签名 = null;

_root.鼠标代理.状态映射 = {};
_root.鼠标代理.状态映射["1"] = "normal";
_root.鼠标代理.状态映射["手型普通"] = "normal";
_root.鼠标代理.状态映射["手型点击"] = "click";
_root.鼠标代理.状态映射["手型准备抓取"] = "hoverGrab";
_root.鼠标代理.状态映射["手型抓取"] = "grab";
_root.鼠标代理.状态映射["手型攻击"] = "attack";
_root.鼠标代理.状态映射["开门"] = "openDoor";

_root.鼠标代理.确保容器 = function():MovieClip {
    var depth:Number = (_root.层级管理器 != undefined && _root.层级管理器.mouse != undefined)
        ? _root.层级管理器.mouse
        : 65535;

    if (_root.鼠标图标层 == undefined) {
        _root.createEmptyMovieClip("鼠标图标层", depth);
    }

    if (_root.鼠标图标层.物品图标容器 == undefined) {
        _root.鼠标图标层.createEmptyMovieClip("物品图标容器", 0);
    }

    if (_root.鼠标图标层.物品图标容器.__鼠标代理已包装 != true) {
        var rawAttach:Function = _root.鼠标图标层.物品图标容器.attachMovie;
        _root.鼠标图标层.物品图标容器.__鼠标代理原始AttachMovie = rawAttach;
        _root.鼠标图标层.物品图标容器.attachMovie = function(linkage:String, name:String, depth:Number) {
            var child:MovieClip = this.__鼠标代理原始AttachMovie(linkage, name, depth);
            if (child != undefined) {
                var rawRemove:Function = child.removeMovieClip;
                child.__鼠标代理原始RemoveMovieClip = rawRemove;
                child.removeMovieClip = function():Void {
                    this.__鼠标代理原始RemoveMovieClip();
                    _root.鼠标代理.停止拖拽同步();
                    _root.鼠标代理.发送状态(_root.鼠标代理.当前状态);
                };
                _root.鼠标代理.启用拖拽同步();
            }
            return child;
        };
        _root.鼠标图标层.物品图标容器.__鼠标代理已包装 = true;
    }

    return _root.鼠标图标层.物品图标容器;
};

_root.鼠标代理.标准化状态 = function(state):String {
    var key:String = String(state);
    var mapped:String = _root.鼠标代理.状态映射[key];
    if (mapped == undefined) return key;
    return mapped;
};

_root.鼠标代理.发送状态 = function(state:String):Void {
    var signature:String = state + "|" + (_root.鼠标代理.拖拽中 ? "1" : "0");
    if (_root.鼠标代理.上次发送签名 == signature) return;
    _root.鼠标代理.上次发送签名 = signature;

    if (_root.server == undefined || !_root.server.isSocketConnected) return;
    _root.server.sendTaskToNode("cursor_control", {
        state: state,
        dragging: _root.鼠标代理.拖拽中
    });
};

_root.鼠标代理.同步拖拽位置 = function():Void {
    var layer:MovieClip = _root.鼠标图标层;
    if (layer == undefined) return;
    layer._x = _root._xmouse;
    layer._y = _root._ymouse;
};

_root.鼠标代理.启用拖拽同步 = function():Void {
    if (_root.鼠标代理.拖拽中) return;
    _root.鼠标代理.拖拽中 = true;
    _root.鼠标代理.同步拖拽位置();
    _root.鼠标图标层.onEnterFrame = function() {
        _root.鼠标代理.同步拖拽位置();
    };
    _root.鼠标代理.发送状态(_root.鼠标代理.当前状态);
};

_root.鼠标代理.停止拖拽同步 = function():Void {
    if (!_root.鼠标代理.拖拽中) return;
    _root.鼠标代理.拖拽中 = false;
    delete _root.鼠标图标层.onEnterFrame;
    _root.鼠标代理.发送状态(_root.鼠标代理.当前状态);
};

_root.鼠标代理.清理拖拽图标 = function():Void {
    var container:MovieClip = _root.鼠标代理.确保容器();
    if (container.物品图标 != undefined) {
        container.物品图标.removeMovieClip();
    }
    _root.鼠标代理.停止拖拽同步();
};

_root.鼠标代理.设置状态 = function(state):Void {
    var normalized:String = _root.鼠标代理.标准化状态(state);
    _root.鼠标代理.当前状态 = normalized;

    if (normalized == "grab") {
        _root.鼠标代理.启用拖拽同步();
    } else if (normalized == "normal") {
        _root.鼠标代理.停止拖拽同步();
    }

    _root.鼠标代理.发送状态(normalized);
};

_root.鼠标代理.安装 = function():Void {
    var container:MovieClip = _root.鼠标代理.确保容器();
    var proxy:Object = {};

    proxy.物品图标容器 = container;
    proxy._visible = false;
    proxy._x = _root._xmouse;
    proxy._y = _root._ymouse;
    proxy._currentframe = 1;
    proxy.gotoAndStop = function(state):Void {
        _root.鼠标代理.设置状态(state);
    };
    proxy.gotoAndPlay = function(state):Void {
        _root.鼠标代理.设置状态(state);
    };
    proxy.removeMovieClip = function():Void {
        _root.鼠标代理.清理拖拽图标();
    };

    _root.鼠标 = proxy;
    _root.鼠标代理.发送状态(_root.鼠标代理.普通状态);
};

_root.鼠标代理.安装();
