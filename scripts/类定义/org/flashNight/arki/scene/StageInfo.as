import org.flashNight.arki.scene.StageEvent;

import org.flashNight.gesh.object.ObjectUtil;

/**
StageInfo.as
——————————————————————————————————————————
*/
class org.flashNight.arki.scene.StageInfo {

    public var basicInfo:Object; // 基本信息
    public var instanceInfo:Array; // 实例信息
    public var spawnPointInfo:Array; // 出生点信息
    public var waveInfo:Array; // 波次信息
    public var eventInfo:Array; // 关卡事件
    public var triggerInfo:Array // 压力板信息

    // ————————————————————————
    // 构造函数
    // ————————————————————————
    public function StageInfo(data:Object) {
        basicInfo = parseBasicInfo(data);
        instanceInfo = parseInstanceInfo(data);
        spawnPointInfo = parseSpawnPointInfo(data);
        waveInfo = parseWaveInfo(data);
        eventInfo = parseEventInfo(data);
        triggerInfo = parseTriggerInfo(data);
    }

    public static function parseBasicInfo(data):Object{
        var info = data.BasicInformation;
		if(info.Environment.Default === true){
			info.Environment = _root.天气系统.关卡环境设置.Default;
		}
        return info;
    }

    public static function parseInstanceInfo(data):Array{
		if(data.Instances == null) return null;
        return ObjectUtil.toArray(data.Instances.Instance);
    }

    public static function parseSpawnPointInfo(data):Array{
		if(data.SpawnPoint == null) return null;
		
		var info = ObjectUtil.toArray(data.SpawnPoint.Point);
		for (var i:Number = 0; i < info.length; i++){
			info[i].QuantityMax = info[i].QuantityMax > 0 ? Number(info[i].QuantityMax) : 0;
			info[i].NoCount = info[i].NoCount ? true : false;
		}
        return info;
    }

    public static function parseDialogues(data):Array{
		var 对话条数 = 0;
		var info = [];
		var 对话列表 = ObjectUtil.toArray(data.Dialogue.SubDialogue);
		var 单次对话 = parseSingleDialogue(对话列表);
		if(单次对话.length > 0) 对话条数++;
		info.push(单次对话);

		var subWaveInfo = ObjectUtil.toArray(data.Wave.SubWave)
		for(var i:Number = 0; i < subWaveInfo.length; i++){
			对话列表 = ObjectUtil.toArray(subWaveInfo[i].Dialogue.SubDialogue);
			单次对话 = parseSingleDialogue(对话列表);
			if(单次对话.length > 0) 对话条数++;
			info.push(单次对话);
		}

		return 对话条数 > 0 ? info : null;
    }

    public static function parseSingleDialogue(dialogueData):Array{
        var len = dialogueData.length;
        if(len <= 0) return null;
        var dialogue = new Array(len);
        for(var i:Number = 0; i < len; i++){
            var 对话 = dialogueData[i];
            if (对话 == null) return null;
            var 对话对象 = parseEnemyAttribute(对话);
            dialogue[i] = {
                name:对话.Name, 
                title:对话.Title, 
                char:对话.Char, 
                text:对话.Text, 
                target:对话对象, 
                imageurl:对话.ImageUrl
            };
        }
        return dialogue;
    }





    public static function parseWaveInfo(data):Array{
        var subWaveInfo = ObjectUtil.toArray(data.Wave.SubWave);
        if(subWaveInfo == null) return null;
        var resultInfo = [];
        for (var i:Number = 0; i < subWaveInfo.length; i++){
            var subwave = subWaveInfo[i];
            var w_info = subwave.WaveInformation;
            w_info.Duration = isNaN(w_info.Duration) ? 0 : w_info.Duration;
            w_info.MapNoCount = w_info.MapNoCount ? true : false;
            var enemyGroupInfo = parseEnemyGroup(ObjectUtil.toArray(subwave.EnemyGroup.Enemy));

            resultInfo.push([w_info].concat(enemyGroupInfo));
        }
        return resultInfo;
    }

    public static function parseEnemyGroup(enemyGroupData):Array{
        var info = [];
        for (var i:Number = 0; i < enemyGroupData.length; i++){
            var enemyInfo = enemyGroupData[i];
            enemyInfo.Attribute = parseEnemyAttribute(enemyInfo);
            enemyInfo.Interval = isNaN(enemyInfo.Interval) ? 100 : enemyInfo.Interval;
            enemyInfo.Delay = isNaN(enemyInfo.Delay) ? 0 : enemyInfo.Delay;
            enemyInfo.Quantity = isNaN(enemyInfo.Quantity) ? 1 : Number(enemyInfo.Quantity);
            enemyInfo.Level = isNaN(enemyInfo.Level) ? 1 : Number(enemyInfo.Level);
            enemyInfo.SpawnIndex = (enemyInfo.SpawnIndex || enemyInfo.SpawnIndex == 0) ? enemyInfo.SpawnIndex : -1;
            info.push(enemyInfo);
        }
        return info;
    }

    public static function parseEnemyAttribute(enemyInfo):Object{
        // 如果Type属性存在，则直接返回已有敌人配置
        if (_root.兵种库[enemyInfo.Type] != null){
            var attr = ObjectUtil.clone(_root.兵种库[enemyInfo.Type]);
            if(enemyInfo.IsHostile != null) attr.是否为敌人 = enemyInfo.IsHostile;
            return attr;
        }
        // 否则，组装敌人属性
        var attr:Object = {
            兵种名: enemyInfo.spritename,
            名字: enemyInfo.Name,
            等级: enemyInfo.Level,
            是否为敌人: enemyInfo.IsHostile,
            身高: enemyInfo.Height,
            NPC: enemyInfo.NPC,
            长枪: enemyInfo.PrimaryWeapon,
            手枪: enemyInfo.SecondaryWeapon,
            手枪2: enemyInfo.SecondaryWeapon2,
            刀: enemyInfo.MeleeWeapon,
            手雷: enemyInfo.Grenade,
            脸型: enemyInfo.FaceType,
            发型: enemyInfo.HairStyle,
            头部装备: enemyInfo.HeadEquipment,
            上装装备: enemyInfo.BodyArmor,
            下装装备: enemyInfo.LegArmor,
            手部装备: enemyInfo.HandGear,
            脚部装备: enemyInfo.FootGear,
            颈部装备: enemyInfo.NeckGear,
            性别: enemyInfo.Gender
        };
        for (var key:String in attr) {
            // 检查属性值是否为undefined或null，如果是则赋值为""
            if (attr[key] == null) attr[key] = "";
        }
        return attr;// 返回组装好的敌人对象
    };



    public function parseEventInfo(data):Array{
        var eventData = ObjectUtil.toArray(data.Event);
        var info = [];
        for (var i:Number = 0; i < eventData.length; i++){
            info.push(new StageEvent(eventData[i]));
        }
        return info;
    }

    public function parseTriggerInfo(data):Array{
        return ObjectUtil.toArray(data.Trigger);
    }

}