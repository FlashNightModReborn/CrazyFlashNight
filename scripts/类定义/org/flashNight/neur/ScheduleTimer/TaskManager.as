import org.flashNight.neur.ScheduleTimer.*;
import org.flashNight.neur.Server.*; 
import org.flashNight.neur.Event.*;
import org.flashNight.naki.DataStructures.*;
import org.flashNight.aven.Coordinator.*;

/**
 * TaskManager.as
 * 任务调度管理器类
 * -----------------------------------------------------------------------------
 * 主要功能：
 *  1. 管理任务调度（添加、更新、删除、延迟任务等）。
 *  2. 借助外部 ScheduleTimer 组件（例如 CerberusScheduler）进行任务的插入、重调度与删除操作。
 *  3. 根据帧率或每帧毫秒数计算任务延迟，并按帧更新进行到期任务处理。
 *
 * 使用说明：
 *  1. 在帧计时器初始化时构造 TaskManager 实例，并传入 ScheduleTimer 实例与当前帧率参数。
 *  2. 每帧调用 updateFrame() 方法，系统内部会根据任务状态来执行、重调度或删除任务。
 *  3. 针对间隔为 0 的任务，会存放于 zeroFrameTasks 中，立即执行；其他任务存放在 taskTable 中。
 *
 * 内部实现细节：
 *  - 采用一个计数器 taskIdCounter 作为任务唯一标识生成器，所有任务均以字符串形式标识。
 *  - 内部分为两部分任务存储：taskTable（非零帧任务）和 zeroFrameTasks（立即执行的零帧任务）。
 *  - updateFrame() 方法首先获取到期任务列表，然后依次执行任务回调并根据重复次数逻辑进行删除或重调度；
 *    接着处理所有零帧任务。
 */
class org.flashNight.neur.ScheduleTimer.TaskManager {
    // 私有属性
    private var scheduleTimer:CerberusScheduler; // 外部任务调度器实例，负责任务调度（如插入、重调度、删除节点）
    private var taskTable:Object;                // 存放待调度任务（非零间隔任务），以任务ID（字符串）为键
    private var zeroFrameTasks:Object;           // 存放零帧（间隔<=0，需立即执行）任务，同样以任务ID为键
    private var taskIdCounter:Number;            // 任务ID生成器，递增方式生成唯一标识
    // [FIX v1.3] 修正命名：framesPerMs 表示每毫秒对应的帧数，用于将毫秒转换为帧数
    // 例如 30 FPS 时，framesPerMs = 30/1000 = 0.03，即 1000ms 对应 30 帧
    private var framesPerMs:Number;
    // [FIX v1.3] 复用数组，避免 updateFrame 热路径每帧分配新数组导致 GC 压力
    private var _reusableZeroIds:Array;
    private var _reusableToDelete:Array;

    /**
     * 构造函数
     * @param scheduleTimer 外部任务调度器实例（如 CerberusScheduler），负责内部任务队列操作
     * @param frameRate 当前帧率，用于计算毫秒到帧数的转换因子
     */
    public function TaskManager(scheduleTimer:CerberusScheduler, frameRate:Number) {
        this.scheduleTimer = scheduleTimer;
        // [FIX v1.3] 计算每毫秒对应的帧数：例如帧率为 30 FPS，则 framesPerMs = 30/1000 = 0.03
        // 用法：intervalFrames = intervalMs * framesPerMs，例如 1000ms * 0.03 = 30 帧
        this.framesPerMs = frameRate / 1000;
        // 初始化存储任务的对象
        this.taskTable = {};
        this.zeroFrameTasks = {};
        // 初始化任务 ID 计数器
        this.taskIdCounter = 0;
        // [FIX v1.3] 初始化复用数组
        this._reusableZeroIds = [];
        this._reusableToDelete = [];
    }

