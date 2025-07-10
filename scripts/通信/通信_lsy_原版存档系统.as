import org.flashNight.gesh.object.ObjectUtil;
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
        情报:new InformationCollection(null)
    }
}

_root.mydata数据组包 = function(){
    _root.身价 = _root.基础身价值 * _root.等级;
    var 主角储存数据 = [_root.角色名,_root.性别,_root.金钱,_root.等级,_root.经验值,_root.身高,_root.技能点数,_root.玩家称号,_root.身价,_root.虚拟币,_root.键值设定,_root.difficultyMode,_root.佣兵是否出战信息,_root.easterEgg, _root.天气系统.开启昼夜系统];
    var 装备储存数据 = [_root.脸型,_root.发型,_root.头部装备,_root.上装装备,_root.手部装备,_root.下装装备,_root.脚部装备,_root.颈部装备,_root.长枪,_root.手枪,_root.手枪2,_root.刀,_root.手雷,_root.快捷物品栏1,_root.快捷物品栏2,_root.快捷物品栏3,_root.快捷技能栏1,_root.快捷技能栏2,_root.快捷技能栏3,_root.快捷技能栏4,_root.快捷技能栏5,_root.快捷技能栏6,_root.快捷技能栏7,_root.快捷技能栏8,_root.快捷技能栏9,_root.快捷技能栏10,_root.快捷技能栏11,_root.快捷技能栏12,_root.快捷物品栏4];
    var 主角技能表储存数据 = _root.主角技能表;
    // var 物品储存数据 = _root.物品栏;
    var 物品储存数据 = {
        背包:  _root.物品栏.背包.getItems(),
        装备栏:_root.物品栏.装备栏.getItems(),
        药剂栏:_root.物品栏.药剂栏.getItems(),
        仓库:  _root.物品栏.仓库.getItems(),
        战备箱:_root.物品栏.战备箱.getItems()
    }
    var 收集品储存数据 = {
        材料:_root.收集品栏.材料.getItems(),
        情报:_root.收集品栏.情报.getItems()
    }
    var 同伴储存数据 = [_root.同伴数据,_root.同伴数];
    var 任务储存数据 = _root.主线任务进度;
    // var 仓库储存数据 = _root.仓库栏;
    var 健身储存数据 = [_root.全局健身HP加成,_root.全局健身MP加成,_root.全局健身空攻加成,_root.全局健身防御加成,_root.全局健身内力加成];

     // 获取当前时间并格式化为字符串
    var now:Date = new Date();
    var 年 = now.getFullYear();
    var 月 = now.getMonth() + 1;
    var 日 = now.getDate();
    var 时 = now.getHours();
    var 分 = now.getMinutes();
    var 秒 = now.getSeconds();

    //  补零函数
    function pad(n) { return (n < 10) ? "0" + n : n; }

    var lastSaved:String = 年 + "-" + pad(月) + "-" + pad(日) + " " + pad(时) + ":" + pad(分) + ":" + pad(秒);

    var mydata = {};
    mydata.version = "2.6";
    mydata[0] = 主角储存数据;
    mydata[1] = 装备储存数据;
    mydata[2] = null;
    mydata[3] = 任务储存数据;
    mydata[4] = 同伴储存数据;
    mydata[5] = 主角技能表储存数据;
    mydata[6] = null;
    mydata[7] = 健身储存数据;
    mydata.inventory = 物品储存数据;
    mydata.collection = 收集品储存数据;
    mydata.infrastructure = _root.基建系统.infrastructure;
    mydata.lastSaved = lastSaved;

    _root.mydata = mydata;
    
    // _root.playerData[_root.playerCurrent] = mydata;
}

_root.自动存盘 = function(){
   if(_root.存盘中 == false){
        _root.存盘动画._visible = 1;
        _root.存盘动画.gotoAndStop("储存中");
        if(_root.身价 < 1000 * _root.等级){
            _root.身价 = 1000 * _root.等级;
        }
        _root.mydata数据组包();
        _root.本地存盘战宠();
        if(_root.lastsave != _root.mydata.toString() or _root.lastsave_2 != _root.mydata_2.toString() or _root.lastsave_3 != _root.mydata_3.toString() or _root.lastsave_4 != _root.mydata_4.toString())
        {
            _root.本地存盘();
            _root.SavePCTasks();
            _root.存盘中 = true;
            _root.存盘中 = false;
            _root.存盘标志 = 1;
            // 存盘重连次数 = 0;
            _root.存盘动画.gotoAndPlay("存储成功");
            _root.发布消息(_root.获得翻译("游戏服务器储存成功！"));
        }
        else
        {
            _root.存盘标志 = 1;
            _root.存盘动画.gotoAndPlay("存储成功");
            _root.安全退出界面.gotoAndStop("成功");
        }
    }
}

