_root.preloaders.push(function()
{
    this.units_jsons_list = new XML();
    this.units_jsons_list.ignoreWhite = true;
    this.units_strarrs = [];
    this.units_jsons_list.onLoad = function(success)
    {
        var files = [];
        _root.XmlNodeToDict(this.lastChild,null,function(name, value)
        {
            if(name == "units")
            {
                files.push(value);
            }
            return null;
        });
        for (var i = 0; i < files.length; i++)
        {
            _root.preloaders.units_strarrs.push([]);
            _root.GetFileByPath("data/units/" + files[i], _root.preloaders.units_strarrs[i]);
        }
    };

    this.units_jsons_list.load("data/units/list.xml");
});

_root.loaders.push(function ()
{
    this.units_srcs = [];
    this.units = [];
    this.unit_indices_by_id = {};
    this.unit_indices_by_name = {};
    this.兵种库 = {};
    this.json_parser = new LiteJSON();

    for (var i = 0; i < _root.preloaders.units_strarrs.length; i++)
    {
        this.units_srcs.push(_root.preloaders.units_strarrs[i].join(""));
    }

    for (var i = 0; i < this.units_srcs.length; i++)
    {
        this.units = this.units.concat(this.json_parser.parse(this.units_srcs[i]));
    }
    for (var i in this.units)
    {
        this.unit_indices_by_id[this.units[i].id] = i;
        this.unit_indices_by_name[this.units[i].name] = i;
        var tmpDict = {};
        tmpDict.兵种名 = this.units[i].spritename;
        tmpDict.等级 = this.units[i].level;
        tmpDict.名字 = this.units[i].name;
        tmpDict.是否为敌人 = this.units[i].is_hostile;
        if (this.units[i].NPC != undefined)
        {
            tmpDict.NPC = this.units[i].NPC;
        }
        tmpDict.身高 = this.units[i].height;
        tmpDict.等级 = this.units[i].level;
        tmpDict.长枪 = !this.units[i].data.primary ? "" : this.units[i].data.primary;
        tmpDict.手枪 = !this.units[i].data.secondary ? "" : this.units[i].data.secondary;
        tmpDict.手枪2 = !this.units[i].data.secondary2 ? "" : this.units[i].data.secondary2;
        tmpDict.刀 = !this.units[i].data.melee ? "" : this.units[i].data.melee;
        tmpDict.手雷 = !this.units[i].data.grenade ? "" : this.units[i].data.grenade;
        if(this.units[i].pet_attr ){
            tmpDict.宠物属性 = this.units[i].pet_attr ;
        }
        if (this.units[i].NPC != undefined)
        {
            tmpDict.NPC = this.units[i].NPC;
        }
        if (this.units[i].data.face != undefined)
        {
            tmpDict.脸型 = this.units[i].data.face == null ? "" : this.units[i].data.face;
        }
        if (this.units[i].data.hairstyle != undefined)
        {
            tmpDict.发型 = this.units[i].data.hairstyle == null ? "" : this.units[i].data.hairstyle;
        }
        if (this.units[i].data.head != undefined)
        {
            tmpDict.头部装备 = this.units[i].data.head == null ? "" : this.units[i].data.head;
        }
        if (this.units[i].data.body != undefined)
        {
            tmpDict.上装装备 = this.units[i].data.body == null ? "" : this.units[i].data.body;
        }
        if (this.units[i].data.leg != undefined)
        {
            tmpDict.下装装备 = this.units[i].data.leg == null ? "" : this.units[i].data.leg;
        }
        if (this.units[i].data.hand != undefined)
        {
            tmpDict.手部装备 = this.units[i].data.hand == null ? "" : this.units[i].data.hand;
        }
        if (this.units[i].data.foot != undefined)
        {
            tmpDict.脚部装备 = this.units[i].data.foot == null ? "" : this.units[i].data.foot;
        }
        if (this.units[i].data.neck != undefined)
        {
            tmpDict.颈部装备 = this.units[i].data.neck == null ? "" : this.units[i].data.neck;
        }
        if (this.units[i].data.gender != undefined)
        {
            tmpDict.性别 = this.units[i].data.gender == null ? "" : this.units[i].data.gender;
        }
        this.兵种库["兵种" + String(this.units[i].id)] = _root.duplicateOf(tmpDict);
    }

    _root.units = this.units;
    _root.unit_indices_by_id = this.unit_indices_by_id;
    _root.unit_indices_by_name = this.unit_indices_by_name;
    _root.兵种库 = this.兵种库;
});