    /**
     * 每帧更新时调用，负责检查任务队列与零帧任务并依次执行
     * -----------------------------------------------------------------------------
     * 实现流程：
     *  1. 调用 scheduleTimer.tick() 获取任务链表（TaskIDNode 链表）。
     *  2. 遍历链表：根据任务ID从 taskTable 取得任务，调用任务回调函数 action()。
     *  3. 根据任务的重复计数（repeatCount）判断：
     *      - 当任务执行次数为 1，则执行完后删除任务；
     *      - 当任务可重复（repeatCount 为 true 表示无限循环，或者为数字大于1）时，若为有限次则减1，并重设 pendingFrames，
     *        然后重新加入调度队列；
     *      - 否则删除任务记录。
     *  4. 遍历 zeroFrameTasks，立即执行所有零帧任务（同样依据 repeatCount 做判断）。
     */
    public function updateFrame():Void {
        // 从调度器中获取当前帧到期的任务链表
        var tasks = this.scheduleTimer.tick();
        if (tasks != null) {
            // 从链表中获取第一个任务节点
            var node:TaskIDNode = tasks.getFirst();
            while (node != null) {
                // 保存下一个节点，避免在当前节点操作时丢失节点引用
                var nextNode:TaskIDNode = node.next;
                // 任务ID转换为字符串（TaskID 为字符串类型）
                var taskID:String = node.taskID;
                // 优先从 taskTable 中查找任务，零帧任务不在此处执行
                var task:Task = this.taskTable[taskID];
                if (task) {
                    // 执行任务回调函数

                    // _root.服务器.发布服务器消息("taskTable: " + task.toString());

                    // 执行任务回调函数
                    task.action();

                    // [FIX v1.1] 竞态条件修复：检查任务是否仍存在于taskTable中
                    // 回调可能调用 removeTask(taskID) 删除当前任务，此时应跳过重调度逻辑
                    if (!this.taskTable[taskID]) {
                        // 任务已被回调删除，节点已在 removeTask 中被回收，跳过继续处理
                        node = nextNode;
                        continue;
                    }

                    // 根据任务重复逻辑进行处理：
                    // 如果只执行一次，则从任务表中删除；如果重复，则根据计数（或无限循环）重新调度
                    if (task.repeatCount === 1) {
                        // 单次执行任务：执行后删除任务
                        delete this.taskTable[taskID];
                        // [FIX v1.4] 回收已到期的节点到节点池
                        this.scheduleTimer.recycleExpiredNode(node);
                    } else if (task.repeatCount === true || task.repeatCount > 1) {
                        // 无限循环或有限多次重复：如果是有限次重复则减1
                        if (task.repeatCount !== true) {
                            task.repeatCount -= 1;
                        }
                        // 重置待调度帧数为任务的间隔帧数
                        task.pendingFrames = task.intervalFrames;
                        // 重新加入调度器，获得新的节点引用
                        task.node = this.scheduleTimer.evaluateAndInsertTask(taskID, task.pendingFrames);
                        // [FIX v1.4] 回收旧节点（新节点已由 evaluateAndInsertTask 分配）
                        this.scheduleTimer.recycleExpiredNode(node);
                    } else {
                        // 其他情况，删除任务
                        delete this.taskTable[taskID];
                        // [FIX v1.4] 回收已到期的节点到节点池
                        this.scheduleTimer.recycleExpiredNode(node);
                    }
                } else {
                    // [FIX v1.5] 防御性回收：理论上不应到达此处
                    // 如果 tick() 返回的节点在 taskTable 中找不到对应 Task，
                    // 可能是非标准用法（直接调用 CerberusScheduler.evaluateAndInsertTask）
                    // 为防止节点泄漏，进行防御性回收
                    this.scheduleTimer.recycleExpiredNode(node);
                }
                // 继续处理下一个任务节点
                node = nextNode;
            }
        }
        // [FIX v1.2] 单独处理零帧任务：修复 for-in 迭代中删除元素和竞态条件问题
        // [FIX v1.3] 复用数组，避免每帧分配新数组导致 GC 压力
        var zeroIds:Array = this._reusableZeroIds;
        zeroIds.length = 0;  // 清空复用数组
        for (var id in this.zeroFrameTasks) {
            zeroIds[zeroIds.length] = id;
        }

        // 遍历收集的ID数组执行任务
        var toDelete:Array = this._reusableToDelete;
        toDelete.length = 0;  // 清空复用数组
        var i:Number = zeroIds.length;
        while (--i >= 0) {
            var zId:String = zeroIds[i];
            var zTask:Task = this.zeroFrameTasks[zId];

            // 任务可能已被其他回调删除，跳过
            if (!zTask) continue;

            //_root.服务器.发布服务器消息("zeroFrameTasks " + zTask.toString());

            zTask.action();

            // [FIX v1.2] 竞态条件修复：检查任务是否仍存在于zeroFrameTasks中
            // 回调可能调用 removeTask(zId) 删除当前任务
            if (!this.zeroFrameTasks[zId]) {
                continue;  // 任务已被回调删除，跳过后续处理
            }

            // 若非无限循环任务则减少重复次数，并检查是否执行完毕
            if (zTask.repeatCount !== true) {
                zTask.repeatCount -= 1;
                if (zTask.repeatCount <= 0) {
                    // 标记待删除，稍后统一删除
                    toDelete[toDelete.length] = zId;
                }
            }
        }

        // 统一删除已完成的零帧任务
        i = toDelete.length;
        while (--i >= 0) {
            delete this.zeroFrameTasks[toDelete[i]];
        }
    }