/*
_root.将中文数据数字化 = function(中文数据, 对比数据){
    var _loc4_ = "";
    if(中文数据[0].toString() != 对比数据[0])
    {
        _loc4_ += "\n";
        _loc4_ += _root.组装数据包(中文数据[0],0,对比数据);
        对比数据[0] = 中文数据[0].toString();
        存储标识 += "1";
    }
    else
    {
        存储标识 += "0";
        _loc4_ += "\n";
    }
    if(中文数据[1].toString() != 对比数据[1])
    {
        _loc4_ += "\n";
        _loc4_ += _root.组装数据包(中文数据[1],1,对比数据);
        对比数据[1] = 中文数据[1].toString();
        存储标识 += "1";
    }
    else
    {
        存储标识 += "0";
        _loc4_ += "\n";
    }
    if(中文数据[2].toString() != 对比数据[2])
    {
        _loc4_ += "\n";
        _loc4_ += _root.组装数据包(中文数据[2],2,对比数据);
        对比数据[2] = 中文数据[2].toString();
        存储标识 += "1";
    }
    else
    {
        存储标识 += "0";
        _loc4_ += "\n";
    }
    if(中文数据[3].toString() != 对比数据[3])
    {
        _loc4_ += "\n";
        _loc4_ += _root.组装数据包(中文数据[3],3,对比数据);
        对比数据[3] = 中文数据[3].toString();
        存储标识 += "1";
    }
    else
    {
        存储标识 += "0";
        _loc4_ += "\n";
    }
    if(中文数据[4].toString() != 对比数据[4])
    {
        _loc4_ += "\n";
        _loc4_ += _root.组装数据包(中文数据[4],4,对比数据);
        对比数据[4] = 中文数据[4].toString();
        存储标识 += "1";
    }
    else
    {
        存储标识 += "0";
        _loc4_ += "\n";
    }
    if(中文数据[5].toString() != 对比数据[5])
    {
        _loc4_ += "\n";
        _loc4_ += _root.组装数据包(中文数据[5],5,对比数据);
        对比数据[5] = 中文数据[5].toString();
        存储标识 += "1";
    }
    else
    {
        存储标识 += "0";
        _loc4_ += "\n";
    }
    if(中文数据[6].toString() != 对比数据[6])
    {
        _loc4_ += "\n";
        _loc4_ += _root.组装数据包(中文数据[6],6,对比数据);
        对比数据[6] = 中文数据[6].toString();
        存储标识 += "1";
    }
    else
    {
        存储标识 += "0";
        _loc4_ += "\n";
    }
    存储标识 += "\n";
    return _loc4_;
}
*/

_root.本地存盘 = function() {
    var mysave = SharedObject.getLocal(_root.savePath);
   
    // Store the actual game data in the SharedObject
    mysave.data[存盘名] = _root.mydata;
    mysave.flush();  // Save the data to disk
    /*
    if(_root.调试模式 === true)
    {
        // Convert the saved object to FNTL format for testing and display purposes
        var FNTL = ObjectUtil.toFNTL(mysave.data, true);  // Serialize saved data to FNTL

        // Step 1: Create a text field for displaying the FNTL data
        if (!_root.saveDataField) {
            _root.createTextField("saveDataField", 9999, 10, 50, 380, 180);
            _root.saveDataField.border = true;
            _root.saveDataField.multiline = true;
            _root.saveDataField.wordWrap = true;
            _root.saveDataField.text = "Game data (in FNTL format) will be shown here...";
        }

        // Step 2: Create a button for manually saving data
        if (!_root.saveButton) {
            _root.createTextField("saveButton", 9998, 400, 50, 100, 25);
            _root.saveButton.border = true;
            _root.saveButton.background = true;
            _root.saveButton.backgroundColor = 0xCCCCCC;
            _root.saveButton.text = "Save Data";
            _root.saveButton.selectable = false;
            _root.saveButton.onRelease = function() {
                _root.本地存盘();  // Trigger the save function and display the FNTL
            };
        }

        // Display the FNTL data in the text field for easy copy-paste testing
        
        _root.saveDataField.text = FNTL;  // Display the FNTL string in the text field
    }
    */
};





