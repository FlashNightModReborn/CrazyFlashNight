// BytecodeProbe.as — AVM1 字节码映射探针
// 用途：编译后用 JPEXS 反汇编，对比各写法生成的 action 序列
// 使用：在 Flash CS6 中新建空 FLA，帧1脚本 #include 此文件，发布后用 JPEXS 打开
// 设计原则：每个函数只含 1-2 条目标语句，消除干扰

// ============================================================
// 全局辅助（供探针引用）
// ============================================================
var _gVar:Number = 42;
var _gObj:Object = {x:42, y:0};
function _emptyFn():Void {}
function _identityFn(v:Number):Number { return v; }
_gObj.emptyMethod = function():Void {};
_gObj.retMethod = function():Number { return 42; };

// ============================================================
// 探针组 A：位运算家族（解决 bit_not 6.87x 异常）
// ============================================================

function probe_bit_and():Number {
    var a:Number = 255;
    var b:Number = 0;
    b = a & 0xFF;
    return b;
}

function probe_bit_or():Number {
    var a:Number = 128;
    var b:Number = 0;
    b = a | 1;
    return b;
}

function probe_bit_xor():Number {
    var a:Number = 255;
    var b:Number = 0;
    b = a ^ 1;
    return b;
}

function probe_bit_not():Number {
    var a:Number = 255;
    var b:Number = 0;
    b = ~a;
    return b;
}

function probe_bit_or_zero():Number {
    var a:Number = 3.7;
    var b:Number = 0;
    b = a | 0;
    return b;
}

function probe_double_tilde():Number {
    var a:Number = 3.7;
    var b:Number = 0;
    b = ~~a;
    return b;
}

function probe_lshift():Number {
    var a:Number = 1;
    var b:Number = 0;
    b = a << 2;
    return b;
}

function probe_rshift():Number {
    var a:Number = 1024;
    var b:Number = 0;
    b = a >> 2;
    return b;
}

// ============================================================
// 探针组 B：NaN 比较行为（解决 n!=n 语义争议）
// ============================================================

function probe_nan_eq():Void {
    var n:Number = NaN;
    trace("NaN == NaN: " + (NaN == NaN));
    trace("NaN != NaN: " + (NaN != NaN));
    trace("NaN === NaN: " + (NaN === NaN));
    trace("NaN !== NaN: " + (NaN !== NaN));
    trace("n == n: " + (n == n));
    trace("n != n: " + (n != n));
    trace("isNaN(n): " + isNaN(n));
}

// 字节码对比：n!=n vs isNaN(n)
function probe_isnan_selfne():Boolean {
    var n:Number = NaN;
    var b:Boolean = false;
    b = (n != n);
    return b;
}

function probe_isnan_fn():Boolean {
    var n:Number = NaN;
    var b:Boolean = false;
    b = isNaN(n);
    return b;
}

// ============================================================
// 探针组 C：一元加 vs Number()（确认编译器行为）
// ============================================================

function probe_unary_plus():Number {
    var s:String = "42";
    var b:Number = 0;
    b = +s;
    return b;
}

function probe_number_cast():Number {
    var s:String = "42";
    var b:Number = 0;
    b = Number(s);
    return b;
}

// ============================================================
// 探针组 D：常量折叠检测
// ============================================================

function probe_const_fold():Number {
    var b:Number = 0;
    b = 3 + 4;
    return b;
}

function probe_var_add():Number {
    var a:Number = 3;
    var c:Number = 4;
    var b:Number = 0;
    b = a + c;
    return b;
}

function probe_const_mul():Number {
    var b:Number = 0;
    b = 6 * 7;
    return b;
}

// ============================================================
// 探针组 E：函数调用路径（解决 call_empty > call_onearg）
// ============================================================

// 无返回值赋值的调用（是否多一条 ActionPop？）
function probe_call_void():Void {
    _emptyFn();
}

// 有返回值赋值的调用
function probe_call_assign():Number {
    var b:Number = 0;
    b = _identityFn(1);
    return b;
}

// 方法调用 vs 函数调用
function probe_call_method():Void {
    _gObj.emptyMethod();
}

function probe_call_method_ret():Number {
    var b:Number = 0;
    b = _gObj.retMethod();
    return b;
}

