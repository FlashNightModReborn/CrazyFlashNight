_root.preloaders.push(function()
{
    this.task_jsons_list = new XML();
    this.task_jsons_list.ignoreWhite = true;
    this.task_strarrs = [];
    this.tasktext_strarrs = [];

    this.task_jsons_list.onLoad = function(success)
    {
        var task_files = [];
        var text_files = [];
        _root.XmlNodeToDict(this.lastChild, null, function(name, value)
        {
            if(name == "task")
            {
                task_files.push(value);
            }
            if(name == "text")
            {
                text_files.push(value);
            }
            return null;
        });
        for(var i = 0; i < task_files.length; i++)
        {
            _root.preloaders.task_strarrs.push([]);
            _root.GetFileByPath("data/task/" + task_files[i], _root.preloaders.task_strarrs[i]);
        }
        for(var i = 0; i < text_files.length; i++)
        {
            _root.preloaders.tasktext_strarrs.push([]);
            _root.GetFileByPath("data/task/text/" + text_files[i], _root.preloaders.tasktext_strarrs[i]);
        }
    };

    this.task_jsons_list.load("data/task/list.xml");
});

_root.loaders.push(function ()
{
    this.task_srcs = [];
    this.tasks = [];
    this.task_indices_by_id = {};
    this.task_indices_by_title = {};
    this.task_chains = {};
    this.task_in_chains_by_sequence = {};
    this.tasks_of_npc = {};
    this.text_srcs = [];
    this.task_texts = {};
    this.json_parser = new LiteJSON();

    for (var i = 0; i < _root.preloaders.task_strarrs.length; i++)
    {
        this.task_srcs.push(_root.preloaders.task_strarrs[i].join(""));
    }
    for (var i = 0; i < _root.preloaders.tasktext_strarrs.length; i++)
    {
        this.text_srcs.push(_root.preloaders.tasktext_strarrs[i].join(""));
    }

    for (var i = 0; i < this.task_srcs.length; i++)
    {
        this.tasks = this.tasks.concat(this.json_parser.parse(this.task_srcs[i]).tasks);
    }
    for (var i = 0; i < this.tasks.length; i++)
    {
        this.task_indices_by_id[this.tasks[i].id] = i;
        this.task_indices_by_title[this.tasks[i].title] = i;
    }
    for (var i = 0; i < this.tasks.length; i++)
    {
        this.tasks[i].chain = this.tasks[i].chain.split("#");
        if (this.task_chains[this.tasks[i].chain[0]] == undefined)
        {
            this.task_chains[this.tasks[i].chain[0]] = {};
        }
        this.task_chains[this.tasks[i].chain[0]][this.tasks[i].chain[1]] = this.tasks[i].id;
        if (this.task_in_chains_by_sequence[this.tasks[i].chain[0]] == undefined)
        {
            this.task_in_chains_by_sequence[this.tasks[i].chain[0]] = new Array();
        }
        this.task_in_chains_by_sequence[this.tasks[i].chain[0]].push(this.tasks[i].chain[1]);
        if (this.tasks_of_npc[this.tasks[i].get_npc] == undefined)
        {
            this.tasks_of_npc[this.tasks[i].get_npc] = new Array();
        }
        this.tasks_of_npc[this.tasks[i].get_npc].push(this.tasks[i].id);
    }

    for (var i = 0; i < this.text_srcs.length; i++)
    {
        this.parsedtext = this.json_parser.parse(this.text_srcs[i]);
        for (var key in this.parsedtext)
        {
            this.task_texts[key] = this.parsedtext[key];
        }
    }

    _root.tasks = this.tasks;
    _root.task_indices_by_id = this.task_indices_by_id;
    _root.task_indices_by_title = this.task_indices_by_title;
    _root.task_chains = this.task_chains;
    _root.task_in_chains_by_sequence = this.task_in_chains_by_sequence;
    _root.tasks_of_npc = this.tasks_of_npc;
    _root.task_texts = this.task_texts;
});