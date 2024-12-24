_root.初始化物品栏 = function(){
    return {
        背包:new Object(),
        装备栏:new Object(),
        药剂栏:new Object(),
        仓库:new Object(),
        战备箱:new Object(),
        材料:new Object()
    };
}

_root.初始化成就栏 = function(){
    return {
        情报:new Object()
    }
}

_root.物品栏数据迁移 = function(){
    var 旧背包 = _root.物品栏;
    var 旧仓库 = _root.仓库栏;
    var 新物品栏 = _root.初始化物品栏();
    var 成就栏 = _root.初始化成就栏();
    //迁移背包数据
    for(var i=0; i<_root.物品栏总数; i++){
        var 旧物品 = 旧背包[i];
        if(!旧物品 || 旧物品[0] == "空") continue;
        var 新物品 = {name:旧物品[0],value:旧物品[1]};
        var use = _root.getItemData(旧物品[0]).use;
        if(旧物品[2] == 1){
            if(use == "药剂"){
                if(_root.快捷物品栏1 == 旧物品[0] && !新物品栏.药剂栏[0]) 新物品栏.药剂栏[0] = 新物品;
                else if(_root.快捷物品栏2 == 旧物品[0] && !新物品栏.药剂栏[1]) 新物品栏.药剂栏[1] = 新物品;
                else if(_root.快捷物品栏3 == 旧物品[0] && !新物品栏.药剂栏[2]) 新物品栏.药剂栏[2] = 新物品;
                else if(_root.快捷物品栏4 == 旧物品[0] && !新物品栏.药剂栏[3]) 新物品栏.药剂栏[3] = 新物品;
            }else{
                新物品栏.装备栏[use] = 新物品;
            }
        }else if(use == "材料"){
            新物品栏.材料[旧物品[0]] = 旧物品[1];
        }else if(use == "情报"){
            成就栏.情报[旧物品[0]] = 旧物品[1];
        }else{
            新物品栏.背包[i] = 新物品;
        }
    }
    //迁移仓库数据
    for(var i=0; i<1200; i++){
        var 旧物品 = 旧仓库[i];
        if(!旧物品 || 旧物品[0] == "空") continue;
        var use = _root.getItemData(旧物品[0]).use;
        if(use == "材料") 新物品栏.材料[旧物品[0]] = 旧物品[1];
        else if (use == "情报") 成就栏.情报[旧物品[0]] = 旧物品[1];
        else 新物品栏.仓库[i] = {name:旧物品[0],value:旧物品[1]};
    }
    //迁移战备箱数据
    for(var i=0; i<400; i++){
        var 旧物品 = 旧仓库[i+1200];
        if(!旧物品 || 旧物品[0] == "空") continue;
        if(use == "材料") 新物品栏.材料[旧物品[0]] = 旧物品[1];
        else if (use == "情报") 成就栏.情报[旧物品[0]] = 旧物品[1];
        else 新物品栏.战备箱[i] = {name:旧物品[0],value:旧物品[1]};
    }
    //完成
    // _root.物品栏 = 物品栏;
    // _root.仓库栏 = null;
    //测试
    ServerManager.getInstance().sendServerMessage("测试迁移数据");
    ServerManager.getInstance().sendServerMessage(org.flashNight.gesh.object.ObjectUtil.toString(新物品栏));
}