// .call 路径
function probe_fn_dot_call():Number {
    var b:Number = 0;
    b = _identityFn.call(null, 1);
    return b;
}

// ============================================================
// 探针组 F：变量访问路径（local vs global vs member）
// ============================================================

function probe_local_read():Number {
    var a:Number = 42;
    var b:Number = 0;
    b = a;
    return b;
}

function probe_global_read():Number {
    var b:Number = 0;
    b = _gVar;
    return b;
}

function probe_member_read():Number {
    var b:Number = 0;
    b = _gObj.x;
    return b;
}

function probe_bracket_read():Number {
    var b:Number = 0;
    b = _gObj["x"];
    return b;
}

function probe_root_read():Number {
    var b:Number = 0;
    b = _root._gVar;
    return b;
}

// ============================================================
// 探针组 G：typed vs untyped 变量
// ============================================================

function probe_typed_local():Number {
    var a:Number = 42;
    var b:Number = 0;
    b = a;
    return b;
}

function probe_untyped_local():Number {
    var a = 42;
    var b = 0;
    b = a;
    return b;
}

// ============================================================
// 探针组 H：String.length vs Array.length
// ============================================================

function probe_str_length():Number {
    var s:String = "hello";
    var b:Number = 0;
    b = s.length;
    return b;
}

function probe_arr_length():Number {
    var arr:Array = [1,2,3,4,5];
    var b:Number = 0;
    b = arr.length;
    return b;
}

// AS1 旧语法 length() 对比（如果编译器支持）
function probe_str_length_as1():Number {
    var s:String = "hello";
    var b:Number = 0;
    b = length(s);
    return b;
}

// ============================================================
// 探针组 I：Boolean 转换路径
// ============================================================

function probe_boolean_cast():Boolean {
    var n:Number = 1;
    var b:Boolean = false;
    b = Boolean(n);
    return b;
}

function probe_double_not():Boolean {
    var n:Number = 1;
    var b:Boolean = false;
    b = !!n;
    return b;
}

// ============================================================
// 探针组 J：typeof
// ============================================================

function probe_typeof():String {
    var x:Number = 42;
    var s:String = "";
    s = typeof(x);
    return s;
}

// ============================================================
// 探针组 K：Math 方法 vs 缓存引用
// ============================================================

function probe_math_floor():Number {
    var a:Number = 3.7;
    var b:Number = 0;
    b = Math.floor(a);
    return b;
}

function probe_cached_floor():Number {
    var mf:Function = Math.floor;
    var a:Number = 3.7;
    var b:Number = 0;
    b = mf(a);
    return b;
}

// ============================================================
// 探针组 L：switch vs if-else（跳表检测）
// ============================================================

function probe_switch_5(v:Number):Number {
    switch(v) {
        case 0: return 10;
        case 1: return 20;
        case 2: return 30;
        case 3: return 40;
        case 4: return 50;
    }
    return 0;
}

function probe_ifelse_5(v:Number):Number {
    if (v == 0) return 10;
    else if (v == 1) return 20;
    else if (v == 2) return 30;
    else if (v == 3) return 40;
    else if (v == 4) return 50;
    return 0;
}

// ============================================================
// 探针组 M：== vs === vs 跨类型
// ============================================================

function probe_eq_same_type():Boolean {
    var a:Number = 42;
    var b:Boolean = false;
    b = (a == 42);
    return b;
}

function probe_strict_eq_same():Boolean {
    var a:Number = 42;
    var b:Boolean = false;
    b = (a === 42);
    return b;
}

function probe_eq_cross_type():Boolean {
    var s:String = "42";
    var b:Boolean = false;
    b = (s == 42);
    return b;
}

function probe_strict_eq_cross():Boolean {
    var s:String = "42";
    var b:Boolean = false;
    b = (s === 42);
    return b;
}

// ============================================================
// 探针组 N：new 构造函数
// ============================================================

function _ProbeCtor0() {}
function _ProbeCtor1() { this.x = 1; }

function probe_new_empty():Object {
    var o:Object = new _ProbeCtor0();
    return o;
}

function probe_new_simple():Object {
    var o:Object = new _ProbeCtor1();
    return o;
}

// ============================================================
// 探针组 O：算术路径对比
// ============================================================

function probe_add_int():Number {
    var a:Number = 7;
    var b:Number = 0;
    b = a + 1;
    return b;
}

