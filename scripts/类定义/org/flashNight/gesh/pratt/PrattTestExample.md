import org.flashNight.gesh.pratt.*;
PrattTestExample.runTests();


========== Pratt系统测试开始 ==========

--- 基础表达式测试 ---
2 + 3 * 4 = 14
(2 + 3) * 4 = 20
10 / 2 + 3 = 8
2 ** 3 = 8
5 > 3 = true
10 == 5 * 2 = true
'hello' != 'world' = true
true && false = false
true || false = true
!true = false
5 > 3 ? 'yes' : 'no' = yes
null ?? 'default' = default

--- 变量和函数测试 ---
x + y = 15
x * y = 50
Math.max(10, 20, 15) = 20
Math.sqrt(16) = 4
Math.floor(3.7) = 3
double(x) = 20
greet(name) = Hello, Player!

--- 复杂表达式测试 ---
player.level = 10
player.stats.attack = 100
player.items[0].damage = 20
player.stats.attack + player.level * 5 = 150
player.level >= 10 ? player.stats.attack * 1.5 : player.stats.attack = 150
game.player.stats.attack * game.config.multiplier = 150

--- Buff系统测试 ---
ADD_FLAT(20) = {type: ADD_FLAT, value: 20}
hasBerserk ? ADD_PERCENT_BASE(50) : ADD_FLAT(10) result type = ADD_PERCENT_BASE
level > 10 ? MUL_PERCENT(level * 2) : ADD_FLAT(level * 5) = {type: MUL_PERCENT, value: 30}
buffValue(100, mods) = 180

--- 错误处理测试 ---
未定义变量结果: -1
除零错误结果: ERROR
语法验证: 有效
空值访问结果: NULL_ACCESS

--- 性能测试 ---
简单表达式 (1000次): 503ms, 平均: 0.503ms
复杂表达式 (1000次): 2097ms, 平均: 2.097ms
不使用缓存: 1114ms
使用缓存: 56ms
性能提升: 95%
========== Pratt系统测试完成 ==========
