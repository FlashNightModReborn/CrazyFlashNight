// config.as

// 单例构造，确保只加载一次
if (!_global.__CONFIG_INCLUDED__) {
    _global.__CONFIG_INCLUDED__ = true;

    // 利用全局命名空间（_global）构造 Config 对象，充当全局寄存器
    _global.Config = {
        // 寄存器 (registers) 是一个动态对象，用于跨函数或宏之间传递数据
        // 不使用函数返回值的原因是 AS2 中函数调用开销较大，
        // 而通过对象存储数据可以避免函数开销，提高性能。
        registers: {},

        // 参数数组 (arguments) 用于存储传递给宏的临时参数
        // 使用数组的优点是能够灵活地支持多个参数传递，避免为每个参数创建单独的变量。
        // 注意：在使用完毕后，需要通过设置 `arguments.length = 0` 清空，防止数据残留。
        arguments: []
    };
}

/*

// 示例宏：macroAdd.as

// 定义一个宏，用于计算两个参数的和，并将结果存储到 Config.marcoAdd 中
// 这里采用宏而非函数的方式，目的是通过 #include 将代码直接嵌入调用处，避免函数调用的额外开销。
var marcoAdd = Config.arguments[0] + Config.arguments[1];

// 清空参数数组，防止下次调用时残留旧数据
Config.arguments.length = 0;

// 设计思想补充说明：
// 1. 使用 Config 对象跨模块共享数据，不仅减少函数调用，还避免局部变量作用域受限的问题。
// 2. arguments 作为类数组结构，支持动态参数数量，为不同类型的宏提供灵活性。
// 3. registers 用于存储持久化数据，可跨宏调用。通过动态键名支持无限扩展寄存器数量。
*/
