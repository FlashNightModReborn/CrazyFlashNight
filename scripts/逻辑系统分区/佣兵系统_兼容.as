_root.preloaders.push(function()
{
    this.merc_jsons_list = new XML();
    this.merc_jsons_list.ignoreWhite = true;
    this.merc_sources = [];
    this.merc_jsons_list.onLoad = function(success)
    {
        var sources = _root.preloaders.merc_sources;
        var sourcesByPath = {};
        _root.XmlNodeToDict(this.lastChild, null, function(name, value)
        {
            if (name == "merc")
            {
                var path = "data/merc/" + value;
                var source = sourcesByPath[path];
                if (source == undefined)
                {
                    source = {chunks: []};
                    sourcesByPath[path] = source;
                    _root.GetFileByPath(path, source.chunks);
                }
                sources.push(source);
            }
            return null;
        });
        // 只给本次 XML 实例签收，所有二级 GetFileByPath 已在上面登记。
        if (success === true && this.lastChild != null) this.__bootChildrenIssued = true;
    };

    this.merc_jsons_list.load("data/merc/list.xml");
});

_root.loaders.push(function ()
{
    var parser = new LiteJSON();
    var rows = [];
    var sources = _root.preloaders.merc_sources;
    for (var i = 0; i < sources.length; i++)
    {
        var source = sources[i];
        if (source.chunks != undefined)
        {
            source.rows = parser.parse(source.chunks.join(""));
            delete source.chunks;
        }
        rows = rows.concat(source.rows);
    }
    // 启动等待门已确认文件落地，定稿后由 MercLibrary 持有唯一的定义集合。
    delete _root.preloaders.merc_sources;
    delete _root.preloaders.merc_jsons_list;
    org.flashNight.arki.merc.MercLibrary.installDefinitions(rows);
});