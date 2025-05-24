import org.flashNight.gesh.json.LoadJson.*;
import org.flashNight.naki.DataStructures.*;
import org.flashNight.gesh.object.ObjectUtil;

var loader:SkillTreeLoader = new SkillTreeLoader(
    "data/skills/skills_metadata.json", 
    "data/skills/skills_tree_config.json",
    "JSON"
);

loader.loadAll(
    function(result:Object):Void {
        // result.skillMetadata 就是技能元数据
        // result.skillDAG      就是技能树依赖图(DAG)

        trace("技能信息加载完成！");
        
        trace(ObjectUtil.toString(result));

    },
    function(error:String):Void {
        trace("加载失败: " + error);
    }
);
