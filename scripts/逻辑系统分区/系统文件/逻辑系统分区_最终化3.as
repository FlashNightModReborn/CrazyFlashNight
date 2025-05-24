for (var index in _root.loaderkillers)
{
    _root.loaderkillers[index]();
}

delete _root.preloaders;
delete _root.loaders;
delete _root.loaderkillers;