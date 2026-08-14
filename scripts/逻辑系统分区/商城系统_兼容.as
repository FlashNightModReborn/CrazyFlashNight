_root.preloaders.push(function()
{
    if (_root.__boot == undefined) _root.__boot = {};
    _root.__boot.kshopCatalogReady = false;
    _root.__boot.kshopCatalogFailed = false;
    this.kshop_jsons_list = new XML();
    this.kshop_jsons_list.ignoreWhite = true;
    this.kshop_strarrs = [];
    this.kshop_list_loaded = false;
    this.kshop_expected_file_count = 0;
    this.kshop_jsons_list.onLoad = function(success)
    {
        // 与 NPC 商店目录相同：失败一旦落地，迟到的 list.xml success 不得翻转状态。
        if (_root.__boot.kshopCatalogFailed == true) return;
        if (success != true || this.lastChild == null)
        {
            _root.__boot.kshopCatalogReady = false;
            _root.__boot.kshopCatalogFailed = true;
            return;
        }
        var files = [];
        var validList:Boolean = true;
        try
        {
            _root.XmlNodeToDict(this.lastChild,null,function(name, value)
            {
                if(name == "kshop")
                {
                    if (typeof value != "string" || value.length == 0) validList = false;
                    else files.push(value);
                }
                return null;
            });
        }
        catch (error)
        {
            validList = false;
        }
        if (!validList || files.length < 1)
        {
            _root.__boot.kshopCatalogReady = false;
            _root.__boot.kshopCatalogFailed = true;
            return;
        }
        _root.preloaders.kshop_expected_file_count = files.length;
        for (var i = 0; i < files.length; i++)
        {
            _root.preloaders.kshop_strarrs.push([]);
            _root.GetFileByPath("data/kshop/" + files[i], _root.preloaders.kshop_strarrs[i]);
        }
        _root.preloaders.kshop_list_loaded = true;
    };

    this.kshop_jsons_list.load("data/kshop/list.xml");
});

_root.loaders.push(function ()
{
    if (_root.__boot.kshopCatalogFailed == true
            || _root.preloaders.kshop_list_loaded != true)
    {
        _root.__boot.kshopCatalogReady = false;
        _root.__boot.kshopCatalogFailed = true;
        return;
    }

    this.kshop_srcs = [];
    this.kshop_list = [];
    this.json_parser = new LiteJSON();

    var expectedCount:Number = Number(_root.preloaders.kshop_expected_file_count);
    if (isNaN(expectedCount) || expectedCount < 1 || Math.floor(expectedCount) != expectedCount
            || _root.preloaders.kshop_strarrs.length != expectedCount)
    {
        _root.__boot.kshopCatalogReady = false;
        _root.__boot.kshopCatalogFailed = true;
        return;
    }
    for (var i = 0; i < _root.preloaders.kshop_strarrs.length; i++)
    {
        var chunks:Array = _root.preloaders.kshop_strarrs[i];
        if (!(chunks instanceof Array) || chunks.length != 1
                || typeof chunks[0] != "string" || chunks[0].length == 0)
        {
            _root.__boot.kshopCatalogReady = false;
            _root.__boot.kshopCatalogFailed = true;
            return;
        }
        this.kshop_srcs.push(chunks[0]);
    }
    for (var i = 0; i < this.kshop_srcs.length; i++)
    {
        var parsedCatalog;
        try
        {
            parsedCatalog = this.json_parser.parse(this.kshop_srcs[i]);
        }
        catch (error)
        {
            _root.__boot.kshopCatalogReady = false;
            _root.__boot.kshopCatalogFailed = true;
            return;
        }
        if (!(parsedCatalog instanceof Array) || parsedCatalog.length < 1)
        {
            _root.__boot.kshopCatalogReady = false;
            _root.__boot.kshopCatalogFailed = true;
            return;
        }
        this.kshop_list = this.kshop_list.concat(parsedCatalog);
    }

    if (_root.__boot.kshopCatalogFailed == true) return;
    _root.kshop_list = this.kshop_list;
    _root.__boot.kshopCatalogReady = true;
});