    /**
     * 添加任务（通用版本）
     * -----------------------------------------------------------------------------
     * 根据用户提供的回调函数、执行间隔和重复次数创建任务，并返回生成的任务ID。
     *
     * @param action 任务执行的回调函数。
     * @param interval 任务间隔（单位：毫秒或其他与 msPerFrame 配合的单位）。
     * @param repeatCount 重复次数：1 表示单次执行，true 表示无限循环，大于1 表示重复执行指定次数。
     * @param parameters 动态参数数组（可选），将传递给回调函数。
     * @return 返回生成的任务ID（字符串类型）。
     */
    public function addTask(action:Function, interval:Number, repeatCount, parameters:Array):String {
        // 生成任务ID（以字符串保存，便于和其他任务使用同一类型）
        var taskID:String = String(++this.taskIdCounter);

        // _root.服务器.发布服务器消息("addTask" + " " + taskID);

        // 根据每帧耗时计算任务的间隔帧数，并向上取整
        var intervalFrames:Number = ((interval * this.framesPerMs) + 0.9999999999) | 0;
        // 创建任务实例，构造参数：任务ID、间隔帧数、重复次数
        var task:Task = new Task(taskID, intervalFrames, repeatCount);
        // 使用 Delegate 封装任务回调函数和传递参数，确保执行环境正确
        task.action = Delegate.createWithParams(task, action, parameters);
        // 判断间隔帧数：若间隔为 0，则归入零帧任务，否则加入正常调度任务表
        if (intervalFrames <= 0) {
            this.zeroFrameTasks[taskID] = task;
        } else {
            task.pendingFrames = intervalFrames; // 初始化 pendingFrames
            // 通过 ScheduleTimer 对象插入任务，返回任务节点引用
            task.node = this.scheduleTimer.evaluateAndInsertTask(taskID, intervalFrames);
            this.taskTable[taskID] = task;
        }
        return taskID;
    }

    /**
     * 添加单次任务（执行一次，当间隔小于等于0时直接执行）
     * -----------------------------------------------------------------------------
     * 如果 interval 小于等于0，任务将立即执行且返回值为 null；否则创建任务并加入调度器。
     *
     * @param action 回调函数。
     * @param interval 任务间隔。
     * @param parameters 动态参数数组（可选）。
     * @return 若立即执行则返回 null，否则返回生成的任务ID（字符串）。
     */
    public function addSingleTask(action:Function, interval:Number, parameters:Array):String {
        // 若间隔 <= 0，直接通过 Delegate 执行回调，不加入任务队列
        if (interval <= 0) {
            var boundAction:Function = Delegate.createWithParams(null, action, parameters);
            boundAction();
            return null;
        } else {
            // 创建任务并加入调度（repeatCount 固定为 1，代表单次执行）
            var taskID:String = String(++this.taskIdCounter);

            //_root.服务器.发布服务器消息("addSingleTask" + " " + taskID);

            var intervalFrames:Number = ((interval * this.framesPerMs) + 0.9999999999) | 0;
            var task:Task = new Task(taskID, intervalFrames, 1);
            task.action = Delegate.createWithParams(task, action, parameters);
            if (intervalFrames <= 0) {
                this.zeroFrameTasks[taskID] = task;
            } else {
                task.pendingFrames = intervalFrames;
                task.node = this.scheduleTimer.evaluateAndInsertTask(taskID, intervalFrames);
                this.taskTable[taskID] = task;
            }
            return taskID;
        }
    }

