_root.preloaders.push(function()
{
    this.merc_jsons_list = new XML();
    this.merc_jsons_list.ignoreWhite = true;
    this.merc_strarrs = [];
    this.merc_easy_strarrs = [];
    this.merc_jsons_list.onLoad = function(success)
    {
        var merc_files = [];
        var merc_easy_files = [];
        _root.XmlNodeToDict(this.lastChild, null, function(name, value)
        {
            if(name == "merc")
            {
                merc_files.push(value);
            }
            if(name == "merc_easy")
            {
                merc_easy_files.push(value);
            }
            return null;
        });
        for (var i = 0; i < merc_files.length; i++)
        {
            _root.preloaders.merc_strarrs.push([]);
            _root.GetFileByPath("data/merc/" + merc_files[i], _root.preloaders.merc_strarrs[i]);
        }
        for (var i = 0; i < merc_easy_files.length; i++)
        {
            _root.preloaders.merc_easy_strarrs.push([]);
            _root.GetFileByPath("data/merc/" + merc_easy_files[i], _root.preloaders.merc_easy_strarrs[i]);
        }
    };

    this.merc_jsons_list.load("data/merc/list.xml");
});

_root.loaders.push(function ()
{
    this.merc_srcs = [];
    this.mercs_list = [];
    this.merc_indices_by_id = {};
    this.merc_easy_srcs = [];
    this.mercs_easy_list = [];
    this.merc_easy_indices_by_id = {};
    this.json_parser = new LiteJSON();

    for (var i = 0; i < _root.preloaders.merc_strarrs.length; i++)
    {
        this.merc_srcs.push(_root.preloaders.merc_strarrs[i].join(""));
    }
    for (var i = 0; i < _root.preloaders.merc_easy_strarrs.length; i++)
    {
        this.merc_easy_srcs.push(_root.preloaders.merc_easy_strarrs[i].join(""));
    }

    for (var i = 0; i < this.merc_srcs.length; i++)
    {
        this.mercs_list = this.mercs_list.concat(this.json_parser.parse(this.merc_srcs[i]));
    }
    for (var i = 0; i < this.mercs_list.length; i++)
    {
        this.merc_indices_by_id[this.mercs_list[i].id] = i;
    }
    for (var i = 0; i < this.merc_easy_srcs.length; i++)
    {
        this.mercs_easy_list = this.mercs_easy_list.concat(this.json_parser.parse(this.merc_easy_srcs[i]));
    }
    for (var i = 0; i < this.mercs_easy_list.length; i++)
    {
        this.merc_easy_indices_by_id[this.mercs_easy_list[i].id] = i;
    }

    _root.mercs_list = this.mercs_list;
    _root.merc_indices_by_id = this.merc_indices_by_id;
    _root.mercs_easy_list = this.mercs_easy_list;
    _root.merc_easy_indices_by_id = this.merc_easy_indices_by_id;
});