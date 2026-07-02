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

    public static function getNpcHotspotKey(npcName:String, hotspotId:String):String{
        return String(npcName) + "\n" + String(hotspotId);
    }

    private static function appendTaskIdList(out:Array, src:Array):Void{
        if(src == undefined || src.length == undefined) return;
        for(var i:Number = 0; i < src.length; i++){
            out.push(src[i]);
        }
    }

    public static function getTasksForNpc(npcName:String, hotspotId:String):Array{
        var out:Array = [];
        if(hotspotId != undefined && hotspotId != ""){
            appendTaskIdList(out, tasks_of_npc[getNpcHotspotKey(npcName, hotspotId)]);
        }
        appendTaskIdList(out, tasks_of_npc[npcName]);
        return out;
    }

    public static function taskNpcMatches(taskData:Object, role:String, npcName:String, hotspotId:String):Boolean{
        if(taskData == undefined) return false;
        var expectedNpc:String;
        var expectedHotspot:String;
        if(role == "finish"){
            expectedNpc = taskData.finish_npc != undefined ? String(taskData.finish_npc) : "";
            expectedHotspot = taskData.finish_npc_hotspot != undefined ? String(taskData.finish_npc_hotspot) : "";
        }else{
            expectedNpc = taskData.get_npc != undefined ? String(taskData.get_npc) : "";
            expectedHotspot = taskData.get_npc_hotspot != undefined ? String(taskData.get_npc_hotspot) : "";
        }
        if(expectedNpc != npcName) return false;
        if(expectedHotspot == "") return true;
        return (hotspotId != undefined && hotspotId != "" && expectedHotspot == hotspotId);
    }

    public static function canAutoAcceptNextAtFinishNpc(finishedTaskData:Object, nextTaskData:Object):Boolean{
        if(finishedTaskData == undefined || nextTaskData == undefined) return false;
        if(nextTaskData.get_npc != finishedTaskData.finish_npc) return false;
        var nextHotspot:String = nextTaskData.get_npc_hotspot != undefined ? String(nextTaskData.get_npc_hotspot) : "";
        if(nextHotspot == "") return true;
        var finishHotspot:String = finishedTaskData.finish_npc_hotspot != undefined ? String(finishedTaskData.finish_npc_hotspot) : "";
        return (finishHotspot != "" && finishHotspot == nextHotspot);
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
            var get_hotspot = taskData.get_npc_hotspot != undefined ? String(taskData.get_npc_hotspot) : "";
            var get_key = get_hotspot != "" ? getNpcHotspotKey(get_npc, get_hotspot) : get_npc;
            if (tasks_of_npc[get_key] == null) tasks_of_npc[get_key] = new Array();
            tasks_of_npc[get_key].push(taskData.id);
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

    // ═══════════════════════════════════════════════════════════
    // conditions — 与成就共享的判定条件（可选字段，设计 docs/任务成就-判定层共享-设计-2026-06-11.md §3）
    //   形状：taskData.conditions = [{type, params, target, label, sinceAccept?}]
    //   读数走共享 ObjectiveEvaluator.rawOf；sinceAccept=true 扣接取时基线
    //   taskEntry.requirements.condBase[i]（AddTask 拍快照，窗口语义；老档无 condBase → 终身语义降级）。
    //   生命周期/奖励链不在此层：本层纯谓词，taskCompleteCheck 合取调用。
    // ═══════════════════════════════════════════════════════════
    public static function checkConditions(taskData:Object, taskEntry:Object):Boolean{
        var conds:Array = taskData.conditions;
        if(conds == undefined || conds.length == undefined || conds.length == 0) return true;
        for(var i:Number = 0; i < conds.length; i++){
            if(conditionCur(conds[i], taskEntry, i) < conditionTarget(conds[i])) return false;
        }
        return true;
    }

    // 面板进度行（与成就 progressOf 同口径：cur 封顶 target，永不返 null/NaN）
    public static function conditionsProgress(taskData:Object, taskEntry:Object):Array{
        var out:Array = [];
        var conds:Array = taskData.conditions;
        if(conds == undefined || conds.length == undefined) return out;
        for(var i:Number = 0; i < conds.length; i++){
            var target:Number = conditionTarget(conds[i]);
            var cur:Number = conditionCur(conds[i], taskEntry, i);
            if(cur > target) cur = target;
            out.push({
                label: (conds[i].label != undefined) ? String(conds[i].label) : String(conds[i].type),
                cur: cur,
                target: target
            });
        }
        return out;
    }

    // 任一进行中任务带 conditions（A2：scanTick 借心跳刷新任务红点的门控，零任务时零成本）
    public static function anyActiveConditions():Boolean{
        var arr:Array = _root.tasks_to_do;
        if(arr == undefined) return false;
        for(var i:Number = 0; i < arr.length; i++){
            if(arr[i] == undefined) continue;
            var td:Object = tasks[arr[i].id];
            if(td != undefined && td.conditions != undefined && td.conditions.length > 0) return true;
        }
        return false;
    }

    private static function conditionTarget(cond:Object):Number{
        var t:Number = Number(cond.target);
        return (isNaN(t) || t < 1) ? 1 : t;
    }

    private static function conditionCur(cond:Object, taskEntry:Object, idx:Number):Number{
        var cur:Number = org.flashNight.arki.achievement.ObjectiveEvaluator.rawOf(cond.type, cond.params);
        if(cond.sinceAccept == true && taskEntry != undefined && taskEntry.requirements != undefined
                && taskEntry.requirements.condBase != undefined){
            var base:Number = Number(taskEntry.requirements.condBase[idx]);
            if(!isNaN(base)) cur = Math.max(0, cur - base);
        }
        if(isNaN(cur) || cur < 0) cur = 0;
        return cur;
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
