var dp:org.flashNight.naki.DP.DynamicProgramming = new org.flashNight.naki.DP.DynamicProgramming();

// 定义状态转移方程
dp.initialize({ maxState: 100 }, function(state, cache) {
    var n:Number = parseInt(state);
    if (n <= 1) {
        return n; // 基础状态
    }
    return (cache[(n - 1).toString()] || dp.solve((n - 1).toString())) +
           (cache[(n - 2).toString()] || dp.solve((n - 2).toString()));
});

// 计算 Fibonacci(10)
trace(dp.solve("10")); // 输出 55
