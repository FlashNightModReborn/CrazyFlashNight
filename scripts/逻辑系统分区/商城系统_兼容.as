_root.preloaders.push(function()
{
    this.kshop_jsons_list = new XML();
    this.kshop_jsons_list.ignoreWhite = true;
    this.kshop_strarrs = [];
    this.kshop_jsons_list.onLoad = function(success)
    {
        var files = [];
        _root.XmlNodeToDict(this.lastChild,null,function(name, value)
        {
            if(name == "kshop")
            {
                files.push(value);
            }
            return null;
        });
        for (var i = 0; i < files.length; i++)
        {
            _root.preloaders.kshop_strarrs.push([]);
            _root.GetFileByPath("data/kshop/" + files[i], _root.preloaders.kshop_strarrs[i]);
        }
    };

    this.kshop_jsons_list.load("data/kshop/list.xml");
});

_root.loaders.push(function ()
{
    this.kshop_srcs = [];
    this.kshop_list = [];
    this.json_parser = new LiteJSON();

    for (var i = 0; i < _root.preloaders.kshop_strarrs.length; i++)
    {
        this.kshop_srcs.push(_root.preloaders.kshop_strarrs[i].join(""));
    }
    for (var i = 0; i < this.kshop_srcs.length; i++)
    {
        this.kshop_list = this.kshop_list.concat(this.json_parser.parse(this.kshop_srcs[i]));
    }

    _root.kshop_list = this.kshop_list;
});