function probe_add_float():Number {
    var a:Number = 3.14;
    var b:Number = 0;
    b = a + 0.5;
    return b;
}

function probe_negate():Number {
    var a:Number = 7;
    var b:Number = 0;
    b = -a;
    return b;
}

function probe_incr_post():Number {
    var b:Number = 0;
    var c:Number = 0;
    c = b++;
    return c;
}

// ============================================================
// 探针组 P：闭包与 arguments
// ============================================================

function probe_closure_factory():Function {
    var captured:Number = 42;
    return function():Number { return captured; };
}

function probe_deep_closure_factory():Function {
    var outer:Number = 100;
    var inner:Function = function():Function {
        var mid:Number = outer + 1;
        return function():Number { return mid; };
    };
    return inner;
}

function probe_arguments_length():Number {
    return arguments.length;
}

function probe_arguments_read():Number {
    return Number(arguments[0]);
}

// ============================================================
// 探针组 Q：数组读取（局部 vs 全局容器）
// ============================================================

function probe_arr_local_read():Number {
    var arr:Array = [10,20,30,40,50];
    var idx:Number = 2;
    var b:Number = 0;
    b = arr[idx];
    return b;
}

function probe_arr_global_read():Number {
    var idx:Number = 50;
    var b:Number = 0;
    // _gArr100 是全局变量——JPEXS 中对比 GetRegister vs GetVariable
    b = _gArr100[idx];
    return b;
}

var _gArr100:Array = [];
var _pI:Number;
for (_pI = 0; _pI < 100; _pI++) _gArr100[_pI] = _pI;

// ============================================================
// 探针组 R：with / eval / try-catch
// ============================================================

function probe_with_block():Number {
    var b:Number = 0;
    with (_gObj) {
        b = x;
    }
    return b;
}

function probe_try_noexcept():Number {
    var a:Number = 1;
    var b:Number = 0;
    try { b = a; } catch(e) {}
    return b;
}

function probe_try_except():Number {
    var a:Number = 1;
    var b:Number = 0;
    var err:Object = {message:"x"};
    try { throw err; } catch(e) { b = a; }
    return b;
}

// ============================================================
// 探针组 S：delete / in / hasOwnProperty
// ============================================================

function probe_delete_prop():Void {
    var o:Object = {tmp:1};
    delete o.tmp;
}

function probe_hasown():Boolean {
    var o:Object = {x:1};
    return o.hasOwnProperty("x");
}

function probe_forin():Number {
    var o:Object = {a:1, b:2, c:3};
    var count:Number = 0;
    for (var k:String in o) {
        count++;
    }
    return count;
}

// ============================================================
// 探针组 T：Number/String/parseInt 转换
// ============================================================

function probe_parseint():Number {
    var s:String = "42";
    var b:Number = 0;
    b = parseInt(s);
    return b;
}

function probe_parsefloat():Number {
    var s:String = "3.14";
    var b:Number = 0;
    b = parseFloat(s);
    return b;
}

function probe_string_cast():String {
    var n:Number = 42;
    var s:String = "";
    s = String(n);
    return s;
}

function probe_string_concat_cast():String {
    var n:Number = 42;
    var s:String = "";
    s = "" + n;
    return s;
}

// ============================================================
// 探针组 U：call_empty 异常诊断（2.5x 谜团分解）
//
// v8 数据：call_empty=1174ns >> call_onearg=471ns
// 已知交织因素：
//   (1) 被调函数 DF1 vs DF2
//   (2) 调用者自身 DF1 vs DF2（空函数体→DF1, 有局部变量→DF2）
//   (3) void调用多 Pop vs 有返回值赋值无 Pop
//   (4) 参数个数 0 vs 1
//   (5) 函数体空 vs 有 return
//
// 设计：逐因素隔离
// ============================================================

// --- 被调函数矩阵 ---
// DF1: 0参数+空体（确认 DF1）
function _callU_empty_df1():Void {}
// 注意：仅声明参数但不使用，编译器仍选 DF1！
// 下面这个实际编译为 DF1（已由字节码确认）
function _callU_decl_only_df1(d:Number):Void {}
// 真正的 DF2：参数在函数体中被引用
function _callU_empty_df2(d:Number):Void { var _:Number = d; }
// DF1: 0参数+有 return（确认空体 vs return 的差异）
function _callU_ret_df1():Number { return 0; }
// DF2: 有参数+有 return（参数被使用）
function _callU_ret_df2(d:Number):Number { return d; }
// DF1: 0参数+空体+无 Void 签名（对比签名影响）
function _callU_void_nosig() {}

