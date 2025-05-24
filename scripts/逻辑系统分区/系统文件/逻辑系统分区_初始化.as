_root.LogicSystems = new Array();
_root.LogicSystemAlloct = new Allocator(_root.LogicSystems);
_root.LogicSystemDict = new Object();

_root.GetLogicSystem = function (name: String): Object
{
    return _root.LogicSystems[_root.LogicSystemDict[name]];
};

_root.preloaders = new Array();
_root.preloaders.current = 0;

_root.loaders = new Array();
_root.loaders.current = 0;

_root.loaderkillers = new Array();
