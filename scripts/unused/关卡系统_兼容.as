_root.preloaders.push(function()
{
    this.stages_jsons_list = new XML();
    this.stages_jsons_list.ignoreWhite = true;
    this.stages_strarrs = [];
    this.stages_jsons_list.onLoad = function(success)
    {
        var files = [];
        _root.XmlNodeToDict(this.lastChild, null, function(name, value)
        {
            if(name == "stages")
            {
                files.push(value);
            }
            return null;
        });
        for (var i = 0; i < files.length; i++)
        {
            _root.preloaders.stages_strarrs.push([]);
            _root.GetFileByPath("data/stages/" + files[i], _root.preloaders.stages_strarrs[i]);
        }
    };

    this.stages_jsons_list.load("data/stages/list.xml");
});

_root.loaders.push(function ()
{
    this.stages_srcs = [];
    this.stages_unlock = {};
    this.json_parser = new JSON();

    for (var i = 0; i < _root.preloaders.stages_strarrs.length; i++)
    {
        this.stages_srcs.push(_root.preloaders.stages_strarrs[i].join(""));
    }
    for (var i = 0; i < this.stages_srcs.length; i++)
    {
        this.parsedstage = this.json_parser.parse(this.stages_srcs[i]);
        for (var key in this.parsedstage)
        {
            this.stages_unlock[key] = this.parsedstage[key];
        }
    }
    
    _root.stages_unlock = this.stages_unlock;
});