// --- 探针 U13: 验证「仅声明参数但不使用」确实是 DF1 ---
function probe_U13_decl_only():Void {
    _callU_decl_only_df1(0);
}

// --- 探针 U14: 调用真正的 DF2 空函数（参数被引用）---
function probe_U14_true_df2():Void {
    _callU_empty_df2(0);
}

// --- 探针 U15: DF2 空函数有返回赋值 ---
function probe_U15_true_df2_ret():Number {
    var b:Number = 0;
    _callU_empty_df2(0);
    b = 1;
    return b;
}

// --- 探针 U1: void调用（无返回值赋值），DF1 被调函数 ---
function probe_U1_void_df1():Void {
    _callU_empty_df1();
}

// --- 探针 U2: void调用，DF2 被调函数 ---
function probe_U2_void_df2():Void {
    _callU_empty_df2(0);
}

// --- 探针 U3: 有返回值赋值，DF1 被调函数 ---
function probe_U3_ret_df1():Number {
    var b:Number = 0;
    b = _callU_ret_df1();
    return b;
}

// --- 探针 U4: 有返回值赋值，DF2 被调函数 ---
function probe_U4_ret_df2():Number {
    var b:Number = 0;
    b = _callU_ret_df2(1);
    return b;
}

// --- 探针 U5: void调用 DF1，但调用者有局部变量（强制调用者 DF2） ---
function probe_U5_caller_df2_void_df1():Number {
    var b:Number = 0;
    _callU_empty_df1();
    return b;
}

// --- 探针 U6: 传1参数调用 DF2，void（无赋值） ---
function probe_U6_void_df2_1arg():Void {
    _callU_empty_df2(0);
}

// --- 探针 U7: 传1参数调用 DF2，有赋值 ---
function probe_U7_ret_df2_1arg():Number {
    var b:Number = 0;
    b = _callU_ret_df2(1);
    return b;
}

// --- 探针 U8: 调用无签名空函数 ---
function probe_U8_void_nosig():Void {
    _callU_void_nosig();
}

// --- 探针 U9: 0参数调用 DF2（传0参数给有参数的函数） ---
function probe_U9_df2_0args():Void {
    _callU_empty_df2();
}

// --- 探针 U10: 空函数 void调用，但显式 Pop 对比（连续调用 2 次 vs 1 次）---
function probe_U10_double_void():Void {
    _callU_empty_df1();
    _callU_empty_df1();
}

// --- 探针 U11: bench 中实际的模式复现 ---
// 模拟 call_empty bench 的实际展开：base 是 b=cst; test 是 _empty_fn(0);
function probe_U11_bench_base():Number {
    var b:Number = 0;
    var cst:Number = 0;
    b = cst;
    return b;
}

function probe_U11_bench_test():Number {
    var b:Number = 0;
    _callU_empty_df2(0);
    return b;
}

// --- 探针 U12: call_onearg bench 的实际模式复现 ---
function probe_U12_onearg_test():Number {
    var b:Number = 0;
    var a:Number = 42;
    b = _callU_ret_df2(a);
    return b;
}

// ============================================================
// 探针组 V：链式属性访问（chain_depth atomicOps 校准）
// 目的：确认 chain_depth2/3 的字节码条数，校准 atomicOps
// ============================================================

// 1层：o.x → 1次 GetMember
function probe_chain_depth1():Number {
    var b:Number = 0;
    b = _gObj.x;
    return b;
}

// 2层：o.inner.x → 预期 2次 GetMember
var _pChain2:Object = {inner:{x:10}};
function probe_chain_depth2():Number {
    var b:Number = 0;
    b = _pChain2.inner.x;
    return b;
}

// 3层：o.mid.inner.x → 预期 3次 GetMember
var _pChain3:Object = {mid:{inner:{x:20}}};
function probe_chain_depth3():Number {
    var b:Number = 0;
    b = _pChain3.mid.inner.x;
    return b;
}

// ============================================================
// 探针组 W：clamp 复合路径（atomicOps 校准）
// 目的：确认 Math.min(Math.max()) 的字节码条数
// ============================================================