_root.读取本地存盘 = function(){
    var 本地loadgame = SharedObject.getLocal(_root.savePath);
    _root.mydata = 本地loadgame.data[存盘名];
    //先检查存盘是否异常
    ServerManager.getInstance().sendServerMessage("检查存盘异常");
    _root.saveConvertor.convert(_root.mydata); // 检查并迁移存档数据
}

_root.读取存盘 = function()
{
    ServerManager.getInstance().sendServerMessage("读取存盘");
    if(_root.当前玩家总数 == 1)
    {
        _root.lastsave = _root.mydata.toString();
        _root.lastsave2[0] = _root.mydata[0].toString();
        _root.lastsave2[1] = _root.mydata[1].toString();
        _root.lastsave2[2] = _root.mydata[2].toString();
        _root.lastsave2[3] = _root.mydata[3].toString();
        _root.lastsave2[4] = _root.mydata[4].toString();
        _root.lastsave2[5] = _root.mydata[5].toString();
        _root.lastsave2[6] = _root.mydata[6].toString();
    }
    var 主角储存数据 = _root.mydata[0];
    var 装备储存数据 = _root.mydata[1];
    // var 物品储存数据 = _root.mydata[2];
    var 任务储存数据 = _root.mydata[3];
    var 健身储存数据 = _root.mydata[7];
    _root.同伴数据 = _root.mydata[4][0];
    _root.同伴数 = Math.floor(Number(_root.mydata[4][1]));
    _root.主角技能表 = _root.mydata[5];
    _root.更新主角被动技能();
    // _root.仓库栏 = _root.mydata[6];
    _root.角色名 = 主角储存数据[0];
    _root.性别 = 主角储存数据[1];
    _root.金钱 = Math.floor(Number(主角储存数据[2]));
    _root.等级 = Math.floor(Number(主角储存数据[3]));
    _root.经验值 = Math.floor(Number(主角储存数据[4]));
    _root.虚拟币 = Math.floor(Number(主角储存数据[9]));
    _root.全局健身HP加成 = Math.floor(Number(健身储存数据[0]));
    _root.全局健身MP加成 = Math.floor(Number(健身储存数据[1]));
    _root.全局健身空攻加成 = Math.floor(Number(健身储存数据[2]));
    _root.全局健身防御加成 = Math.floor(Number(健身储存数据[3]));
    _root.全局健身内力加成 = Math.floor(Number(健身储存数据[4]));
    if(主角储存数据[10].length > 0)
    {
        _root.键值设定 = 主角储存数据[10];
    }
    if(主角储存数据[11] >= 0)
    {
        _root.difficultyMode = 主角储存数据[11];
    }
    else
    {
        _root.difficultyMode = 0;
    }
    if(主角储存数据[12].length > 0)
    {
        _root.佣兵是否出战信息 = 主角储存数据[12];
        i = 0;
        while(i < _root.佣兵是否出战信息.length)
        {
            if(_root.佣兵是否出战信息[i] == -1)
            {
                _root.佣兵是否出战信息[i] = 1;
            }
            i++;
        }
    }
    if(主角储存数据[14] || 主角储存数据[14] === false)
    {
        _root.天气系统.开启昼夜系统 = 主角储存数据[14];
    }
    
    var tmp经验值 = 根据等级得升级所需经验(_root.等级);
    if(tmp经验值 < _root.经验值)
    {
        _root.经验值 = tmp经验值;
    }
    tmp经验值 = 根据等级得升级所需经验(_root.等级 - 1);
    if(tmp经验值 > _root.经验值)
    {
        _root.经验值 = tmp经验值;
    }
    _root.身高 = Math.floor(Number(主角储存数据[5]));
    _root.技能点数 = Math.floor(Number(主角储存数据[6]));
    _root.玩家称号 = 主角储存数据[7];
    _root.身价 = Math.floor(Number(主角储存数据[8]));
    _root.长枪强化等级 = undefined;
    _root.手枪强化等级 = undefined;
    _root.手枪2强化等级 = undefined;
    _root.刀强化等级 = undefined;
    _root.脸型 = 装备储存数据[0];
    _root.发型 = 装备储存数据[1];
    // _root.头部装备 = 装备储存数据[2];
    // _root.上装装备 = 装备储存数据[3];
    // _root.手部装备 = 装备储存数据[4];
    // _root.下装装备 = 装备储存数据[5];
    // _root.脚部装备 = 装备储存数据[6];
    // _root.颈部装备 = 装备储存数据[7];
    // _root.长枪 = 装备储存数据[8];
    // _root.手枪 = 装备储存数据[9];
    // _root.手枪2 = 装备储存数据[10];
    // _root.刀 = 装备储存数据[11];
    // _root.手雷 = 装备储存数据[12];
    // _root.快捷物品栏1 = 装备储存数据[13];
    // _root.快捷物品栏2 = 装备储存数据[14];
    // _root.快捷物品栏3 = 装备储存数据[15];
    _root.快捷技能栏1 = 装备储存数据[16];
    _root.快捷技能栏2 = 装备储存数据[17];
    _root.快捷技能栏3 = 装备储存数据[18];
    _root.快捷技能栏4 = 装备储存数据[19];
    _root.快捷技能栏5 = 装备储存数据[20];
    _root.快捷技能栏6 = 装备储存数据[21];
    _root.快捷技能栏7 = 装备储存数据[22];
    _root.快捷技能栏8 = 装备储存数据[23];
    _root.快捷技能栏9 = 装备储存数据[24];
    _root.快捷技能栏10 = 装备储存数据[25];
    _root.快捷技能栏11 = 装备储存数据[26];
    _root.快捷技能栏12 = 装备储存数据[27];
    // _root.快捷物品栏4 = 装备储存数据[28];
    // _root.物品栏 = 物品储存数据;

    _root.物品栏 = {
        背包:new ArrayInventory(_root.mydata.inventory.背包,50),
        装备栏:new EquipmentInventory(_root.mydata.inventory.装备栏),
        药剂栏:new DrugInventory(_root.mydata.inventory.药剂栏,4),
        仓库:new ArrayInventory(_root.mydata.inventory.仓库,1200),
        战备箱:new ArrayInventory(_root.mydata.inventory.战备箱,400)
    };
    _root.收集品栏 = {
        材料:new DictCollection(_root.mydata.collection.材料),
        情报:new InformationCollection(_root.mydata.collection.情报)
    };
    _root.基建系统.infrastructure = mydata.infrastructure;

    _root.主线任务进度 = Math.floor(Number(任务储存数据));
    _root.LoadPCTasks();
    if(_root.角色名 == undefined){
        _root.发布消息(_root.获得翻译("游戏本地无存盘！"));
        return false;
    }
    _root.发布消息(_root.获得翻译("游戏本地读取成功！"));
    载入新佣兵库数据(0,0,0,0,0);
    return true;
}

