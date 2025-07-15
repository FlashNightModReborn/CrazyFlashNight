_root.存档系统.convertInventory = function(data){
    var 旧背包 = data[2];
    var 旧仓库 = data[6];
    var 新物品栏 = _root.存档系统.初始化物品栏();
    var 收集品栏 = _root.存档系统.初始化收集品栏();
    //迁移背包数据
    for(var i=0; i < _root.物品栏总数; i++){
        var 旧物品 = 旧背包[i];
        if(!旧物品 || 旧物品[0] == "空") continue;
        var 新物品 = {name:旧物品[0],value:旧物品[1]};
        var itemData = _root.getItemData(旧物品[0]);
        var type = itemData.type;
        var use = itemData.use;
        if(itemData == null){
            if(新物品.name.indexOf("阶") == 1) 新物品.value = {level:旧物品[1]};
            else if(新物品.name.indexOf("制作图纸") == -1 && (新物品.name.indexOf("墨冰") > -1 || 新物品.name.indexOf("狱火") > -1)) 新物品.value = {level:旧物品[1]};
            else continue;
        }else if(type == "武器" || type == "防具") 新物品.value = {level:旧物品[1]};
        if(旧物品[2] == 1 && use != "药剂"){
            新物品栏.装备栏.add(use,新物品);
        }else if(use == "材料"){
            收集品栏.材料.add(旧物品[0],旧物品[1]);
        }else if(use == "情报"){
            收集品栏.情报.add(旧物品[0],旧物品[1]);
        }else{
            新物品栏.背包.add(i,新物品);
        }
    }
    //迁移仓库数据
    for(var i=0; i<1200; i++){
        var 旧物品 = 旧仓库[i];
        if(!旧物品 || 旧物品[0] == "空") continue;
        var 新物品 = {name:旧物品[0],value:旧物品[1]};
        var itemData = _root.getItemData(旧物品[0]);
        var type = itemData.type;
        var use = itemData.use;
        if(itemData == null){
            if(新物品.name.indexOf("阶") == 1) 新物品.value = {level:旧物品[1]};
            else if(新物品.name.indexOf("制作图纸") == -1 && (新物品.name.indexOf("墨冰") > -1 || 新物品.name.indexOf("狱火") > -1)) 新物品.value = {level:旧物品[1]};
            else continue;
        }else if(type == "武器" || type == "防具") 新物品.value = {level:旧物品[1]};
        if(use == "材料") 收集品栏.材料.add(旧物品[0],旧物品[1]);
        else if (use == "情报") 收集品栏.情报.add(旧物品[0],旧物品[1]);
        else 新物品栏.仓库.add(i, 新物品);
    }
    //迁移战备箱数据
    for(var i=0; i<400; i++){
        var 旧物品 = 旧仓库[i+1200];
        if(!旧物品 || 旧物品[0] == "空") continue;
        var 新物品 = {name:旧物品[0],value:旧物品[1]};
        var itemData = _root.getItemData(旧物品[0]);
        var type = itemData.type;
        var use = itemData.use;
        if(itemData == null){
            if(新物品.name.indexOf("阶") == 1) 新物品.value = {level:旧物品[1]};
            else if(新物品.name.indexOf("制作图纸") == -1 && (新物品.name.indexOf("墨冰") > -1 || 新物品.name.indexOf("狱火") > -1)) 新物品.value = {level:旧物品[1]};
            else continue;
        }else if(type == "武器" || type == "防具") 新物品.value = {level:旧物品[1]};
        if(use == "材料") 收集品栏.材料.add(旧物品[0],旧物品[1]);
        else if (use == "情报") 收集品栏.情报.add(旧物品[0],旧物品[1]);
        else 新物品栏.战备箱.add(i, 新物品);
    }
    // 完成
    data.inventory = {
        背包:  新物品栏.背包.getItems(),
        装备栏:新物品栏.装备栏.getItems(),
        药剂栏:新物品栏.药剂栏.getItems(),
        仓库:  新物品栏.仓库.getItems(),
        战备箱:新物品栏.战备箱.getItems()
    };
    data.collection = {
        材料:收集品栏.材料.getItems(),
        情报:收集品栏.情报.getItems()
    };
    data[2] = null;
    data[6] = null;
    _root.仓库栏 = null;
    //测试
    // ServerManager.getInstance().sendServerMessage("迁移背包仓库数据");
    // var str = "";
    // for(var key in 新物品栏){
    //     str += org.flashNight.gesh.object.ObjectUtil.toString(新物品栏[key].getItems());
    //     str += "\n";
    // }
    // str += org.flashNight.gesh.object.ObjectUtil.toString(收集品栏.材料.getItems());
    // str += "\n";
    // str += org.flashNight.gesh.object.ObjectUtil.toString(收集品栏.情报.getItems());
    // ServerManager.getInstance().sendServerMessage(str);
}

