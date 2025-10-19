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

    public static var specialRequirements:Object;

    // 任务进度引导数据
    public static var progress_guides:Object;


    public static function getTaskData(index){
        return ObjectUtil.clone(tasks[index]);
    }

    /*
     * 获取任务数据（返回原始数据，不进行拷贝）
     * as2不支持protected，原则上只能在高性能需求时谨慎使用
     */
    public static function getRawTaskData(index){
        return tasks[index];
    }

    public static function getTaskText(str:String):String{
        if (str.charAt(0) == "$") return task_texts[str];
        return str;
    }

    public static function ParseTaskData(rawTaskData, rawTextData):Void{
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

    public static function checkItemRequirements(taskData):Boolean{
        //目前逻辑为提交物品与持有物品不可兼容，优先判定提交物品
        if(taskData.finish_submit_items.length > 0 && !containTaskItems(taskData.finish_submit_items)){
            return false;
        }else if(taskData.finish_contain_items.length > 0 && !containTaskItems(taskData.finish_contain_items)){
            return false;
        }
        return true;
    }

    public static function checkSpecialRequirements(taskData):Boolean{
        var args = taskData.special_requirements;
        if(args.length > 0){
            return specialRequirements[args[0]].check(args);
        }
        return true;
    }

    public static function containTaskItems(items:Array):Boolean{
        if(items == null) return true;
        var itemArray = ItemUtil.getRequirementFromTask(items);
        return ItemUtil.contain(itemArray) != null;
    }

    /**
     * 获取指定进度的引导数据
     * @param progress 主线任务进度
     * @return Object 引导数据对象，包含 title 和 description，如果不存在则返回 null
     */
    public static function getProgressGuide(progress:Number):Object {
        if(progress_guides == null) return null;
        return progress_guides[progress];
    }

    /**
     * 解析引导数据并存储
     * @param rawGuideData 原始引导数据
     */
    public static function ParseGuideData(rawGuideData):Void {
        progress_guides = new Object();
        if(rawGuideData == null || rawGuideData.guides == null) {
            trace("TaskUtil: 引导数据为空或格式不正确");
            return;
        }
        var guides = rawGuideData.guides;
        for(var i = 0; i < guides.length; i++){
            var guide = guides[i];
            progress_guides[guide.progress] = guide;
        }
        trace("TaskUtil: 成功加载 " + guides.length + " 条进度引导数据");
    }
}