    /**
     * 添加循环任务（无限重复执行的任务）
     * -----------------------------------------------------------------------------
     * 创建任务并设置 repeatCount 为 true，表示该任务会无限重复执行。
     *
     * @param action 回调函数。
     * @param interval 任务间隔。
     * @param parameters 动态参数数组（可选）。
     * @return 返回生成的任务ID（字符串）。
     */
    public function addLoopTask(action:Function, interval:Number, parameters:Array):String {
        var taskID:String = String(++this.taskIdCounter);

        //_root.服务器.发布服务器消息("addLoopTask" + " " + taskID);

        var intervalFrames:Number = ((interval * this.framesPerMs) + 0.9999999999) | 0;
        // 创建任务时将 repeatCount 设置为 true，无限循环执行
        var task:Task = new Task(taskID, intervalFrames, true);
        task.action = Delegate.createWithParams(task, action, parameters);
        if (intervalFrames <= 0) {
            this.zeroFrameTasks[taskID] = task;
        } else {
            task.pendingFrames = intervalFrames;
            task.node = this.scheduleTimer.evaluateAndInsertTask(taskID, intervalFrames);
            this.taskTable[taskID] = task;
        }
        return taskID;
    }

    /**
     * 添加或更新任务
     * -----------------------------------------------------------------------------
     * 若 obj.taskLabel 中已有指定 labelName 的任务，则更新任务的回调与间隔，
     * 否则创建新任务，默认 repeatCount 为 1（单次执行）。
     *
     * @param obj 任务所属对象，用于记录任务标识。
     * @param labelName 任务标签名称，用以在同一对象中唯一标识任务。
     * @param action 回调函数。
     * @param interval 任务间隔。
     * @param parameters 动态参数数组（可选）。
     * @return 返回任务ID（字符串）。
     */
    public function addOrUpdateTask(obj:Object, labelName:String, action:Function, interval:Number, parameters:Array):String {
        if (!obj) return null;
        // 若对象中不存在该 labelName 对应的任务，则生成新的任务ID
        if (!obj.taskLabel[labelName]) {
            // 如果对象上没有 taskLabel 属性，则初始化该属性用于存储任务标识
            if (!obj.taskLabel) {
                obj.taskLabel = {};
                _global.ASSetPropFlags(obj, ["taskLabel"], 1, false);
            }
            obj.taskLabel[labelName] = ++this.taskIdCounter;
        }
        // 使用对象内的任务标识作为任务ID（字符串）
        var taskID:String = obj.taskLabel[labelName];
        // _root.服务器.发布服务器消息("addOrUpdateTask labelName:" + labelName + " " + taskID);
        var intervalFrames:Number = ((interval * this.framesPerMs) + 0.9999999999) | 0;
        // 从任务表或零帧任务中查找是否已有该任务
        var task:Task = this.taskTable[taskID] || this.zeroFrameTasks[taskID];

        // [FIX v1.6] 幽灵 ID 检测：如果 taskLabel 存在但任务实例已死（被手动 removeTask 删除），
        // 说明是脏数据，必须强制生成新 ID。与 addLifecycleTask 保持一致的检测逻辑。
        // 注意：addOrUpdateTask 没有 isNewTask 标记，因为不涉及 unload 回调绑定
        if (!task && taskID != undefined) {
            // 标签存在但任务不存在 -> 强制生成新 ID
            taskID = String(++this.taskIdCounter);
            obj.taskLabel[labelName] = taskID;
        }

        if (task) {
            // 更新任务的回调、间隔等信息
            task.action = Delegate.createWithParams(obj, action, parameters);
            task.intervalFrames = intervalFrames;
            // 如果更新后任务间隔为 0，则归入零帧任务中管理
            if (intervalFrames === 0) {
                if (this.taskTable[taskID]) {
                    this.scheduleTimer.removeTaskByNode(task.node);
                    delete task.node;
                    delete this.taskTable[taskID];
                }
                this.zeroFrameTasks[taskID] = task;
            } else {
                // 如果原来为零帧任务，则移至正常任务表
                if (this.zeroFrameTasks[taskID]) {
                    delete this.zeroFrameTasks[taskID];
                    task.pendingFrames = intervalFrames;
                    task.node = this.scheduleTimer.evaluateAndInsertTask(taskID, intervalFrames);
                    this.taskTable[taskID] = task;
                } else {
                    // 否则，直接重设 pendingFrames 并重新调度
                    task.pendingFrames = intervalFrames;
                    // [FIX v1.1] 更新节点引用，避免节点引用失效
                    task.node = this.scheduleTimer.rescheduleTaskByNode(task.node, intervalFrames);
                }
            }
        } else {
            // 若任务不存在，则创建一个新的单次执行任务（repeatCount 为 1）
            task = new Task(taskID, intervalFrames, 1);
            task.action = Delegate.createWithParams(obj, action, parameters);
            if (intervalFrames === 0) {
                this.zeroFrameTasks[taskID] = task;
            } else {
                task.pendingFrames = intervalFrames;
                task.node = this.scheduleTimer.evaluateAndInsertTask(taskID, intervalFrames);
                this.taskTable[taskID] = task;
            }
        }
        return taskID;
    }

