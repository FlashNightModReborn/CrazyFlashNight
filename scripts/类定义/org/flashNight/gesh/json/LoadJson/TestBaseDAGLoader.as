import org.flashNight.gesh.json.LoadJson.BaseDAGLoader;
import org.flashNight.naki.DataStructures.DAG;
import org.flashNight.gesh.object.ObjectUtil;

class org.flashNight.gesh.json.LoadJson.TestBaseDAGLoader {

    public function TestBaseDAGLoader() {
        runTests();
    }
    
    // 简单断言方法：输出断言是否通过
    private function assert(condition:Boolean, message:String):Void {
        if (!condition) {
            trace("Assertion failed: " + message);
        } else {
            trace("Passed: " + message);
        }
    }
    
    public function runTests():Void {
        trace("===== 运行 BaseDAGLoader 测试 =====");
        testDictFormat();
        testArrayFormat();
        testCycleDetection();
        trace("===== BaseDAGLoader 测试结束 =====");
    }
    
    // 测试 JSON 数据为字典格式时的 DAG 构建
    private function testDictFormat():Void {
        trace("--- 测试字典格式 DAG ---");
        // 假定 JSON 文件路径位于资源目录下
        var filePath:String = "scripts/类定义/org/flashNight/gesh/json/LoadJson/TestDAG/test_dag_dict.json";

        var loader:BaseDAGLoader = new BaseDAGLoader(filePath, "JSON");
        loader.load(function(dag:DAG):Void {
            trace("字典格式 DAG 加载成功！");
            // 验证邻接关系：期望 A->["B", "C"], B->["D"], C->["D"], D->[]
            var neighborsA:Array = dag.getNeighbors("A");
            var neighborsB:Array = dag.getNeighbors("B");
            var neighborsC:Array = dag.getNeighbors("C");
            var neighborsD:Array = dag.getNeighbors("D");
            
            assert(neighborsA.length == 2 && neighborsA.indexOf("B") != -1 && neighborsA.indexOf("C") != -1, "A 应有邻居 B 和 C");
            assert(neighborsB.length == 1 && neighborsB[0] == "D", "B 应有邻居 D");
            assert(neighborsC.length == 1 && neighborsC[0] == "D", "C 应有邻居 D");
            assert(neighborsD.length == 0, "D 无邻居");
            
            // 输出拓扑排序结果
            var topo:Array = dag.topologicalSort();
            trace("拓扑排序结果: " + topo.join(", "));
        }, function(error:String):Void {
            trace("字典格式 DAG 加载失败，错误：" + error);
        });
    }
    
    // 测试 JSON 数据为数组格式时的 DAG 构建
    private function testArrayFormat():Void {
        trace("--- 测试数组格式 DAG ---");
        var filePath:String = "scripts/类定义/org/flashNight/gesh/json/LoadJson/TestDAG/test_dag_array.json";
        var loader:BaseDAGLoader = new BaseDAGLoader(filePath, "JSON");
        loader.load(function(dag:DAG):Void {
            trace("数组格式 DAG 加载成功！");
            var neighborsA:Array = dag.getNeighbors("A");
            var neighborsB:Array = dag.getNeighbors("B");
            var neighborsC:Array = dag.getNeighbors("C");
            var neighborsD:Array = dag.getNeighbors("D");
            
            // 验证结构应与字典格式一致
            assert(neighborsA.length == 2 && neighborsA.indexOf("B") != -1 && neighborsA.indexOf("C") != -1, "A 应有邻居 B 和 C");
            assert(neighborsB.length == 1 && neighborsB[0] == "D", "B 应有邻居 D");
            assert(neighborsC.length == 1 && neighborsC[0] == "D", "C 应有邻居 D");
            assert(neighborsD.length == 0, "D 无邻居");
            
            var topo:Array = dag.topologicalSort();
            trace("拓扑排序结果: " + topo.join(", "));
        }, function(error:String):Void {
            trace("数组格式 DAG 加载失败，错误：" + error);
        });
    }
    
    // 测试环路检测：加载包含环路边的 JSON 数据
    private function testCycleDetection():Void {
        trace("--- 测试环路检测 DAG ---");
        var filePath:String = "scripts/类定义/org/flashNight/gesh/json/LoadJson/TestDAG/test_dag_cycle.json";
        var loader:BaseDAGLoader = new BaseDAGLoader(filePath, "JSON");
        loader.load(function(dag:DAG):Void {
            trace("环路检测 DAG 加载成功！");
            // 假设 test_dag_cycle.json 的内容如下：
            // {
            //    "A": ["B"],
            //    "B": ["C"],
            //    "C": ["A", "D"],
            //    "D": []
            // }
            // 根据 DAG 的环路检测，边 C->A 应该被拒绝
            var neighborsA:Array = dag.getNeighbors("A");
            var neighborsB:Array = dag.getNeighbors("B");
            var neighborsC:Array = dag.getNeighbors("C");
            var neighborsD:Array = dag.getNeighbors("D");
            
            assert(neighborsA.length == 1 && neighborsA[0] == "B", "A 应有邻居 B");
            assert(neighborsB.length == 1 && neighborsB[0] == "C", "B 应有邻居 C");
            // 验证 C 的邻居中不包含 A，但包含 D
            assert(neighborsC.length == 1 && neighborsC[0] == "D", "C 应仅有邻居 D（环路边被拒绝）");
            assert(neighborsD.length == 0, "D 无邻居");
            
            var topo:Array = dag.topologicalSort();
            trace("拓扑排序结果: " + topo.join(", "));
        }, function(error:String):Void {
            trace("环路检测 DAG 加载失败，错误：" + error);
        });
    }
}
