/**
 * BulletFactoryDebugger.as
 * 位于 org.flashNight.arki.bullet.BulletComponent.Factory 包下
 *
 * 调试用方法
 */

class org.flashNight.arki.bullet.Factory.BulletFactoryDebugger {
    /**
     * 更新子弹统计信息
     * @param gameWorld 游戏世界对象
     * @param Obj 子弹配置对象
     * @param shooter 发射者
     */
    public static function updateBulletStats(游戏世界, Obj, shooter) {
        var report_len = 16;

        // 初始化统计信息（如果没有）
        if (!游戏世界.bulletStats) {
            游戏世界.bulletStats = {
                shooters: {},
                bulletTypes: {},
                totalShots: 0,
                timeStats: {},
                unitShots: {},
                lastSecondStats: {
                    shooters: {},
                    bulletTypes: {},
                    totalShots: 0
                }
            };
        }

        // 增加单位发射数量
        if (!游戏世界.bulletStats.shooters[shooter]) {
            游戏世界.bulletStats.shooters[shooter] = {
                shotCount: 0,
                bulletTypes: {}
            };
        }
        游戏世界.bulletStats.shooters[shooter].shotCount++;

        // 增加子弹类型发射数量
        if (!游戏世界.bulletStats.bulletTypes[Obj.子弹种类]) {
            游戏世界.bulletStats.bulletTypes[Obj.子弹种类] = {
                shotCount: 0,
                shooters: {}
            };
        }
        游戏世界.bulletStats.bulletTypes[Obj.子弹种类].shotCount++;

        // 增加全局子弹统计
        游戏世界.bulletStats.totalShots++;

        // 时间统计：跟踪每一帧创建的子弹数量
        var currentFrame = _root.帧计时器.当前帧数;
        var currentSecond = Math.floor(currentFrame / 30);
        if (!游戏世界.bulletStats.timeStats[currentSecond]) {
            游戏世界.bulletStats.timeStats[currentSecond] = {
                totalShots: 0,
                shooters: {}
            };
        }
        游戏世界.bulletStats.timeStats[currentSecond].totalShots++;
        if (!游戏世界.bulletStats.timeStats[currentSecond].shooters[shooter]) {
            游戏世界.bulletStats.timeStats[currentSecond].shooters[shooter] = 0;
        }
        游戏世界.bulletStats.timeStats[currentSecond].shooters[shooter]++;

        // 增加每个单位的子弹创建数量
        if (!游戏世界.bulletStats.unitShots[shooter]) {
            游戏世界.bulletStats.unitShots[shooter] = {
                shotCount: 0,
                bulletTypes: {}
            };
        }
        游戏世界.bulletStats.unitShots[shooter].shotCount++;
        if (!游戏世界.bulletStats.unitShots[shooter].bulletTypes[Obj.子弹种类]) {
            游戏世界.bulletStats.unitShots[shooter].bulletTypes[Obj.子弹种类] = 0;
        }
        游戏世界.bulletStats.unitShots[shooter].bulletTypes[Obj.子弹种类]++;

        // 每秒汇总一次统计信息
        if (currentFrame % 30 == 0) {
            var report = "子弹创建与发射频率分析报告：\n";

            // 发射者排行（按发射数量）
            var sortedShooters = [];
            for (var shooterName in 游戏世界.bulletStats.shooters) {
                sortedShooters.push({ name: shooterName, count: 游戏世界.bulletStats.shooters[shooterName].shotCount });
            }
            sortedShooters.sort(function(a, b) { return b.count - a.count; });

            report += "发射者排行（按发射数量）：\n";
            for (var i = 0; i < Math.min(report_len, sortedShooters.length); i++) {
                var shooterSummary = sortedShooters[i];
                report += shooterSummary.name + ": " + shooterSummary.count + " 发射\n";

                // 每个发射者发射的子弹类型统计
                for (var bulletType in 游戏世界.bulletStats.shooters[shooterSummary.name].bulletTypes) {
                    report += "  -> " + bulletType + ": " + 游戏世界.bulletStats.shooters[shooterSummary.name].bulletTypes[bulletType] + " 发射\n";
                }
            }

            // 子弹类型排行（按发射数量）
            var sortedBulletTypes = [];
            for (var bulletType in 游戏世界.bulletStats.bulletTypes) {
                sortedBulletTypes.push({ name: bulletType, count: 游戏世界.bulletStats.bulletTypes[bulletType].shotCount });
            }
            sortedBulletTypes.sort(function(a, b) { return b.count - a.count; });

            report += "子弹类型排行（按发射数量）：\n";
            for (var i = 0; i < Math.min(report_len, sortedBulletTypes.length); i++) {
                var bulletTypeSummary = sortedBulletTypes[i];
                report += bulletTypeSummary.name + ": " + bulletTypeSummary.count + " 发射\n";
            }

            // 最多创建子弹的单位（按创建子弹数量）
            var sortedUnitShots = [];
            for (var unitName in 游戏世界.bulletStats.unitShots) {
                sortedUnitShots.push({ name: unitName, count: 游戏世界.bulletStats.unitShots[unitName].shotCount });
            }
            sortedUnitShots.sort(function(a, b) { return b.count - a.count; });

            report += "最多创建子弹的单位排行：\n";
            for (var i = 0; i < Math.min(report_len, sortedUnitShots.length); i++) {
                var unitSummary = sortedUnitShots[i];
                report += unitSummary.name + ": " + unitSummary.count + " 次创建\n";

                // 每个单位创建的子弹类型统计
                for (var bulletType in 游戏世界.bulletStats.unitShots[unitSummary.name].bulletTypes) {
                    report += "  -> " + bulletType + ": " + 游戏世界.bulletStats.unitShots[unitSummary.name].bulletTypes[bulletType] + " 次创建\n";
                }
            }

            // 每秒子弹创建频率分析
            report += "\n每秒子弹创建频率分析：\n";
            var sortedTimeStats = [];
            for (var second in 游戏世界.bulletStats.timeStats) {
                var timeData = 游戏世界.bulletStats.timeStats[second];
                sortedTimeStats.push({ second: second, shotCount: timeData.totalShots });
            }
            sortedTimeStats.sort(function(a, b) { return b.shotCount - a.shotCount; });

            for (var i = 0; i < Math.min(report_len, sortedTimeStats.length); i++) {
                var timeSummary = sortedTimeStats[i];
                report += "第 " + timeSummary.second + " 秒: " + timeSummary.shotCount + " 子弹创建\n";

                // 每秒区间内的发射者发射情况
                for (var shooterName in 游戏世界.bulletStats.timeStats[timeSummary.second].shooters) {
                    report += "  发射者 " + shooterName + ": " + 游戏世界.bulletStats.timeStats[timeSummary.second].shooters[shooterName] + " 发射\n";
                }
            }

            // 总子弹数量（全局）
            report += "总子弹数量（全局）: " + 游戏世界.bulletStats.totalShots + "\n";

            // 发送汇总后的统计信息
            _root.服务器.发布服务器消息(report);
        }
    };

}