_root.preloaders.push(function()
{
    this.shops_jsons_list = new XML();
    this.shops_jsons_list.ignoreWhite = true;
    this.shops_strarrs = [];
    this.shops_jsons_list.onLoad = function(success)
    {
        var files = [];
        _root.XmlNodeToDict(this.lastChild,null,function(name, value)
        {
            if(name == "shops")
            {
                files.push(value);
            }
            return null;
        });
        for (var i = 0; i < files.length; i++)
        {
            _root.preloaders.shops_strarrs.push([]);
            _root.GetFileByPath("data/shops/" + files[i], _root.preloaders.shops_strarrs[i]);
        }
    };

    this.shops_jsons_list.load("data/shops/list.xml");
})

_root.loaders.push(function ()
{
    this.shops_srcs = [];
    this.shops = {};
    this.json_parser = new LiteJSON();

    for (var i = 0; i < _root.preloaders.shops_strarrs.length; i++)
    {
        this.shops_srcs.push(_root.preloaders.shops_strarrs[i].join(""));
    }

    for (var i = 0; i < this.shops_srcs.length; i++)
    {
        this.parsedshop = this.json_parser.parse(this.shops_srcs[i]);
        for (var key in this.parsedshop)
        {
            this.shops[key] = this.parsedshop[key];
        }
    }

    _root.shops = this.shops;
});