    /**
     * 添加生命周期任务
     * -----------------------------------------------------------------------------
     * 该任务类似于 addOrUpdateTask，但设置为无限循环执行（repeatCount = true），
     * 并使用 EventCoordinator.addUnloadCallback 为对象绑定卸载时自动移除任务的回调，
     * 防止任务遗留而导致内存泄漏。
     *
     * 【契约】：
     * - 避免混用 addLifecycleTask 和手动 removeTask()
     * - 如需手动控制任务，请使用 addTask/addSingleTask 或 removeLifecycleTask()
     *
     * 【重要：unload 回调语义 - S2 文档强化 v1.6】
     * - unload 回调一旦注册，无法撤销（EventCoordinator 设计限制）
     * - 如果手动调用 removeTask(taskID) 删除任务，unload 回调仍会在对象卸载时触发
     * - 此时 unload 回调会尝试删除一个已不存在的任务，这是安全的（removeTask 会静默忽略）
     * - 但如果在 removeTask 后又调用 addLifecycleTask 创建同名任务：
     *   - 幽灵 ID 检测会为新任务分配新 ID（v1.3 修复）
     *   - 旧的 unload 回调持有旧 ID，会尝试删除旧 ID（不存在，安全）
     *   - 新的 unload 回调持有新 ID，会正确删除新任务
     * - 推荐：使用 removeLifecycleTask(obj, labelName) 替代 removeTask(taskID)
     *
     * @param obj 任务所属对象。
     * @param labelName 任务标签，在同一对象内唯一标识该任务。
     * @param action 任务回调函数。
     * @param interval 任务间隔。
     * @param parameters 动态参数数组（可选）。
     * @return 返回任务ID（字符串）。
     */
    public function addLifecycleTask(obj:Object, labelName:String, action:Function, interval:Number, parameters:Array):String {
        if (!obj) return null;

        // [FIX v1.2] 检查是否是新任务，用于决定是否需要注册 unload 回调
        // 避免重复注册导致的内存泄漏和多次 removeTask 调用
        var isNewTask:Boolean = false;

        // 若该 labelName 尚未存在，生成新的任务ID
        if (!obj.taskLabel) {
            obj.taskLabel = {};
            _global.ASSetPropFlags(obj, ["taskLabel"], 1, false);
        }

        if (!obj.taskLabel[labelName]) {
            obj.taskLabel[labelName] = ++this.taskIdCounter;
            isNewTask = true;  // 新分配的 taskID，需要注册回调
        }

        var taskID:String = obj.taskLabel[labelName];
        // _root.服务器.发布服务器消息("addLifecycleTask  labelName:" + labelName + " " + taskID);
        // 根据每帧耗时计算间隔对应的帧数
        var intervalFrames:Number = ((interval * this.framesPerMs) + 0.9999999999) | 0;
        // 使用 Delegate 封装回调函数，以确保执行时 this 指向正确，并传递参数
        var boundAction:Function = Delegate.createWithParams(obj, action, parameters);
        // 尝试查找已有任务（可能在 taskTable 或 zeroFrameTasks 中）
        var task:Task = this.taskTable[taskID] || this.zeroFrameTasks[taskID];

        // [FIX v1.3] 幽灵 ID 检测：如果 ID 存在于 Label 但任务实例已死（被手动 removeTask 删除），
        // 说明是脏数据，必须强制生成新 ID 以避免旧的 unload 回调错误杀死新任务
        if (!task && !isNewTask) {
            // 标签存在但任务不存在 -> 强制生成新 ID
            taskID = String(++this.taskIdCounter);
            obj.taskLabel[labelName] = taskID;
            isNewTask = true;  // 标记为新任务，需要重新绑定 unload 回调
        }

        if (task) {
            // 更新已有任务的回调和间隔，并设为无限循环（repeatCount = true）
            task.action = boundAction;
            task.intervalFrames = intervalFrames;
            task.repeatCount = true;
            // 根据新的间隔帧数判断放入零帧任务或正常任务表
            if (intervalFrames === 0) {
                if (this.taskTable[taskID]) {
                    this.scheduleTimer.removeTaskByNode(task.node);
                    delete task.node;
                    delete this.taskTable[taskID];
                }
                this.zeroFrameTasks[taskID] = task;
            } else {
                if (this.zeroFrameTasks[taskID]) {
                    delete this.zeroFrameTasks[taskID];
                    task.pendingFrames = intervalFrames;
                    task.node = this.scheduleTimer.evaluateAndInsertTask(taskID, intervalFrames);
                    this.taskTable[taskID] = task;
                } else {
                    task.pendingFrames = intervalFrames;
                    // [FIX v1.1] 更新节点引用，避免节点引用失效
                    task.node = this.scheduleTimer.rescheduleTaskByNode(task.node, intervalFrames);
                }
            }
        } else {
            // 创建新的无限循环任务
            // [FIX v1.3] 注意：此时 isNewTask 已在上方的幽灵 ID 检测中正确设置
            task = new Task(taskID, intervalFrames, true);
            task.action = boundAction;
            if (intervalFrames === 0) {
                this.zeroFrameTasks[taskID] = task;
            } else {
                task.pendingFrames = intervalFrames;
                task.node = this.scheduleTimer.evaluateAndInsertTask(taskID, intervalFrames);
                this.taskTable[taskID] = task;
            }
        }

        // [FIX v1.2] 仅在新任务时注册 unload 回调，避免重复注册导致的内存泄漏
        if (isNewTask) {
            var self:TaskManager = this;
            EventCoordinator.addUnloadCallback(obj, function():Void {
                self.removeTask(taskID);
                delete obj.taskLabel[labelName];
            });
        }

        return taskID;
    }

