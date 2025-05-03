class org.flashNight.gesh.depth.DepthManager {
    private var container:MovieClip;       // 母影片剪辑
    private var depthTree:TreeSet;         // 用于深度排序的AVL树
    private var mcMap:Object;              // 影片剪辑到节点的哈希表映射
    private var updateQueue:Array;         // 延迟更新队列
    private var needsProcessing:Boolean;   // 是否需要处理队列
    
    // 构造函数
    public function DepthManager(container:MovieClip) {
        this.container = container;
        this.mcMap = {};
        this.updateQueue = [];
        this.needsProcessing = false;
        
        // 创建深度树 - 按深度值升序排序
        this.depthTree = new TreeSet(function(a, b) {
            // a和b是DepthNode对象
            return a.depth - b.depth;
        });
        
        // 初始化 - 处理容器中现有的影片剪辑
        initializeFromContainer();
        
        // 设置帧事件监听器用于延迟处理
        container.onEnterFrame = Delegate.create(this, processUpdateQueue);
    }
    
    // 更新MovieClip的目标深度
    public function updateDepth(mc:MovieClip, targetDepth:Number):Void {
        // 1. 快速查找节点
        var mcName:String = mc._name;
        var node:DepthNode = mcMap[mcName];
        
        // 2. 如果节点不存在，创建并添加
        if (node == undefined) {
            node = new DepthNode(mc, targetDepth);
            mcMap[mcName] = node;
            depthTree.add(node);
            mc.swapDepths(targetDepth); // 首次添加时执行一次swapDepths
            return;
        }
        
        // 3. 检查深度是否变化
        if (node.depth == targetDepth) {
            return; // 无变化，跳过
        }
        
        // 4. 深度变化 - 加入更新队列
        node.targetDepth = targetDepth;
        if (updateQueue.indexOf(node) == -1) {
            updateQueue.push(node);
            needsProcessing = true;
        }
    }
    
    // 处理更新队列 - 在onEnterFrame中调用
    private function processUpdateQueue():Void {
        if (!needsProcessing || updateQueue.length == 0) return;
        
        // 限制每帧处理的数量，避免性能问题
        var maxUpdatesPerFrame:Number = 5; 
        var processed:Number = 0;
        
        while (updateQueue.length > 0 && processed < maxUpdatesPerFrame) {
            var node:DepthNode = updateQueue.shift();
            processed++;
            
            // 检查节点是否仍然有效（可能已被移除）
            if (!mcMap[node.mc._name]) continue;
            
            // 确定是否需要重构树
            var depthDiff:Number = Math.abs(node.depth - node.targetDepth);
            var needsTreeRestructure:Boolean = depthDiff > 10; // 阈值可调整
            
            if (needsTreeRestructure) {
                // 删除并重新插入
                depthTree.remove(node);
                node.depth = node.targetDepth;
                depthTree.add(node);
            } else {
                // 直接更新深度值
                node.depth = node.targetDepth;
            }
            
            // 执行实际的深度交换
            node.mc.swapDepths(node.depth);
        }
        
        needsProcessing = (updateQueue.length > 0);
    }
    
    // 销毁和清理资源
    public function dispose():Void {
        container.onEnterFrame = null;
        mcMap = null;
        depthTree = null;
        updateQueue = null;
        container = null;
    }
    
    // 其他辅助方法...
}