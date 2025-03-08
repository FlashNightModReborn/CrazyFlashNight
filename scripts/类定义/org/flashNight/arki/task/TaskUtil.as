// import org.flashNight.neur.Server.ServerManager;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.arki.item.ItemUtil;
/*
 * TaskUtil 静态类，存储任务数据，任务文本数据与任务相关函数
 */

class org.flashNight.arki.task.TaskUtil{

    public static var tasks:Object;
    public static var task_chains:Object;
    public static var task_in_chains_by_sequence:Object;
    public static var tasks_of_npc:Object;
    public static var task_texts:Object;

    public static function getTaskData(id){
        return ObjectUtil.clone(tasks[id]);
    }

    public static function getTaskText(str){
        if (str.charAt(0) == "$") return task_texts[str];
        return str;
    }

    public static function ParseTaskData(rawTaskData,rawTextData){
        //先配置任务文本数据
        task_texts = rawTextData;
        //新建任务数据字典
        tasks = new Object();
        task_chains = new Object();
        task_in_chains_by_sequence = new Object();
        tasks_of_npc = new Object();
        for(var i = 0; i < rawTaskData.length; i++){
            var taskData = rawTaskData[i];
            // 分解chain
            taskData.chain = taskData.chain.split("#");
            var chainName = taskData.chain[0];
            if(taskData.chain[1]){
                taskData.chain[1] = Number(taskData.chain[1]);
                // 检查对应字典/数组是否存在
                if (task_chains[chainName] == null) task_chains[chainName] = new Object();
                if (task_in_chains_by_sequence[chainName] == null) task_in_chains_by_sequence[chainName] = new Array();
                task_chains[taskData.chain[0]][taskData.chain[1]] = taskData.id;
                task_in_chains_by_sequence[taskData.chain[0]].push(taskData.chain[1]);
            }
            // 建立NPC可接取的任务字典
            var get_npc = taskData.get_npc;
            if (tasks_of_npc[get_npc] == null) tasks_of_npc[get_npc] = new Array();
            tasks_of_npc[get_npc].push(taskData.id);
            // 以id和任务名分别作为键，将任务数据存入tasks
            tasks[taskData.id] = taskData;
            var title = typeof task_texts[taskData.title] == "string" ? task_texts[taskData.title] : taskData.title;
            tasks[title] = taskData;
        }
    }

    public static function ParseTaskText(data){
        task_texts = data;
    }

    public static function taskAvailable(index){
    }

    public static function containTaskItems(items:Array):Boolean{
        if(items == null) return true;
        var itemArray = ItemUtil.getRequirementFromTask(items);
        return ItemUtil.contain(itemArray) != null;
    }
}
