_root.物品栏数据迁移 = function(data){
    var 旧背包 = data[2];
    var 旧仓库 = data[6];
    var 新物品栏 = _root.初始化物品栏();
    var 收集品栏 = _root.初始化收集品栏();
    //迁移背包数据
    for(var i=0; i < _root.物品栏总数; i++){
        var 旧物品 = 旧背包[i];
        if(!旧物品 || 旧物品[0] == "空") continue;
        var 新物品 = {name:旧物品[0],value:旧物品[1]};
        var itemData = _root.getItemData(旧物品[0]);
        var type = itemData.type;
        var use = itemData.use;
        if(type == "武器" || type == "防具") 新物品.value = {level:旧物品[1]};
        if(旧物品[2] == 1 && use != "药剂"){
            // if(use == "药剂"){
            //     if     (_root.快捷物品栏1 == 旧物品[0] && !新物品栏.药剂栏[0]) 新物品栏.药剂栏.add(0,新物品);
            //     else if(_root.快捷物品栏2 == 旧物品[0] && !新物品栏.药剂栏[1]) 新物品栏.药剂栏.add(1,新物品);
            //     else if(_root.快捷物品栏3 == 旧物品[0] && !新物品栏.药剂栏[2]) 新物品栏.药剂栏.add(2,新物品);
            //     else if(_root.快捷物品栏4 == 旧物品[0] && !新物品栏.药剂栏[3]) 新物品栏.药剂栏.add(3,新物品);
            // }else{
            //     新物品栏.装备栏.add(use,新物品);
            // }
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
        if(type == "武器" || type == "防具") 新物品.value = {level:旧物品[1]};
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
        if(type == "武器" || type == "防具") 新物品.value = {level:旧物品[1]};
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
    ServerManager.getInstance().sendServerMessage("迁移背包仓库数据");
    var str = "";
    for(var key in 新物品栏){
        str += org.flashNight.gesh.object.ObjectUtil.toString(新物品栏[key].getItems());
        str += "\n";
    }
    str += org.flashNight.gesh.object.ObjectUtil.toString(收集品栏.材料.getItems());
    str += "\n";
    str += org.flashNight.gesh.object.ObjectUtil.toString(收集品栏.情报.getItems());
    ServerManager.getInstance().sendServerMessage(str);
}

_root.检查并迁移存档数据 = function(data){
    if(data[2] && !data.inventory){
        _root.物品栏数据迁移(data);
    }
}