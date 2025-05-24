import org.flashNight.arki.spatial.move.*;

/**
 * MoveFactoryDebugger.as
 * 位于 org.flashNight.arki.spatial.move 包下
 *
 * 移动系统调试分析工具，提供移动统计与碰撞分析功能
 */

class org.flashNight.arki.spatial.move.MoveFactoryDebugger {
  // 统计信息存储结构
  private static var moveStats:Object;
  
  // 是否启用调试模式（可通过外部配置修改）
  public static var DEBUG_ENABLED:Boolean = false;

  // 初始化统计系统
  public static function init():Void {
    moveStats = {
      entities: {},      // 各实体移动统计
      directions: {},   // 方向使用统计
      moveTypes: {      // 移动类型统计
        "2D": 0,
        "2.5D": 0
      },
      collisions: {      // 碰撞相关统计
        total: 0,
        resolved: 0,
        byDirection: {}
      },
      speedStats: {      // 速度分析
        total: 0,
        max: 0,
        avg: 0
      }
    };
  }

  /**
   * 记录移动事件
   * @param entity   移动的实体
   * @param dir      移动方向
   * @param speed    移动速度
   * @param moveType 移动类型（"2D"/"2.5D"）
   * @param collided 是否发生碰撞
   * @param resolved 是否成功挤出
   */
  public static function recordMove(
    entity:MovieClip, 
    dir:String, 
    speed:Number,
    moveType:String, 
    collided:Boolean, 
    resolved:Boolean
  ):Void {
    if (!DEBUG_ENABLED) return;

    // 实体统计
    var entityId:String = getEntityIdentifier(entity);
    if (!moveStats.entities[entityId]) {
      moveStats.entities[entityId] = {
        moveCount: 0,
        collidedCount: 0,
        lastSpeed: 0,
        directions: {},
        moveTypes: { "2D":0, "2.5D":0 }
      };
    }
    var entityStat = moveStats.entities[entityId];
    entityStat.moveCount++;
    entityStat.lastSpeed = speed;
    entityStat.directions[dir] = (entityStat.directions[dir] || 0) + 1;
    entityStat.moveTypes[moveType]++;

    // 方向统计
    if (!moveStats.directions[dir]) {
      moveStats.directions[dir] = {
        count: 0,
        collisionRate: 0,
        avgSpeed: 0
      };
    }
    var dirStat = moveStats.directions[dir];
    dirStat.count++;
    dirStat.avgSpeed = (dirStat.avgSpeed * (dirStat.count-1) + speed) / dirStat.count;

    // 移动类型统计
    moveStats.moveTypes[moveType]++;

    // 速度统计
    moveStats.speedStats.total += speed;
    moveStats.speedStats.max = Math.max(moveStats.speedStats.max, speed);
    moveStats.speedStats.avg = moveStats.speedStats.total / (++moveStats.speedStats.count || 1);

    // 碰撞统计
    if (collided) {
      moveStats.collisions.total++;
      entityStat.collidedCount++;
      
      // 按方向统计碰撞
      moveStats.collisions.byDirection[dir] = (moveStats.collisions.byDirection[dir] || 0) + 1;
      
      // 碰撞解决统计
      if (resolved) moveStats.collisions.resolved++;
    }
  }

  /**
   * 生成移动分析报告 
   * @param maxEntries 各分类最大显示条目数
   */
  public static function generateReport(maxEntries:Number = 10):String {
    var report:String = "===== 移动系统分析报告 =====\n";

    // 活跃实体排行
    report += "[最活跃实体]\n";
    var sortedEntities = [];
    for (var e in moveStats.entities) {
      sortedEntities.push({ id:e, data:moveStats.entities[e] });
    }
    sortedEntities.sort(function(a,b) { return b.data.moveCount - a.data.moveCount; });
    for (var i=0; i<Math.min(maxEntries, sortedEntities.length); i++) {
      var e = sortedEntities[i];
      report += StringUtil.substitute(
        "{0}: 移动{1}次 碰撞{2}次 平均速度{3}\n",
        e.id, e.data.moveCount, e.data.collidedCount, e.data.lastSpeed
      );
      
    }

    // 方向热度分析
    report += "\n[方向使用率]\n";
    var sortedDirs = [];
    for (var d in moveStats.directions) {
      sortedDirs.push({ dir:d, data:moveStats.directions[d] });
    }
    sortedDirs.sort(function(a,b) { return b.data.count - a.data.count; });
    for (var i=0; i<Math.min(maxEntries, sortedDirs.length); i++) {
      var d = sortedDirs[i];
      report += StringUtil.substitute(
        "{0}: {1}次 平均速度{2} 碰撞率{3}%\n", 
        d.dir, d.data.count, d.data.avgSpeed,
        ((moveStats.collisions.byDirection[d.dir]||0)/d.data.count*100)
      );
    }

    // 碰撞分析
    report += "\n[碰撞统计]\n";
    report += StringUtil.substitute(
      "总碰撞: {0}次 解决率: {1}%\n",
      moveStats.collisions.total, 
      (moveStats.collisions.resolved / moveStats.collisions.total * 100)
    );

    // 移动类型分布
    report += "\n[移动类型]\n";
    report += "2D移动: " + moveStats.moveTypes["2D"] + "次\n";
    report += "2.5D移动: " + moveStats.moveTypes["2.5D"] + "次\n";

    // 速度分析
    report += "\n[速度分析]\n";
    report += StringUtil.substitute(
      "最高速度: {0} 平均速度: {1}\n",
      moveStats.speedStats.max,
      moveStats.speedStats.avg
    );

    return report;
  }

  // 获取实体唯一标识
  private static function getEntityIdentifier(entity:MovieClip):String {
    return entity._name;
  }
}
