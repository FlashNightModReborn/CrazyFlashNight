var npcskillloader = org.flashNight.gesh.json.LoadJson.NPCSkillLoader.getInstance();
npcskillloader.loadNPCSkills(
    function(data:Object):Void {
		trace("主程序：NPC技能数据加载成功！");
		_root.NPC技能表 = data;
    },
    function():Void {
        trace("主程序：NPC技能数据加载失败！");
    }
);