_root.是否存过盘 = function(){
    var 本地loadgame = SharedObject.getLocal(_root.savePath);
    var tmp主角储存数据 = 本地loadgame.data[存盘名][0];
    var tmp角色名 = tmp主角储存数据[0];
    if(tmp角色名 == undefined) return false;
    return true;
}

_root.新建角色 = function(){
    _root.mydata数据组包();
    _root.金钱 = 0;
    _root.虚拟币 = 0;
    _root.宠物信息 = [[],[],[],[],[]];
    _root.宠物领养限制 = 5;
    //
    _root.基建系统.infrastructure = {};
    //
    _root.soundEffectManager.stopBGM();
    // _root.淡出动画.淡出跳转帧("教学关卡");
    _root.载入关卡数据("无限过图", "data/stages/特殊/教学关卡.xml");
    _root.淡出动画.淡出跳转帧("wuxianguotu_1");
    return true;
}

_root.删除存盘 = function(){
    var mysave = SharedObject.getLocal(_root.savePath);
    mysave.clear();
}

_root.存盘名 = "test";
_root.lastsave2 = [];
_root.lastsave2_1 = [];
_root.lastsave2_2 = [];
_root.lastsave2_3 = [];
_root.lastsave = "";
_root.lastsave_1 = "";
_root.lastsave_2 = "";
_root.lastsave_3 = "";
_root.存盘中 = false;
// _root.存盘重连次数 = 0;
// _root.存盘重连次数限制 = 10;