    /**
     * 移除任务
     * -----------------------------------------------------------------------------
     * 根据任务ID删除任务。如果任务存在于正常调度任务表中，则调用
     * scheduleTimer.removeTaskByNode() 移除调度器中的任务节点，并从 taskTable 中删除。
     * 如果任务存在于零帧任务中，则直接从 zeroFrameTasks 中删除。
     *
     * @param taskID 要移除的任务ID（字符串）。
     */
    public function removeTask(taskID:String):Void {
        // _root.服务器.发布服务器消息("removeTask" + " " + taskID);
        var task:Task = this.taskTable[taskID];
        if (task) {
            // 调用调度器接口移除任务节点
            this.scheduleTimer.removeTaskByNode(task.node);
            // 从任务表中删除任务记录
            delete this.taskTable[taskID];
        } else if (this.zeroFrameTasks[taskID]) {
            // 若任务在零帧任务中，则直接删除
            delete this.zeroFrameTasks[taskID];
        }
    }

    /**
     * [NEW v1.6] 移除生命周期任务
     * -----------------------------------------------------------------------------
     * 通过 obj 和 labelName 移除由 addLifecycleTask 创建的任务。
     * 此方法是 removeTask(taskID) 的便捷封装，适用于不跟踪 taskID 的场景。
     *
     * 【契约说明】：
     * - 此方法会同时清理 obj.taskLabel[labelName]，避免产生幽灵 ID
     * - 与 addLifecycleTask 的 unload 回调不冲突：如果对象已卸载，unload 回调会先执行
     * - 如果任务不存在（已被 unload 回调删除或从未创建），此方法安全地不执行任何操作
     *
     * 使用场景：
     * - 手动控制生命周期任务的生命周期（如角色切换技能时移除旧任务）
     * - 在对象卸载前主动清理任务（虽然 unload 回调会自动清理，但某些场景需要提前清理）
     *
     * @param obj       任务所属对象（与 addLifecycleTask 时传入的对象相同）
     * @param labelName 任务标签（与 addLifecycleTask 时传入的标签相同）
     * @return          如果任务存在并被移除返回 true，否则返回 false
     */
    public function removeLifecycleTask(obj:Object, labelName:String):Boolean {
        if (!obj || !obj.taskLabel) return false;

        var taskID:String = obj.taskLabel[labelName];
        if (taskID == undefined) return false;

        // 移除任务
        this.removeTask(taskID);

        // 清理标签，避免产生幽灵 ID
        delete obj.taskLabel[labelName];

        return true;
    }

