// 文件路径: org/flashNight/naki/DataStructures/StatefulNAryTreeNode.as
import org.flashNight.naki.DataStructures.NAryTreeNode;
import org.flashNight.neur.StateMachine.FSM_StateMachine;
import org.flashNight.neur.StateMachine.Machine;
import org.flashNight.neur.StateMachine.Status;

/**
 * 增强版 N 叉树节点类，通过组合绑定状态机 (FSM_StateMachine)
 * 实现节点状态与树结构的协同管理
 */
class org.flashNight.naki.DataStructures.StatefulNAryTreeNode extends NAryTreeNode {
    // ------------ 状态机相关属性 ------------
    private var _stateMachine:FSM_StateMachine; // 组合的状态机实例
    private var _stateData:Object;              // 状态机专用数据黑板

    // ------------ 构造函数 ------------
    public function StatefulNAryTreeNode(data:Object) {
        super(data);
        initStateMachine();
    }

    // ------------ 状态机初始化 ------------
    private function initStateMachine():Void {
        // 创建状态机实例，绑定默认回调
        _stateMachine = new FSM_StateMachine(
            this.onStateAction,  // onAction 回调
            this.onStateEnter,   // onEnter 回调
            this.onStateExit     // onExit 回调
        );

        // 初始化状态机数据黑板
        _stateData = {
            node: this,          // 反向引用节点
            progress: {},        // 任务进度数据
            conditions: {}       // 动态条件缓存
        };
    }

    // ------------ 状态机访问器 ------------
    public function get stateMachine():FSM_StateMachine {
        return _stateMachine;
    }

    public function get stateData():Object {
        return _stateData;
    }

    // ------------ 状态机回调 (可被子类覆盖) ------------
    private function onStateAction():Void {
        // 默认每帧行为（例如更新任务进度）
        trace("[State] Action @ " + this.data.name);
    }

    private function onStateEnter():Void {
        // 默认进入状态行为（例如激活子节点）
        trace("[State] Enter: " + _stateMachine.getActiveStateName());
        this.tree.registerNode(this); // 自动注册到树
    }

    private function onStateExit():Void {
        // 默认退出状态行为（例如清理资源）
        trace("[State] Exit: " + _stateMachine.getActiveStateName());
    }

    // ------------ 增强版子节点管理 ------------
    override public function addChild(child:NAryTreeNode):Void {
        super.addChild(child);
        
        // 自动传递状态机相关配置
        if (child instanceof StatefulNAryTreeNode) {
            var statefulChild:StatefulNAryTreeNode = StatefulNAryTreeNode(child);
            statefulChild.stateData.global = this._stateData.global; // 共享全局数据
        }
    }

    // ------------ 状态驱动树操作 ------------
    public function activateChildren():Void {
        // 激活所有子节点的状态机
        this.traversePreOrder(function(node:NAryTreeNode):Boolean {
            if (node instanceof StatefulNAryTreeNode) {
                node.stateMachine.ChangeState("active");
            }
            return true;
        });
    }

    // ------------ 条件检查快捷方法 ------------
    public function checkCondition(conditionId:String):Boolean {
        // 从数据黑板或外部系统获取条件结果
        return _stateData.conditions[conditionId] || false;
    }
}