// 单次 Math.max → GetVariable + GetMember + CallMethod
function probe_math_max_single():Number {
    var a:Number = 3;
    var lo:Number = 0;
    var b:Number = 0;
    b = Math.max(a, lo);
    return b;
}

// 复合 clamp → 两次 GetVariable + GetMember + CallMethod
function probe_clamp_mathminmax():Number {
    var a:Number = 7;
    var lo:Number = 0;
    var hi:Number = 10;
    var b:Number = 0;
    b = Math.min(Math.max(a, lo), hi);
    return b;
}

// 三元 clamp → 纯字节码比较+跳转，无 native 调用
function probe_clamp_ternary():Number {
    var a:Number = 7;
    var lo:Number = 0;
    var hi:Number = 10;
    var b:Number = 0;
    b = (a < lo ? lo : (a > hi ? hi : a));
    return b;
}

// ============================================================
// 探针组 X：native 桥接开销对照（C++ glue cost 隔离）
// 目的：对比不同 native API 的 CallMethod/CallFunction 路径
// 验证 C++ 桥接是通用常数还是逐 API 变化
// ============================================================

// String.fromCharCode → GetVariable("String") + GetMember("fromCharCode") + CallMethod
function probe_native_fromcharcode():String {
    var b:String = "";
    b = String.fromCharCode(65);
    return b;
}

// parseInt → GetVariable("parseInt") + CallFunction（全局函数，非对象方法）
// 注意：已有 probe_parseint，这里专门对照缓存版本
var _pParseInt:Function = parseInt;
function probe_native_parseint_cached():Number {
    var b:Number = 0;
    b = _pParseInt("42");
    return b;
}

// Key.isDown → GetVariable("Key") + GetMember("isDown") + CallMethod
// Flash 专有 native API，验证 Flash-specific dispatch 层
function probe_native_keyisdown():Boolean {
    var b:Boolean = false;
    b = Key.isDown(65);
    return b;
}

// Number() 全局函数 → CallFunction 路径
// 已有 probe_number_cast，这里对照缓存版本
var _pNumber:Function = Number;
function probe_native_number_cached():Number {
    var b:Number = 0;
    b = _pNumber("42");
    return b;
}

// isNaN() 全局函数 → CallFunction 路径
var _pIsNaN:Function = isNaN;
function probe_native_isnan_cached():Boolean {
    var b:Boolean = false;
    b = _pIsNaN(42);
    return b;
}

// ============================================================
// 探针组 Y：closure_deep2 语义验证
// 目的：确认 benchmark 中 closure_deep2 实际读的是哪一层
// ============================================================

// 直接读 outer（2层跳跃）vs 读 mid（1层跳跃）
function probe_closure_read_outer():Function {
    var outer:Number = 100;
    var inner:Function = function():Function {
        var mid:Number = 50;
        // 这个闭包跳过 mid，直接读 outer → 应有 2 层 GetVariable
        return function():Number { return outer; };
    };
    return inner;
}

function probe_closure_read_mid():Function {
    var outer:Number = 100;
    var inner:Function = function():Function {
        var mid:Number = 50;
        // 这个闭包只读 mid → 1 层 GetVariable
        return function():Number { return mid; };
    };
    return inner;
}

// 同时读 outer + mid（验证多变量捕获的字节码）
function probe_closure_read_both():Function {
    var outer:Number = 100;
    var inner:Function = function():Function {
        var mid:Number = 50;
        return function():Number { return outer + mid; };
    };
    return inner;
}

// ============================================================
// 探针组 Z：new 构造函数 DF1/DF2 对照（解决 new_empty > new_simple）
// 目的：精确对比 bench 中使用的 _EmptyCtor (DF1) vs _SimpleCtor (DF2)
// ============================================================

// 模拟 bench 中的 _EmptyCtor：0参数空体 → 必然 DF1
function _ProbeBenchEmptyCtor() {}

// 模拟 bench 中的 _SimpleCtor：this.x=1 → DF2（this 被引用）
function _ProbeBenchSimpleCtor() { this.x = 1; }

// 模拟修复后的 DF2 空构造：参数被引用 → 强制 DF2
function _ProbeBenchEmptyCtorDF2(d:Number) { var _:Number = d; }

