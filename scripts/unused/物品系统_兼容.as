import org.flashNight.naki.Sort.*;
_root.preloaders.push(function()
{
    this.items_xmls_list = new XML();
    this.items_xmls_list.ignoreWhite = true;
    this.items_strarrs = [];
    this.items_xmls_list.onLoad = function(success)
    {
        var files = [];
        _root.XmlNodeToDict(this.lastChild,null,function(name, value)
        {
            if(name == "items")
            {
                files.push(value);
            }
            return null;
        });
        var _loc4_ = 0;
        while(_loc4_ < files.length)
        {
            _root.preloaders.items_strarrs.push([]);
            _root.GetFileByPath("data/items/" + files[_loc4_], _root.preloaders.items_strarrs[_loc4_]);
            _loc4_ += 1;
        }
    };

    this.items_xmls_list.load("data/items/list.xml");
});

_root.loaders.push(function ()
{
    this.items_srcs = [];
    this.count = _root.preloaders.items_strarrs.length;
    this.物品属性列表 = {};
    this.id物品名对应表 = {};

    for (var i = 0; i < this.count; i++)
    {
        this.items_srcs.push(_root.preloaders.items_strarrs[i].join(""));
    }

    for (var i = 0; i < this.count; i++)
    {
        this.itemsxml = new XML();
        this.itemsxml.ignoreWhite = true;
        this.itemsxml.parseXML(this.items_srcs[i]);
        this.tmp = _root.XmlNodeToDict(this.itemsxml.firstChild, "name", function (name, value)
        {
            return _root.StringClassify(value);
        });
        for (var key in this.tmp)
        {
            this.物品属性列表[key] = this.tmp[key];
        }
    }

    for (var index in this.物品属性列表)
    {
        this.id物品名对应表[this.物品属性列表[index].id] = index;
    }

    _root.物品属性列表 = this.物品属性列表;
    _root.id物品名对应表 = this.id物品名对应表;
    _root.物品最大id = 0;
    _root.物品id数组 = [];
    for (var key0 in _root.id物品名对应表)
    {
        _root.物品id数组.push(Number(key0));
        if (Number(key0) > _root.物品最大id)
        {
            _root.物品最大id = Number(key0);
        }
    }
    _root.物品id数组 = QuickSort.adaptiveSort(_root.物品id数组, function(a, b) {
        return a - b; // Numeric comparison
    });
});