_root.存档系统.convertInfrastructure = function(data){
    data.infrastructure = new Object();
}

_root.存档系统.convert = function(data){
    //检查并迁移物品栏数据
    ServerManager.getInstance().sendServerMessage("开始检查存档版本");
    if(isNaN(data.version)){
        ServerManager.getInstance().sendServerMessage("将存档数据从未知版本更新至2.6");
        if(data[2] && !data.inventory){
            this.convertInventory(data);
        }
        if(data.infrastructure == null){
            this.convertInfrastructure(data);
        }
        data.version = "2.6";
    }
    if(data.version == "2.6"){
        ServerManager.getInstance().sendServerMessage("将存档数据从2.6更新至2.7");
        this.convert_2_6(data);
    }
}


// 2.6 迁移内容

_root.存档系统.convert_tiers = function(rawItems){
    var tierstrs = ["二阶","三阶","四阶"];
    for(var key in rawItems){
        var item = rawItems[key];
        var itemName = item.name
        if(itemName.indexOf("墨冰") > -1){
            this.tierfunc.墨冰(item);
            continue;
        }else if(itemName.indexOf("狱火") > -1){
            this.tierfunc.狱火(item);
            continue;
        }
        for(var i=0; i<3; i++){
            if(itemName.indexOf(tierstrs[i]) == 0){
                this.tierfunc[tierstrs[i]](item);
                break;
            }
        }
    }
}
_root.存档系统.tierfunc = new Object(); 
_root.存档系统.tierfunc.二阶 = function(item){
    if(this.specailTierDict[item.name] != null) item.name = this.specailTierDict[item.name];
    else item.name = item.name.split("二阶").join("");
    item.value.tier = "二阶";
}
_root.存档系统.tierfunc.三阶 = function(item){
    if(this.specailTierDict[item.name] != null) item.name = this.specailTierDict[item.name];
    else item.name = item.name.split("三阶").join("");
    item.value.tier = "三阶";
}
_root.存档系统.tierfunc.四阶 = function(item){
    if(this.specailTierDict[item.name] != null) item.name = this.specailTierDict[item.name];
    else item.name = item.name.split("四阶").join("");
    item.value.tier = "四阶";
}
_root.存档系统.tierfunc.墨冰 = function(item){
    item.name = this.specailTierDict[item.name];
    item.value.tier = "墨冰";
}
_root.存档系统.tierfunc.狱火 = function(item){
    item.name = this.specailTierDict[item.name];
    item.value.tier = "狱火";
}

