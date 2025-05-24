var tester:org.flashNight.naki.DataStructures.TestDAG = new org.flashNight.naki.DataStructures.TestDAG();

# ActionScript 2 DAG（有向无环图）模块使用手册


## 目录

1. [概述：什么是有向无环图（DAG）](#1-概述什么是有向无环图dag)
2. [项目结构与环境准备](#2-项目结构与环境准备)
3. [快速入门（10分钟上手）](#3-快速入门10分钟上手)
4. [DAG 核心功能详解](#4-dag-核心功能详解)
   - [4.1 创建 DAG 与添加边](#41-创建-dag-与添加边)
   - [4.2 拓扑排序（topologicalSort）](#42-拓扑排序topologicalsort)
   - [4.3 查找所有路径（findAllPaths）](#43-查找所有路径findallpaths)
   - [4.4 获取源节点（getSourceNodes）](#44-获取源节点getsourcenodes)
   - [4.5 移除边（removeEdge）](#45-移除边removeedge)
   - [4.6 toString 与图可视化](#46-tostring-与图可视化)
5. [JSON 数据加载与集成](#5-json-数据加载与集成)
   - [5.1 JSON 加载器 BaseDAGLoader](#51-json-加载器-basedagloader)
   - [5.2 支持的 JSON 格式](#52-支持的-json-格式)
   - [5.3 加载示例](#53-加载示例)
   - [5.4 常见加载错误与排查](#54-常见加载错误与排查)
6. [实战案例：技能树 / 任务系统](#6-实战案例技能树--任务系统)
   - [6.1 技能树场景](#61-技能树场景)
   - [6.2 任务依赖场景](#62-任务依赖场景)
7. [进阶：性能与扩展](#7-进阶性能与扩展)
   - [7.1 批量操作与大规模数据](#71-批量操作与大规模数据)
   - [7.2 自定义权重系统（WeightedDAG 示例）](#72-自定义权重系统weighteddag-示例)
8. [测试与常见问题](#8-测试与常见问题)

---

## 1. 概述：什么是有向无环图（DAG）

**DAG (Directed Acyclic Graph)** 是指 **有向无环** 的图结构。  
- **有向**：边（Edge）是有方向的，比如从节点 A 指向节点 B，不一定能从 B 指回 A。  
- **无环**：图中不存在从某个节点出发，沿着有向边又回到自身的情形。

**常见应用场景**：
- **任务依赖**：例如“完成任务 A 再执行任务 B”，DAG 很适合用来描述这样的依赖关系，保证没有“环”。
- **技能树或科技树**：高级技能依赖基础技能；若存在闭环，会导致学习顺序无法定义。
- **编译依赖**：编译器会对源文件进行排序，让不依赖其他文件的先行编译，等等。

在本项目中，我们使用 **ActionScript 2 (AS2)** 编写了一个轻量级的 DAG 模块，并且提供了 JSON 加载支持，让开发者可以在 Flash 环境下快速集成、管理和可视化依赖关系。

---

## 2. 项目结构与环境准备

在使用之前，请确认满足以下条件：

1. **ActionScript 2.0 项目结构**  
     项目根目录/
     └── org/
         └── flashNight/
             ├── naki/
             │   └── DataStructures/
             │       ├── AdjacencyListGraph.as
             │       └── DAG.as
             └── gesh/
                 └── json/
                     └── LoadJson/
                         └── BaseDAGLoader.as
     ```
   
2. **PathManager 环境**  
   - 项目中已包含一个 `PathManager` 类，用来自动判断资源加载路径（如 Steam 环境或本地环境）。  
   - 在项目启动时，务必先调用 `PathManager.initialize();` 并根据需要设置资源基础路径。  
   - 如果使用的不是 Steam 环境，请用 `PathManager.setBasePath("file:///D:/my_project/resources/");` 设定资源目录。

3. **编译与运行**    
   - 在代码中使用 `import org.flashNight.naki.DataStructures.DAG;` 等语句时，需要保证类文件路径正确。

---

## 3. 快速入门（10分钟上手）

以下示例展示了如何快速开始使用 DAG 模块。在 10 分钟内，您就可以在自己的 AS2 项目中管理一个有向无环图！

### 3.1 安装与引用
```actionscript
// （1）将以下类文件拷贝到相应目录：
//     org/flashNight/naki/DataStructures/AdjacencyListGraph.as
//     org/flashNight/naki/DataStructures/DAG.as
//     org/flashNight/gesh/json/LoadJson/BaseDAGLoader.as

// （2）在需要使用的代码文件中，添加 import
import org.flashNight.naki.DataStructures.DAG;
import org.flashNight.gesh.json.LoadJson.BaseDAGLoader; // 如果需要 JSON 加载功能
```

### 3.2 创建第一个DAG
```actionscript
// 示例：建立一个“技能树”或“科技树”式的依赖关系
var skillTree:DAG = new DAG();

// 添加节点与边：语义上等同于“基础剑术 -> 连击”表示连击依赖于基础剑术
skillTree.addEdge("基础剑术", "连击");
skillTree.addEdge("基础剑术", "格挡");
skillTree.addEdge("连击", "旋风斩");
skillTree.addEdge("格挡", "盾击");

// 打印图结构
trace(skillTree.toString());
/* 可能输出：
Edge from 基础剑术 to 连击
Edge from 基础剑术 to 格挡
Edge from 连击 to 旋风斩
Edge from 格挡 to 盾击
*/

// 获取推荐学习顺序（拓扑排序）
var learningOrder:Array = skillTree.topologicalSort();
trace("推荐学习顺序：" + learningOrder.join(" → "));
```

**预期输出**：  
```
推荐学习顺序：基础剑术 → 连击 → 格挡 → 旋风斩 → 盾击
```

看到这里，您已经成功在 AS2 环境中创建了一个简单的有向无环图，并获取了一个可行的学习/依赖顺序。后续可以将这个思路应用到“任务系统”、“配方解锁”、“剧情分支”等一切需要“前置条件”的场景！

---

## 4. DAG 核心功能详解

### 4.1 创建 DAG 与添加边

- **创建对象**  
  ```actionscript
  var dag:DAG = new DAG(); // 强制有向无环
  ```
  内部继承自 `AdjacencyListGraph`，同时会自动进行 **环检测**。如果发现尝试添加会造成环的边，会抛出 `Error`。

- **添加边**  
  ```actionscript
  try {
      dag.addEdge("A", "B");
  } catch (e:Error) {
      trace(e.message); // 如果检测到环，会抛出错误
  }
  ```
  - 若 `A` 或 `B` 不存在，会自动创建对应节点。
  - 若 `A -> B` 会导致环，则抛异常。

### 4.2 拓扑排序（topologicalSort）

拓扑排序可以用于找出 **“无环图中的线性序”**。例如：
- 技能学习顺序
- 任务执行顺序
- 编译次序

**用法**：
```actionscript
var order:Array = dag.topologicalSort();
if (order == null) {
    trace("图中存在环，无法拓扑排序");
} else {
    trace("拓扑排序结果：" + order.join(" -> "));
}
```
在本实现中，若图结构已保持无环，那么 `topologicalSort()` 返回的就是一个正确的 **全拓扑序**；若某些原因导致了环存在（理论上不会发生，因为 `DAG` 类在添加边时就拒绝了环），就会返回 `null`。

### 4.3 查找所有路径（findAllPaths）

`findAllPaths(u, v)` 用于寻找 **从节点 `u` 到节点 `v` 的所有可能路径**。举例：
```actionscript
var paths:Array = dag.findAllPaths("A", "E");
for (var i:Number = 0; i < paths.length; i++) {
    trace("路径 " + (i+1) + ": " + paths[i].join(" -> "));
}
```
如果需要在游戏中展示“从初级技能到终极技能的所有进阶路线”，可以通过 `findAllPaths` 一次性获取所有可行路线。

### 4.4 获取源节点（getSourceNodes）

**源节点**指 **没有任何其他节点指向它** 的节点，在本实现中也就是 **入度为 0** 的节点。  
```actionscript
var sources:Array = dag.getSourceNodes();
trace("源节点：" + sources.join(", "));
```
常见应用：
- 找出“新手即可学习的技能”
- 找出“没有任何前置任务”的任务

### 4.5 移除边（removeEdge）

如果后续发现某条依赖关系不需要，可以用 `removeEdge(u, v)`。  
```actionscript
var removed:Boolean = dag.removeEdge("A", "B");
if (removed) {
    trace("成功移除了 A->B");
} else {
    trace("未移除任何边");
}
```
**注意**：  
- 如果图是无向图（`AdjacencyListGraph` 不指定 `isDirected = true`），则会同时移除 `A->B` 与 `B->A`。  
- 在 `DAG` 中一般不允许出现无向逻辑，因此无需担心额外操作。  
- 若需要彻底删除节点，还需手动删除 `dag.adjacencyList["节点名"]`，并移除所有相关边。

### 4.6 toString 与图可视化

- `toString()` 返回类似：
  ```
  Edge from A to B
  Edge from A to C
  Edge from B to D
  ...
  ```
- 如果想要更灵活的可视化，可自己编写遍历函数，示例：
  ```actionscript
  function printDAG(dag:DAG):Void {
      for (var node:String in dag.adjacencyList) {
          var neighbors:Array = dag.getNeighbors(node);
          if (neighbors.length > 0) {
              trace(node + " -> " + neighbors.join(", "));
          } else {
              trace(node + " -> (无邻居)");
          }
      }
  }
  ```

---

## 5. JSON 数据加载与集成

### 5.1 JSON 加载器 BaseDAGLoader

为方便在 **AS2** 中读取并解析 JSON，我们提供了 `BaseDAGLoader` 类以及内部用到的 `JSONLoader`。  
`BaseDAGLoader` 可以帮助您：

1. 从指定文件路径加载 JSON 文件。
2. 自动解析（支持三种解析方式 `JSON`, `LiteJSON`, `FastJSON`；一般用 `JSON` 即可）。
3. 将数据转换为一个新的 `DAG` 对象。

**用法概览**：
```actionscript
import org.flashNight.gesh.json.LoadJson.BaseDAGLoader;
import org.flashNight.naki.DataStructures.DAG;

var loader:BaseDAGLoader = new BaseDAGLoader("data/graph_data.json", "JSON");
loader.load(
    function(dag:DAG):Void { trace("加载成功！"); },
    function(errorMsg:String):Void { trace("加载失败：" + errorMsg); }
);
```

### 5.2 支持的 JSON 格式

`BaseDAGLoader` 支持两种结构：

1. **字典（对象）格式**  
   ```json
   {
       "A": ["B", "C"],
       "B": ["D"],
       "C": ["D"],
       "D": []
   }
   ```
   - Key 代表节点名称，Value 是一个数组，表示该节点的所有 **直接后继** 节点（即有一条边 `Key -> Value[i]`）。
   - 适合简单场景，无需在节点上附加其他属性。

2. **数组格式**  
   ```json
   [
       { "id": "A", "edges": ["B", "C"] },
       { "id": "B", "edges": ["D"] },
       { "id": "C", "edges": ["D"] },
       { "id": "D", "edges": [] }
   ]
   ```
   - 每个元素都必须至少包含 `id` 和 `edges` 字段。
   - 可以额外添加其他属性（如 `desc`, `type`, `cost` 等）而不会出错，解析时只关心 `id` 和 `edges` 两个字段来构造图。

### 5.3 加载示例

假设有一个文件 `skill_tree.json`：

```json
{
    "基础法术": ["火球术", "冰箭术"],
    "火球术": ["爆裂火焰"],
    "冰箭术": ["寒冰护体"],
    "寒冰护体": ["绝对零度"]
}
```

**AS2 代码**：
```actionscript
import org.flashNight.gesh.json.LoadJson.BaseDAGLoader;
import org.flashNight.naki.DataStructures.DAG;

// 假设资源目录为 "file:///D:/my_project/resources/"
PathManager.initialize();
PathManager.setBasePath("file:///D:/my_project/resources/");

var loader:BaseDAGLoader = new BaseDAGLoader("data/skill_tree.json", "JSON");
loader.load(
    function(dag:DAG):Void {
        trace("技能树加载成功！");
        
        // 获取所有源节点（可直接学习的技能）
        var sources:Array = dag.getSourceNodes();
        trace("可直接学习的技能: " + sources.join(", "));
        
        // 查找从 '基础法术' 到 '绝对零度' 的所有路径
        var paths:Array = dag.findAllPaths("基础法术", "绝对零度");
        for (var i:Number = 0; i < paths.length; i++) {
            trace("路线 " + (i+1) + ": " + paths[i].join(" -> "));
        }
    },
    function(error:String):Void {
        trace("技能树加载失败: " + error);
    }
);
```

### 5.4 常见加载错误与排查

| 错误现象                     | 可能原因                     | 解决方案                                   |
|------------------------------|------------------------------|--------------------------------------------|
| JSONLoader Error: File not found | 文件路径错误                 | 检查 `BaseDAGLoader` 的相对路径是否正确；或使用 `PathManager.resolvePath()` 查看最终解析 |
| 添加边 (X->Y) 会导致环       | 数据中存在闭环，比如 Y->...->X | 是预期行为（DAG 类会拒绝形成环的边），请修改数据结构，避免环。 |
| 最终加载后 DAG 为空          | JSON 文件结构不符合字典或数组格式 | 确认 JSON 里是否是 `{key: [list], ...}` 或 `[ {id, edges} ]` 格式。            |

---

## 6. 实战案例：技能树 / 任务系统

### 6.1 技能树场景

- **JSON 文件**（字典格式示例）：
  ```json
  {
      "基础剑术": ["连击", "格挡"],
      "连击": ["旋风斩"],
      "格挡": ["盾击"],
      "旋风斩": [],
      "盾击": []
  }
  ```
- **加载后**：
  ```actionscript
  var order:Array = skillTree.topologicalSort();
  trace("技能学习顺序：" + order.join(" -> "));
  // 输出示例：基础剑术 -> 连击 -> 格挡 -> 旋风斩 -> 盾击
  ```

### 6.2 任务依赖场景

- **JSON 文件**（字典格式示例）：
  ```json
  {
      "寻找线索": ["调查现场"],
      "调查现场": ["击败守卫", "收集证据"],
      "击败守卫": ["回报镇长"],
      "收集证据": ["回报镇长"],
      "回报镇长": []
  }
  ```
- **逻辑**：必须先寻找线索，才能调查现场；调查现场后，如果要回报镇长，需要完成击败守卫、收集证据。

**可拓展示例：检查某一任务是否可开始**：
```actionscript
function canStartTask(dag:DAG, taskName:String, completedTasks:Array):Boolean {
    // completedTasks 储存已经完成的任务
    // 只要有任务指向当前 taskName，就属于该任务的前置任务
    for (var node:String in dag.adjacencyList) {
        var neighbors:Array = dag.getNeighbors(node);
        if (neighbors.indexOf(taskName) != -1) {
            // 如果 completedTasks 中不包含 node，则无法开始
            if (completedTasks.indexOf(node) == -1) {
                return false;
            }
        }
    }
    return true;
}
```

---

## 7. 进阶：性能与扩展

### 7.1 批量操作与大规模数据

- **减少多次哈希查询**：  
  如果要为很多节点添加边，先用 `addVertex(...)` 批量创建节点，再循环添加边，可以减少内部数组操作与哈希查询的消耗。

- **移除大规模节点**：  
  如果要移除整个子图，可先用 `removeEdge` 逐条移除相关边，然后统一 `delete` 掉节点在 `adjacencyList` 中的属性，以免内存泄漏。

### 7.2 自定义权重系统（WeightedDAG 示例）

如果需要在边上存储权重，例如技能升级所需金币等，参考以下做法：
```actionscript
class WeightedDAG extends DAG {
    private var edgeWeights:Object;

    public function WeightedDAG() {
        super();
        edgeWeights = {};
    }

    public function addWeightedEdge(u:String, v:String, weight:Number):Void {
        super.addEdge(u, v);
        var key:String = u + "->" + v;
        edgeWeights[key] = weight;
    }

    public function getPathWeight(path:Array):Number {
        var total:Number = 0;
        for (var i:Number = 0; i < path.length - 1; i++) {
            var key:String = path[i] + "->" + path[i + 1];
            total += edgeWeights[key];
        }
        return total;
    }
}
```
这样就可以对每个路径做加权运算，例如最短路径或最大收益路径（当然，这已经延伸到带权 DAG 的更多算法范畴了）。


## 8. 测试与常见问题

1. **如何进行单元测试？**  
   - 项目内提供了 `TestDAG.as`，包含多种单元测试场景：  
     - 自环检测  
     - 重复边添加  
     - 拓扑排序结果验证  
     - 路径查找  
   - 您可以自行添加更多测试，或根据项目需求修改测试用例。

2. **为什么拓扑排序返回 `null`？**  
   - 说明图中出现了环；但在 `DAG` 类中，理论上不会出现环（因为会拒绝添加导致环的边）。若强行通过底层方法修改 `adjacencyList`，就会引发这个问题。

3. **getSourceNodes() 返回空？**  
   - 如果每个节点都有入边，意味着没有任何节点可以“独立存在”，往往暗示图中存在一个环或全部节点相互连接成环形。请检查数据正确性。

4. **JSON 加载报错 “添加边 X->Y 会导致环”**  
   - 说明输入数据本身包含了从 Y 到 X 的路径，所以再加 X->Y 就会产生闭环。请修改 JSON 数据，排除这种情况。

---