    /**
     * 定位任务
     * -----------------------------------------------------------------------------
     * 根据任务ID查找对应的 Task 实例，先在 taskTable 中查找，如未找到再在 zeroFrameTasks 中查找。
     *
     * @param taskID 任务ID（字符串）。
     * @return 找到的 Task 实例或 null（若任务不存在）。
     */
    public function locateTask(taskID:String):Task {
        return this.taskTable[taskID] || this.zeroFrameTasks[taskID] || null;
    }

    /**
     * 延迟执行任务
     * -----------------------------------------------------------------------------
     * 为指定任务增加延迟时间（单位与 interval 相同）。
     * 处理方式：
     *  1. 如果 delayTime 为数字，则计算相应的延迟帧数并加至 task.pendingFrames 上。
     *  2. 如果 delayTime 非数字，则根据其是否为 true 判断：为 true 时设置 pendingFrames 为无限（Infinity），否则恢复为原间隔帧数。
     *  3. 若延迟后的 pendingFrames 小于等于 0，则将任务转为零帧任务。
     *  4. 否则，则重新将任务调度到 scheduleTimer 中（若原来为零帧任务则移至 taskTable）。
     *
     * @param taskID 任务ID（字符串）。
     * @param delayTime 延迟时间，单位与 interval 保持一致；也可传入非数字值来做特殊处理。
     * @return 若延迟设置成功返回 true，否则返回 false（未找到任务）。
     */
    public function delayTask(taskID:String, delayTime):Boolean {
        // 根据任务ID在正常任务和零帧任务中查找任务
        var task:Task = this.taskTable[taskID] || this.zeroFrameTasks[taskID];
        if (task) {
            var delayFrames:Number;
            // 判断 delayTime 是否为数字，如果不是，则根据其布尔值处理
            if (isNaN(delayTime)) {
                task.pendingFrames = (delayTime === true) ? Infinity : task.intervalFrames;
            } else {
                // 根据每帧耗时计算需要延迟的帧数，并累加到 pendingFrames 中
                delayFrames = Math.ceil(delayTime * this.framesPerMs);
                task.pendingFrames += delayFrames;
            }
            // 若累加后的 pendingFrames 小于等于 0，则将任务转移为零帧任务
            if (task.pendingFrames <= 0) {
                if (this.taskTable[taskID]) {
                    this.scheduleTimer.removeTaskByNode(task.node);
                    delete task.node;
                    delete this.taskTable[taskID];
                    this.zeroFrameTasks[taskID] = task;
                }
            } else {
                // 如果原来在零帧任务中，则移回正常任务表并重新调度
                if (this.zeroFrameTasks[taskID]) {
                    delete this.zeroFrameTasks[taskID];
                    task.node = this.scheduleTimer.evaluateAndInsertTask(taskID, task.pendingFrames);
                    this.taskTable[taskID] = task;
                } else {
                    // 若任务已在正常任务表中，则直接调用重调度方法更新 pendingFrames
                    // [FIX v1.1] 更新节点引用，避免节点引用失效
                    task.node = this.scheduleTimer.rescheduleTaskByNode(task.node, task.pendingFrames);
                }
            }
            return true;
        }
        return false;
    }
}