_root.存档系统.tierfunc.specailTierDict = {
    二阶外置能量战纹: "盗贼纹身装",
    三阶外置能量战纹: "盗贼纹身装",
    四阶外置能量战纹: "盗贼纹身装",
    二阶道钉手套: "褐色道钉手套",
    三阶道钉手套: "褐色道钉手套",
    四阶道钉手套: "褐色道钉手套",

    Glock18墨冰: "Glock 18",
    MP40墨冰: "MP40",
    Beretta90TWO墨冰: "Beretta90TWO",
    TTI2011墨冰: "TTI 2011 Combat Master",
    MK23墨冰: "MK23手枪",
    韦森686墨冰: "韦森686",
    AK74墨冰: "AK74",
    M4A1墨冰: "M4A1",
    AUG墨冰: "AUG",
    HK416墨冰: "HK416",
    // 53式步骑枪墨冰: "53式步骑枪",
    Sniper墨冰: "Sniper",
    SVD墨冰: "SVD",
    M14墨冰: "m14",
    墨冰88式狙击枪: "中国88式狙击步枪",
    XM1014墨冰: "XM1014",
    墨冰白火铳: "白火铳",
    墨冰匕首: "匕首",
    墨冰大剑: "大剑",

    Glock18狱火: "Glock 18",
    MP40狱火: "MP40",
    Beretta90TWO狱火: "Beretta90TWO",
    TTI2011狱火: "TTI 2011 Combat Master",
    MK23狱火: "MK23手枪",
    韦森686狱火: "韦森686",
    AK74狱火: "AK74",
    M4A1狱火: "M4A1",
    AUG狱火: "AUG",
    HK416狱火: "HK416",
    // 53式步骑枪狱火: "53式步骑枪",
    Sniper狱火: "Sniper",
    SVD狱火: "SVD",
    M14狱火: "m14",
    狱火88式狙击枪: "中国88式狙击步枪",
    XM1014狱火: "XM1014",
    狱火白火铳: "白火铳",
    狱火匕首: "匕首",
    狱火大剑: "大剑"
}
_root.存档系统.tierfunc.specailTierDict["53式步骑枪墨冰"] = "53式步骑枪";
_root.存档系统.tierfunc.specailTierDict["53式步骑枪狱火"] = "53式步骑枪";


_root.存档系统.materialToInfoDict = {
    精致战术猪鼻式防毒面具制作图纸: "A兵团制式套装改造图纸",
    A兵团精致战术背心制作图纸: "A兵团制式套装改造图纸",
    A兵团精致战术手套制作图纸: "A兵团制式套装改造图纸",
    A兵团精致战术裤制作图纸: "A兵团制式套装改造图纸",
    A兵团精致战术皮鞋制作图纸: "A兵团制式套装改造图纸",
    A兵团精致项链制作图纸: "A兵团制式套装改造图纸",
    镜之虎彻制作图纸: "镜之虎彻制作图纸",
    加强版MP7制作图纸: "加强版MP7制作图纸",
    双管白火铳制作图纸: "双管白火铳制作图纸"
}

_root.存档系统.convert_material_info = function(data){
    var rawMaterial = data.collection.材料;
    var 墨冰计数 = 0;
    var 狱火计数 = 0;
    var 情报 = new InformationCollection(data.collection.情报);
    for(var key in rawMaterial){
        if(key.indexOf("图纸") > -1){
            if(key.indexOf("墨冰") > -1){
                墨冰计数 += rawMaterial[key];
                delete rawMaterial[key];
                continue;
            }else if(key.indexOf("狱火") > -1){
                狱火计数 += rawMaterial[key];
                delete rawMaterial[key];
                continue;
            }
        }
        var infokey = this.materialToInfoDict[key];
        if(infokey != null){
            情报.add(infokey, 1);
            delete rawMaterial[key];
        }
    }
    if(墨冰计数 > 0) rawMaterial["墨冰战术涂料"] = 墨冰计数;
    if(狱火计数 > 0) rawMaterial["狱火战术涂料"] = 狱火计数;
    data.collection.情报 = 情报.getItems();
}


_root.存档系统.convert_2_6 = function(data){
    this.convert_tiers(data.inventory.背包);
    this.convert_tiers(data.inventory.装备栏);
    this.convert_tiers(data.inventory.仓库);
    this.convert_tiers(data.inventory.战备箱);
    this.convert_material_info(data);
}