function probe_new_bench_empty():Object {
    var o:Object = new _ProbeBenchEmptyCtor();
    return o;
}

function probe_new_bench_simple():Object {
    var o:Object = new _ProbeBenchSimpleCtor();
    return o;
}

function probe_new_bench_empty_df2():Object {
    var o:Object = new _ProbeBenchEmptyCtorDF2(0);
    return o;
}

// ============================================================
// 探针组 AA：fn_call_onearg base 异常诊断
// 目的：验证 .call() 的字节码路径，解释 fn_call_onearg base 偏高
// ============================================================

// 普通调用 _identity_fn(a) → base 路径
function probe_fn_direct_call():Number {
    var a:Number = 1;
    var b:Number = 0;
    b = _identityFn(a);
    return b;
}

// .call(null, a) 路径
function probe_fn_dot_call_v2():Number {
    var a:Number = 1;
    var b:Number = 0;
    b = _identityFn.call(null, a);
    return b;
}

// .apply(null, [a]) 路径
function probe_fn_dot_apply():Number {
    var a:Number = 1;
    var b:Number = 0;
    var args:Array = [1];
    b = _identityFn.apply(null, args);
    return b;
}

// ============================================================
// 探针组 AB：member_set 路径对比（resetEach 语义验证）
// 目的：确认 o.dyn=a (新属性) vs o.x=a (已有属性) 的字节码差异
// ============================================================

function probe_member_set_existing():Void {
    var o:Object = {x:1};
    o.x = 2;
}

function probe_member_set_new():Void {
    var o:Object = {};
    o.dyn = 1;
}

// 带 delete 后重新赋值（模拟 resetEach 重建后的路径）
function probe_member_set_after_reset():Void {
    var o:Object = {};
    o.dyn = 1;
    delete o.dyn;
    o.dyn = 2;
}

// ============================================================
// 运行入口（确保所有函数不被 DCE）
// ============================================================
trace("=== BytecodeProbe: 运行所有探针防止 DCE ===");
trace("A-and:" + probe_bit_and());
trace("A-or:" + probe_bit_or());
trace("A-xor:" + probe_bit_xor());
trace("A-not:" + probe_bit_not());
trace("A-or0:" + probe_bit_or_zero());
trace("A-dtil:" + probe_double_tilde());
trace("A-lsh:" + probe_lshift());
trace("A-rsh:" + probe_rshift());
probe_nan_eq();
trace("B-selfne:" + probe_isnan_selfne());
trace("B-isnan:" + probe_isnan_fn());
trace("C-uplus:" + probe_unary_plus());
trace("C-numcast:" + probe_number_cast());
trace("D-cfold:" + probe_const_fold());
trace("D-varadd:" + probe_var_add());
trace("D-cmul:" + probe_const_mul());
probe_call_void();
trace("E-cassign:" + probe_call_assign());
probe_call_method();
trace("E-cmret:" + probe_call_method_ret());
trace("E-fncall:" + probe_fn_dot_call());
trace("F-local:" + probe_local_read());
trace("F-global:" + probe_global_read());
trace("F-member:" + probe_member_read());
trace("F-bracket:" + probe_bracket_read());
trace("G-typed:" + probe_typed_local());
trace("G-untyped:" + probe_untyped_local());
trace("H-strlen:" + probe_str_length());
trace("H-arrlen:" + probe_arr_length());
trace("H-as1len:" + probe_str_length_as1());
trace("I-boolcast:" + probe_boolean_cast());
trace("I-dblnot:" + probe_double_not());
trace("J-typeof:" + probe_typeof());
trace("K-mfloor:" + probe_math_floor());
trace("K-cfloor:" + probe_cached_floor());
trace("L-sw5:" + probe_switch_5(3));
trace("L-if5:" + probe_ifelse_5(3));
trace("M-eq:" + probe_eq_same_type());
trace("M-seq:" + probe_strict_eq_same());
trace("M-eqx:" + probe_eq_cross_type());
trace("M-seqx:" + probe_strict_eq_cross());
trace("N-new0:" + probe_new_empty());
trace("N-new1:" + probe_new_simple());
trace("O-addi:" + probe_add_int());
trace("O-addf:" + probe_add_float());
trace("O-neg:" + probe_negate());
trace("O-post:" + probe_incr_post());
var _pClosure:Function = probe_closure_factory();
trace("P-closure:" + _pClosure());
trace("P-arglen:" + probe_arguments_length());
trace("P-argread:" + probe_arguments_read(99));
trace("Q-arrlocal:" + probe_arr_local_read());
trace("Q-arrglobal:" + probe_arr_global_read());
trace("R-with:" + probe_with_block());
trace("R-tryok:" + probe_try_noexcept());
trace("R-tryex:" + probe_try_except());
probe_delete_prop();
trace("S-hasown:" + probe_hasown());
trace("S-forin:" + probe_forin());
trace("T-pint:" + probe_parseint());
trace("T-pfloat:" + probe_parsefloat());
trace("T-strcast:" + probe_string_cast());
trace("T-strconcat:" + probe_string_concat_cast());
// --- 探针组 U 调用 ---
trace("=== 探针组 U: call_empty 异常诊断 ===");
probe_U1_void_df1();
probe_U2_void_df2();
trace("U3-ret_df1:" + probe_U3_ret_df1());
trace("U4-ret_df2:" + probe_U4_ret_df2());
trace("U5-caller_df2:" + probe_U5_caller_df2_void_df1());
probe_U6_void_df2_1arg();
trace("U7-ret_df2_1arg:" + probe_U7_ret_df2_1arg());
probe_U8_void_nosig();
probe_U9_df2_0args();
probe_U10_double_void();
trace("U11-base:" + probe_U11_bench_base());
trace("U11-test:" + probe_U11_bench_test());
trace("U12-onearg:" + probe_U12_onearg_test());
probe_U13_decl_only();
probe_U14_true_df2();
trace("U15-true_df2_ret:" + probe_U15_true_df2_ret());

