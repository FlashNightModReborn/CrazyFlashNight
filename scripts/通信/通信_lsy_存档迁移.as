import org.flashNight.arki.item.itemCollection.*;

_root.初始化物品栏 = function(){
    return {
        背包:new ArrayInventory(null,50),
        装备栏:new EquipmentInventory(null),
        药剂栏:new DrugInventory(null,4),
        仓库:new ArrayInventory(null,1200),
        战备箱:new ArrayInventory(null,400)
    };
}

_root.初始化收集品栏 = function(){
    return {
        材料:new DictCollection(null),
        情报:new DictCollection(null)
    }
}

_root.物品栏数据迁移 = function(){
    var 旧背包 = _root.物品栏;
    var 旧仓库 = _root.仓库栏;
    var 新物品栏 = _root.初始化物品栏();
    var 收集品栏 = _root.初始化收集品栏();
    //迁移背包数据
    for(var i=0; i < _root.物品栏总数; i++){
        var 旧物品 = 旧背包[i];
        if(!旧物品 || 旧物品[0] == "空") continue;
        var 新物品 = {name:旧物品[0],value:旧物品[1]};
        var use = _root.getItemData(旧物品[0]).use;
        if(旧物品[2] == 1){
            if(use == "药剂"){
                if     (_root.快捷物品栏1 == 旧物品[0] && !新物品栏.药剂栏[0]) 新物品栏.药剂栏.add(0,新物品);
                else if(_root.快捷物品栏2 == 旧物品[0] && !新物品栏.药剂栏[1]) 新物品栏.药剂栏.add(1,新物品);
                else if(_root.快捷物品栏3 == 旧物品[0] && !新物品栏.药剂栏[2]) 新物品栏.药剂栏.add(2,新物品);
                else if(_root.快捷物品栏4 == 旧物品[0] && !新物品栏.药剂栏[3]) 新物品栏.药剂栏.add(3,新物品);
            }else{
                新物品栏.装备栏.add(use,新物品);
            }
        }else if(use == "材料"){
            收集品栏.材料.add(旧物品[0],旧物品[1]);
        }else if(use == "情报"){
            收集品栏.情报.add(旧物品[0],旧物品[1]);
        }else{
            新物品栏.背包[i] = 新物品;
        }
    }
    //迁移仓库数据
    for(var i=0; i<1200; i++){
        var 旧物品 = 旧仓库[i];
        if(!旧物品 || 旧物品[0] == "空") continue;
        var use = _root.getItemData(旧物品[0]).use;
        if(use == "材料") 收集品栏.材料.add(旧物品[0],旧物品[1]);
        else if (use == "情报") 收集品栏.情报.add(旧物品[0],旧物品[1]);
        else 新物品栏.仓库.add(i, {name:旧物品[0],value:旧物品[1]});
    }
    //迁移战备箱数据
    for(var i=0; i<400; i++){
        var 旧物品 = 旧仓库[i+1200];
        if(!旧物品 || 旧物品[0] == "空") continue;
        if(use == "材料") 收集品栏.材料.add(旧物品[0],旧物品[1]);
        else if (use == "情报") 收集品栏.情报.add(旧物品[0],旧物品[1]);
        else 新物品栏.战备箱.add(i, {name:旧物品[0],value:旧物品[1]});
    }
    完成
    _root.物品栏 = 新物品栏;
    _root.收集品栏 = 收集品栏;
    _root.仓库栏 = null;
    //测试
    // ServerManager.getInstance().sendServerMessage("测试迁移数据");
    // ServerManager.getInstance().sendServerMessage(org.flashNight.gesh.object.ObjectUtil.toString(新物品栏));
}