// --- 探针组 V: 链式属性访问 ---
trace("=== 探针组 V: chain_depth ===");
trace("V-chain1:" + probe_chain_depth1());
trace("V-chain2:" + probe_chain_depth2());
trace("V-chain3:" + probe_chain_depth3());

// --- 探针组 W: clamp 复合路径 ---
trace("=== 探针组 W: clamp ===");
trace("W-maxsingle:" + probe_math_max_single());
trace("W-clampmath:" + probe_clamp_mathminmax());
trace("W-clamptern:" + probe_clamp_ternary());

// --- 探针组 X: native 桥接开销 ---
trace("=== 探针组 X: native bridge ===");
trace("X-fromchar:" + probe_native_fromcharcode());
trace("X-pint_c:" + probe_native_parseint_cached());
trace("X-keydown:" + probe_native_keyisdown());
trace("X-num_c:" + probe_native_number_cached());
trace("X-isnan_c:" + probe_native_isnan_cached());

// --- 探针组 Y: closure 层级 ---
trace("=== 探针组 Y: closure depth ===");
var _pClosureOuter:Function = probe_closure_read_outer();
var _pClosureOuterInner:Function = _pClosureOuter();
trace("Y-readouter:" + _pClosureOuterInner());
var _pClosureMid:Function = probe_closure_read_mid();
var _pClosureMidInner:Function = _pClosureMid();
trace("Y-readmid:" + _pClosureMidInner());
var _pClosureBoth:Function = probe_closure_read_both();
var _pClosureBothInner:Function = _pClosureBoth();
trace("Y-readboth:" + _pClosureBothInner());

// --- 探针组 Z: new 构造 DF1/DF2 ---
trace("=== 探针组 Z: new ctor DF1/DF2 ===");
trace("Z-benchempty:" + probe_new_bench_empty());
trace("Z-benchsimple:" + probe_new_bench_simple());
trace("Z-benchemptydf2:" + probe_new_bench_empty_df2());

// --- 探针组 AA: fn_call 路径 ---
trace("=== 探针组 AA: fn call paths ===");
trace("AA-direct:" + probe_fn_direct_call());
trace("AA-dotcall:" + probe_fn_dot_call_v2());
trace("AA-apply:" + probe_fn_dot_apply());

// --- 探针组 AB: member_set 路径 ---
trace("=== 探针组 AB: member_set ===");
probe_member_set_existing();
trace("AB-existing:done");
probe_member_set_new();
trace("AB-new:done");
probe_member_set_after_reset();
trace("AB-afterreset:done");

trace("=== BytecodeProbe 完成 ===");

