/**
 * bench_gen_v7.js — AVM1/AS2 性能基准测试生成器 v7
 *
 * v7 修复清单（基于 v6 实测数据）：
 * 1. _quality→_qualityTag：AS2 内置 _quality 属性遮蔽自定义函数（v3以来的bug）
 * 2. blackhole NaN 感染：nan_add/number_cast_undef 的 finalize 不再写入 NaN 到 _blackhole
 * 3. local_copy delta=0 → rel 除零：refNs fallback 改为使用 add_int 作为后备基准
 * 4. bit_not 128.5ns 异常高 → 新增 bit_not_assign (b=~b) 对照；确认 base 对称
 * 5. floor_doubletilde 276ns → 实际是两次按位非，AVM1 可能每次都做 Number→Int32→Number 转换
 *    → 保留作为"反模式"标注，新增 floor_int_cast 用 int() 做对照
 * 6. base 函数 60ms vs 47ms 不一致 → 统一所有 base 为 b=a 模式（确保 base 都读局部变量）
 *    部分 base 使用 b=0/b=false 常量赋值，改为读局部变量确保公平
 * 7. GC_OUTER 200→400（GC_TOTAL 10K→20K）提高 GC 测试信噪比
 * 8. arr_concat base 含 [6,7] 字面量创建 → base 改为等效的数组字面量赋值消耗
 * 9. 新增重要对照组：
 *    - 有类型 vs 无类型局部变量 (typed vs untyped)
 *    - local_copy 参照物修正：base=test=相同语句，测纯循环+赋值基线
 *    - 常量折叠检测：b=3+4 vs b=a+c (编译器是否折叠常量)
 *    - 空 while 循环（不含任何赋值，纯 overhead）
 *    - Array.length 设置 (arr.length=0 清空 vs delete)
 *    - 函数调用有返回值 vs 无返回值
 * 10. 输出改进：每条结果带 sampleCount + allDeltas 方便后处理
 */

const fs = require('fs');
const path = require('path');

const OUT_DIR = path.join(__dirname);
if (!fs.existsSync(OUT_DIR)) fs.mkdirSync(OUT_DIR, { recursive: true });

const CFG = {
  STD_UNROLL: 100,
  STD_OUTER: 20000,       // 100*20000=2M ops
  GC_UNROLL: 50,
  GC_OUTER: 400,          // v7: 50*400=20K ops (v6=10K 信噪比不足)
  STRUCT_UNROLL: 10,
  STRUCT_OUTER: 40000,    // 10*40000=400K ops
  FORIN_UNROLL: 5,
  FORIN_OUTER: 4000,
  REPEATS: 9,
  WARMUP: 3
};
CFG.STD_TOTAL = CFG.STD_UNROLL * CFG.STD_OUTER;
CFG.GC_TOTAL = CFG.GC_UNROLL * CFG.GC_OUTER;
CFG.STRUCT_TOTAL = CFG.STRUCT_UNROLL * CFG.STRUCT_OUTER;
CFG.FORIN_TOTAL = CFG.FORIN_UNROLL * CFG.FORIN_OUTER;

function indent(lines, prefix) {
  if (!lines || !lines.length) return '';
  return lines.map(l => prefix + l).join('\n') + '\n';
}

function makePairFns(spec) {
  const kind = spec.kind || 'std';
  let cfg;
  if (kind === 'gc')          cfg = { unroll: CFG.GC_UNROLL, outer: CFG.GC_OUTER };
  else if (kind === 'struct') cfg = { unroll: CFG.STRUCT_UNROLL, outer: CFG.STRUCT_OUTER };
  else                        cfg = { unroll: CFG.STD_UNROLL, outer: CFG.STD_OUTER };

  const init = indent(spec.init || [], '    ');
  const finalize = spec.finalize ? '    ' + spec.finalize + '\n' : '';
  const resetBase = indent(spec.resetEach || [], '        ');
  const resetTest = indent(spec.resetEach || [], '        ');

  function makeBody(line) {
    return Array(cfg.unroll).fill('        ' + line).join('\n');
  }

  function emit(prefix, body, reset) {
    const parts = [
      'function ' + prefix + '_' + spec.name + '():Number {',
      '    var t0:Number = getTimer();',
      '    var i:Number = ' + cfg.outer + ';',
      init.trimEnd(),
      '    while (i--) {'
    ];
    if (reset && reset.trim()) parts.push(reset.trimEnd());
    parts.push(body);
    parts.push('    }');
    if (finalize.trim()) parts.push(finalize.trimEnd());
    parts.push('    return getTimer() - t0;');
    parts.push('}');
    return parts.filter(Boolean).join('\n');
  }

  return emit('base', makeBody(spec.base), resetBase) + '\n\n' +
         emit('test', makeBody(spec.test), resetTest);
}

// ======================================================================
// BENCHMARK DEFINITIONS
// ======================================================================
// v7 设计原则：
// - base 尽量用 "b=a;" (局部变量读→局部变量写) 作为统一基线
//   这样 delta = test - base 测量的是 test 相比"纯赋值"的增量开销
// - 涉及 Boolean 结果的，base 用 "b=cst;" (cst 是 Boolean 局部常量)
// - finalize 必须消耗所有可能被优化掉的变量

const benches = [
  // ===================== ARITH =====================
  // 自我参照基线：base 和 test 完全相同，delta 理论为 0
  { cat:'arith', name:'noop_baseline', desc:'b=a 自参照基线',
    init:['var a:Number=1;','var b:Number=0;'],
    base:'b=a;', test:'b=a;', finalize:'_bh += b;', atomicOps:1 },

  { cat:'arith', name:'add_int', desc:'b=a+1 (int)',
    init:['var a:Number=7;','var b:Number=0;'],
    base:'b=a;', test:'b=a+1;', finalize:'_bh += b;', atomicOps:1 },

  { cat:'arith', name:'add_float', desc:'b=a+0.5 (float)',
    init:['var a:Number=3.14;','var b:Number=0;'],
    base:'b=a;', test:'b=a+0.5;', finalize:'_bh += b;', atomicOps:1 },

  { cat:'arith', name:'sub_int', desc:'b=a-1',
    init:['var a:Number=7;','var b:Number=0;'],
    base:'b=a;', test:'b=a-1;', finalize:'_bh += b;', atomicOps:1 },

  { cat:'arith', name:'mul_int', desc:'b=a*3',
    init:['var a:Number=7;','var b:Number=0;'],
    base:'b=a;', test:'b=a*3;', finalize:'_bh += b;', atomicOps:1 },

  // v7压缩: mul_float 与 mul_int 同量级，已删除

  { cat:'arith', name:'div_int', desc:'b=a/2',
    init:['var a:Number=8;','var b:Number=0;'],
    base:'b=a;', test:'b=a/2;', finalize:'_bh += b;', atomicOps:1 },

  // v7压缩: div_float 与 div_int 同量级，已删除

  { cat:'arith', name:'mod_int', desc:'b=a%3',
    init:['var a:Number=7;','var b:Number=0;'],
    base:'b=a;', test:'b=a%3;', finalize:'_bh += b;', atomicOps:1 },

  { cat:'arith', name:'negate', desc:'b=-a',
    init:['var a:Number=7;','var b:Number=0;'],
    base:'b=a;', test:'b=-a;', finalize:'_bh += b;', atomicOps:1 },

  { cat:'arith', name:'incr_post', desc:'c=b++',
    init:['var b:Number=0;','var c:Number=0;'],
    base:'c=b;', test:'c=b++;', finalize:'_bh += c+b;', atomicOps:1 },

  // v7压缩: incr_pre 与 incr_post 同量级，已删除

  { cat:'arith', name:'compound_addassign', desc:'b+=a',
    init:['var a:Number=1;','var b:Number=0;'],
    base:'b=a;', test:'b+=a;', finalize:'_bh += b;', atomicOps:1 },

  { cat:'arith', name:'compound_expr', desc:'b=a*3+c*2',
    init:['var a:Number=7;','var c:Number=5;','var b:Number=0;'],
    base:'b=a;', test:'b=a*3+c*2;', finalize:'_bh += b;', atomicOps:3 },

  // v7 新增：常量折叠检测
  { cat:'arith', name:'const_fold', desc:'b=3+4 常量折叠?',
    init:['var b:Number=0;','var a:Number=7;'],
    base:'b=a;', test:'b=3+4;', finalize:'_bh += b;', atomicOps:1 },

  // bitwise
  { cat:'arith', name:'bit_and', desc:'b=a&0xFF',
    init:['var a:Number=255;','var b:Number=0;'],
    base:'b=a;', test:'b=a&0xFF;', finalize:'_bh += b;', atomicOps:1 },

  { cat:'arith', name:'bit_or', desc:'b=a|1',
    init:['var a:Number=128;','var b:Number=0;'],
    base:'b=a;', test:'b=a|1;', finalize:'_bh += b;', atomicOps:1 },

  { cat:'arith', name:'bit_xor', desc:'b=a^1',
    init:['var a:Number=255;','var b:Number=0;'],
    base:'b=a;', test:'b=a^1;', finalize:'_bh += b;', atomicOps:1 },

  { cat:'arith', name:'bit_not', desc:'b=~a 单一取反',
    init:['var a:Number=255;','var b:Number=0;'],
    base:'b=a;', test:'b=~a;', finalize:'_bh += b;', atomicOps:1 },

  { cat:'arith', name:'lshift', desc:'b=a<<2',
    init:['var a:Number=1;','var b:Number=0;'],
    base:'b=a;', test:'b=a<<2;', finalize:'_bh += b;', atomicOps:1 },

  { cat:'arith', name:'rshift', desc:'b=a>>2',
    init:['var a:Number=1024;','var b:Number=0;'],
    base:'b=a;', test:'b=a>>2;', finalize:'_bh += b;', atomicOps:1 },

  // v7压缩: urshift 与 lshift/rshift 同机制，已删除

  // compare
  { cat:'arith', name:'eq_num', desc:'a==1',
    init:['var a:Number=1;','var cst:Boolean=false;','var b:Boolean=false;'],
    base:'b=cst;', test:'b=(a==1);', finalize:'_bh += (b?1:0);', atomicOps:1 },

  { cat:'arith', name:'strict_eq', desc:'a===1',
    init:['var a:Number=1;','var cst:Boolean=false;','var b:Boolean=false;'],
    base:'b=cst;', test:'b=(a===1);', finalize:'_bh += (b?1:0);', atomicOps:1 },

  // v7压缩: neq_num/strict_neq 与 eq_num/strict_eq 同机制，已删除

  { cat:'arith', name:'lt_cmp', desc:'a<2',
    init:['var a:Number=1;','var cst:Boolean=false;','var b:Boolean=false;'],
    base:'b=cst;', test:'b=(a<2);', finalize:'_bh += (b?1:0);', atomicOps:1 },

  { cat:'arith', name:'gt_cmp', desc:'a>0',
    init:['var a:Number=1;','var cst:Boolean=false;','var b:Boolean=false;'],
    base:'b=cst;', test:'b=(a>0);', finalize:'_bh += (b?1:0);', atomicOps:1 },

  // cross-type
  { cat:'arith', name:'eq_str_num', desc:'"42"==42 跨类型==',
    init:['var s:String="42";','var cst:Boolean=false;','var b:Boolean=false;'],
    base:'b=cst;', test:'b=(s==42);', finalize:'_bh += (b?1:0);', atomicOps:1 },

  { cat:'arith', name:'strict_eq_str_num', desc:'"42"===42 跨类型===',
    init:['var s:String="42";','var cst:Boolean=false;','var b:Boolean=false;'],
    base:'b=cst;', test:'b=(s===42);', finalize:'_bh += (b?1:0);', atomicOps:1 },

  // NaN/Infinity — v7fix: AS2中NaN==NaN为true, b!=b无法检测NaN, 必须用isNaN()
  { cat:'arith', name:'nan_add', desc:'NaN+1 (NaN传播)',
    init:['var a:Number=NaN;','var b:Number=0;','var sink:Number=0;'],
    base:'sink=a;', test:'b=a+1;', finalize:'_bh += (isNaN(b)?1:0);', atomicOps:1 },

  { cat:'arith', name:'infinity_mul', desc:'Infinity*2',
    init:['var a:Number=Infinity;','var b:Number=0;','var sink:Number=0;'],
    base:'sink=a;', test:'b=a*2;', finalize:'_bh += (b>9999999?1:0);', atomicOps:1 },

  // ===================== BRANCH =====================
  { cat:'branch', name:'if_true', desc:'if(true) path',
    init:['var a:Boolean=true;','var b:Number=0;','var cst:Number=1;'],
    base:'b=cst;', test:'if(a){b=1;}else{b=0;}', finalize:'_bh += b;', atomicOps:1 },

  { cat:'branch', name:'if_false', desc:'if(false) path',
    init:['var a:Boolean=false;','var b:Number=0;','var cst:Number=0;'],
    base:'b=cst;', test:'if(a){b=1;}else{b=0;}', finalize:'_bh += b;', atomicOps:1 },

  // v7压缩: ternary_true/false 与 if_true/false 功能重叠，已删除

  { cat:'branch', name:'logical_and_short', desc:'false&&x 短路',
    init:['var a:Boolean=false;','var cst:Boolean=false;','var b:Boolean=false;'],
    base:'b=cst;', test:'b=a&&true;', finalize:'_bh += (b?1:0);', atomicOps:1 },

  { cat:'branch', name:'logical_and_eval', desc:'true&&x 求值',
    init:['var a:Boolean=true;','var cst:Boolean=true;','var b:Boolean=false;'],
    base:'b=cst;', test:'b=a&&true;', finalize:'_bh += (b?1:0);', atomicOps:1 },

  { cat:'branch', name:'logical_or_short', desc:'true||x 短路',
    init:['var a:Boolean=true;','var cst:Boolean=true;','var b:Boolean=false;'],
    base:'b=cst;', test:'b=a||true;', finalize:'_bh += (b?1:0);', atomicOps:1 },

  // v7压缩: logical_or_eval 与 logical_and_eval 同模式，已删除

  { cat:'branch', name:'not_bool', desc:'!a',
    init:['var a:Boolean=true;','var cst:Boolean=false;','var b:Boolean=false;'],
    base:'b=cst;', test:'b=!a;', finalize:'_bh += (b?1:0);', atomicOps:1 },

  { cat:'branch', name:'double_not', desc:'!!a 强转布尔',
    init:['var a:Number=1;','var cst:Boolean=true;','var b:Boolean=false;'],
    base:'b=cst;', test:'b=!!a;', finalize:'_bh += (b?1:0);', atomicOps:1 },

  // ===================== ACCESS =====================
  // v7压缩: arr_read_const_5 被 arr_read_var_5 覆盖，已删除

  { cat:'access', name:'arr_read_var_5', desc:'arr[idx] 5元素',
    init:['var arr5:Array=[1,2,3,4,5];','var idx:Number=2;','var b:Number=0;','var cst:Number=3;'],
    base:'b=cst;', test:'b=arr5[idx];', finalize:'_bh += b;', atomicOps:1 },

  { cat:'access', name:'arr_read_var_100', desc:'arr[idx] 100元素',
    init:['var idx:Number=50;','var b:Number=0;','var cst:Number=50;'],
    base:'b=cst;', test:'b=_arr100[idx];', finalize:'_bh += b;', atomicOps:1 },

  { cat:'access', name:'arr_read_var_1000', desc:'arr[idx] 1000元素',
    init:['var idx:Number=500;','var b:Number=0;','var cst:Number=500;'],
    base:'b=cst;', test:'b=_arr1000[idx];', finalize:'_bh += b;', atomicOps:1 },

  { cat:'access', name:'arr_write_const', desc:'arr[2]=a',
    init:['var arr:Array=[0,0,0,0,0];','var a:Number=1;','var b:Number=0;'],
    base:'b=a;', test:'arr[2]=a;', finalize:'_bh += arr[2]+b;', atomicOps:1 },

  { cat:'access', name:'arr_write_var', desc:'arr[idx]=a',
    init:['var arr:Array=[0,0,0,0,0];','var idx:Number=2;','var a:Number=1;','var b:Number=0;'],
    base:'b=a;', test:'arr[idx]=a;', finalize:'_bh += arr[idx]+b;', atomicOps:1 },

  // v7压缩: arr_oob_read 边缘case，优先级低，已删除

  { cat:'access', name:'arr_length', desc:'arr.length',
    init:['var arr5:Array=[1,2,3,4,5];','var b:Number=0;','var cst:Number=5;'],
    base:'b=cst;', test:'b=arr5.length;', finalize:'_bh += b;', atomicOps:1 },

  // Object
  { cat:'access', name:'obj_dot_hit', desc:'o.x 点访问',
    init:['var b:Number=0;','var cst:Number=42;'],
    base:'b=cst;', test:'b=_obj_shallow.x;', finalize:'_bh += b;', atomicOps:1 },

  { cat:'access', name:'obj_bracket_str', desc:'o[k] 变量键',
    init:['var k:String="x";','var b:Number=0;','var cst:Number=42;'],
    base:'b=cst;', test:'b=_obj_shallow[k];', finalize:'_bh += b;', atomicOps:1 },

  // v7压缩: obj_bracket_literal 与 obj_bracket_str 同类，已删除

  { cat:'access', name:'obj_miss', desc:'o.notExist',
    init:['var b;','var cst;'],
    base:'b=cst;', test:'b=_obj_shallow.notExist;', finalize:'_bh += (b==undefined?0:1);', atomicOps:1 },

  { cat:'access', name:'proto1_read', desc:'原型链深度1',
    init:['var b:Number=0;','var cst:Number=99;'],
    base:'b=cst;', test:'b=_obj_proto1.inherited_x;', finalize:'_bh += b;', atomicOps:1 },

  { cat:'access', name:'proto2_read', desc:'原型链深度2',
    init:['var b:Number=0;','var cst:Number=77;'],
    base:'b=cst;', test:'b=_obj_proto2.deep_x;', finalize:'_bh += b;', atomicOps:1 },

  { cat:'access', name:'proto3_read', desc:'原型链深度3',
    init:['var b:Number=0;','var cst:Number=33;'],
    base:'b=cst;', test:'b=_obj_proto3.very_deep_x;', finalize:'_bh += b;', atomicOps:1 },

  { cat:'access', name:'member_set_existing', desc:'o.x=a 已有属性',
    init:['var a:Number=1;','var b:Number=0;'],
    base:'b=a;', test:'_obj_shallow.x=a;', finalize:'_bh += _obj_shallow.x+b;', atomicOps:1 },

  { cat:'access', name:'member_set_newprop', desc:'o.dyn=a 新属性',
    init:['var o:Object={};','var a:Number=1;','var b:Number=0;'],
    base:'b=a;', test:'o.dyn=a;', finalize:'_bh += (o.dyn==undefined?0:o.dyn)+b;', atomicOps:1 },

  { cat:'access', name:'chain_depth2', desc:'a.b.x 链式2层',
    init:['var b:Number=0;','var cst:Number=10;'],
    base:'b=cst;', test:'b=_chain2.inner.x;', finalize:'_bh += b;', atomicOps:1 },

  { cat:'access', name:'chain_depth3', desc:'a.b.c.x 链式3层',
    init:['var b:Number=0;','var cst:Number=20;'],
    base:'b=cst;', test:'b=_chain3.mid.inner.x;', finalize:'_bh += b;', atomicOps:1 },

  // native MC
  { cat:'access', name:'native_get_x', desc:'_mc._x',
    init:['var b:Number=0;','var cst:Number=0;'],
    base:'b=cst;', test:'b=_mc._x;', finalize:'_bh += b;', atomicOps:1 },

  { cat:'access', name:'native_set_x', desc:'_mc._x=a',
    init:['var a:Number=0;','var b:Number=0;'],
    base:'b=a;', test:'_mc._x=a;', finalize:'_bh += _mc._x+b;', atomicOps:1 },

  { cat:'access', name:'native_get_visible', desc:'_mc._visible',
    init:['var cst:Boolean=true;','var b:Boolean=false;'],
    base:'b=cst;', test:'b=_mc._visible;', finalize:'_bh += (b?1:0);', atomicOps:1 },

  // v7压缩: native_get_alpha 与 native_get_x 同类，已删除

  // ===================== CALL =====================
  { cat:'call', name:'call_empty', desc:'空函数调用',
    init:['var b:Number=0;','var cst:Number=0;'],
    base:'b=cst;', test:'_empty_fn();', finalize:'_bh += b;', atomicOps:1 },

  { cat:'call', name:'call_onearg', desc:'单参数调用',
    init:['var a:Number=1;','var b:Number=0;'],
    base:'b=a;', test:'b=_identity_fn(a);', finalize:'_bh += b;', atomicOps:1 },

  { cat:'call', name:'call_twoargs', desc:'双参数调用',
    init:['var a:Number=1;','var b:Number=0;'],
    base:'b=a;', test:'b=_add_fn(a,a);', finalize:'_bh += b;', atomicOps:1 },

  { cat:'call', name:'call_threeargs', desc:'三参数调用',
    init:['var a:Number=1;','var b:Number=0;'],
    base:'b=a;', test:'b=_add3_fn(a,a,a);', finalize:'_bh += b;', atomicOps:1 },

  { cat:'call', name:'call_fiveargs', desc:'五参数调用',
    init:['var a:Number=1;','var b:Number=0;'],
    base:'b=a;', test:'b=_add5_fn(a,a,a,a,a);', finalize:'_bh += b;', atomicOps:1 },

  { cat:'call', name:'call_method', desc:'方法调用 o.m()',
    init:['var b:Number=0;','var cst:Number=0;'],
    base:'b=cst;', test:'_obj_shallow.emptyMethod();', finalize:'_bh += b;', atomicOps:1 },

  { cat:'call', name:'call_method_ret', desc:'方法调用有返回值',
    init:['var b:Number=0;','var cst:Number=42;'],
    base:'b=cst;', test:'b=_obj_shallow.retMethod();', finalize:'_bh += b;', atomicOps:1 },

  { cat:'call', name:'fn_call_onearg', desc:'.call(null,a)',
    init:['var a:Number=1;','var b:Number=0;'],
    base:'b=_identity_fn(a);', test:'b=_identity_fn.call(null,a);', finalize:'_bh += b;', atomicOps:1 },

  { cat:'call', name:'fn_apply_cached', desc:'.apply 复用args',
    init:['var a:Number=1;','var b:Number=0;','var args:Array=[1];'],
    base:'b=_identity_fn(a);', test:'b=_identity_fn.apply(null,args);', finalize:'_bh += b;', atomicOps:1 },

  { cat:'call', name:'new_empty', desc:'new EmptyCtor()',
    init:['var o:Object;','var b:Number=0;','var cst:Number=0;'],
    base:'b=cst;', test:'o=new _EmptyCtor();', finalize:'_bh += (o==undefined?0:1)+b;', atomicOps:1 },

  { cat:'call', name:'new_simple', desc:'new SimpleCtor()',
    init:['var o:Object;','var b:Number=0;','var cst:Number=0;'],
    base:'b=cst;', test:'o=new _SimpleCtor();', finalize:'_bh += (o.x==undefined?0:o.x)+b;', atomicOps:1 },

  { cat:'call', name:'closure_read', desc:'闭包变量读取',
    init:['var b:Number=0;','var cst:Number=42;'],
    base:'b=cst;', test:'b=_closure_reader();', finalize:'_bh += b;', atomicOps:1 },

  { cat:'call', name:'closure_deep2', desc:'2层嵌套闭包',
    init:['var b:Number=0;','var cst:Number=100;'],
    base:'b=cst;', test:'b=_closure_deep2();', finalize:'_bh += b;', atomicOps:1 },

  { cat:'call', name:'arguments_length', desc:'arguments.length',
    init:['var b:Number=0;','var cst:Number=0;'],
    base:'b=cst;', test:'b=_args_length_fn(1,2,3);', finalize:'_bh += b;', atomicOps:1 },

  { cat:'call', name:'arguments_read', desc:'arguments[0]',
    init:['var b:Number=0;','var cst:Number=0;'],
    base:'b=cst;', test:'b=_args_read_fn(42);', finalize:'_bh += b;', atomicOps:1 },

  { cat:'call', name:'proto_method', desc:'原型方法调用',
    init:['var b:Number=0;','var cst:Number=0;'],
    base:'b=cst;', test:'b=_obj_proto_method.getValue();', finalize:'_bh += b;', atomicOps:1 },

  { cat:'call', name:'instance_method', desc:'实例方法调用',
    init:['var b:Number=0;','var cst:Number=0;'],
    base:'b=cst;', test:'b=_obj_inst_method.getValue();', finalize:'_bh += b;', atomicOps:1 },

  // ===================== STRING =====================
  { cat:'string', name:'str_eq_hit', desc:'s=="hello" 命中',
    init:['var s:String="hello";','var cst:Boolean=true;','var b:Boolean=false;'],
    base:'b=cst;', test:'b=(s=="hello");', finalize:'_bh += (b?1:0);', atomicOps:1 },

  { cat:'string', name:'str_eq_miss', desc:'s=="world" 未命中',
    init:['var s:String="hello";','var cst:Boolean=false;','var b:Boolean=false;'],
    base:'b=cst;', test:'b=(s=="world");', finalize:'_bh += (b?1:0);', atomicOps:1 },

  { cat:'string', name:'str_eq_long_hit', desc:'50字符== 命中',
    init:['var s:String=_longStr50;','var cst:Boolean=true;','var b:Boolean=false;'],
    base:'b=cst;', test:'b=(s==_longStr50);', finalize:'_bh += (b?1:0);', atomicOps:1 },

  // v7压缩: str_eq_long_miss 与 str_eq_long_hit 互补但非关键，已删除

  { cat:'string', name:'str_concat_short', desc:'s+"b"',
    init:['var s:String="a";','var r:String="";'],
    base:'r=s;', test:'r=s+"b";', finalize:'_bh += r.length;', atomicOps:1 },

  { cat:'string', name:'str_concat_long', desc:'50字符+短串',
    init:['var s:String=_longStr50;','var r:String="";'],
    base:'r=s;', test:'r=s+"x";', finalize:'_bh += r.length;', atomicOps:1 },

  { cat:'string', name:'str_length', desc:'s.length',
    init:['var s:String="hello_world";','var b:Number=0;','var cst:Number=11;'],
    base:'b=cst;', test:'b=s.length;', finalize:'_bh += b;', atomicOps:1 },

  { cat:'string', name:'str_charat', desc:'s.charAt(3)',
    init:['var s:String="hello_world";','var r:String="";','var cstR:String="l";'],
    base:'r=cstR;', test:'r=s.charAt(3);', finalize:'_bh += r.length;', atomicOps:1 },

  { cat:'string', name:'str_charcodeat', desc:'s.charCodeAt(3)',
    init:['var s:String="hello_world";','var b:Number=0;','var cst:Number=108;'],
    base:'b=cst;', test:'b=s.charCodeAt(3);', finalize:'_bh += b;', atomicOps:1 },

  { cat:'string', name:'str_indexof_short_hit', desc:'短串indexOf命中',
    init:['var s:String="hello_world";','var b:Number=0;','var cst:Number=6;'],
    base:'b=cst;', test:'b=s.indexOf("world");', finalize:'_bh += b;', atomicOps:1 },

  { cat:'string', name:'str_indexof_short_miss', desc:'短串indexOf未命中',
    init:['var s:String="hello_world";','var b:Number=0;','var cst:Number=-1;'],
    base:'b=cst;', test:'b=s.indexOf("zzz");', finalize:'_bh += b;', atomicOps:1 },

  { cat:'string', name:'str_substr', desc:'substr(2,4)',
    init:['var s:String="hello_world";','var r:String="";','var cstR:String="llo_";'],
    base:'r=cstR;', test:'r=s.substr(2,4);', finalize:'_bh += r.length;', atomicOps:1 },

  { cat:'string', name:'str_split', desc:'split(",")',
    init:['var s:String="a,b,c";','var r:Array;'],
    base:'r=_split_stub;', test:'r=s.split(",");', finalize:'_bh += r.length;', atomicOps:1 },

  { cat:'string', name:'str_tolower', desc:'toLowerCase',
    init:['var s:String="HELLO";','var r:String="";','var cstR:String="hello";'],
    base:'r=cstR;', test:'r=s.toLowerCase();', finalize:'_bh += r.length;', atomicOps:1 },

  { cat:'string', name:'str_fromcharcode', desc:'String.fromCharCode(65)',
    init:['var b:String="";','var cstR:String="A";'],
    base:'b=cstR;', test:'b=String.fromCharCode(65);', finalize:'_bh += b.length;', atomicOps:1 },

  // ===================== CONVERT =====================
  { cat:'convert', name:'to_number_str', desc:'Number("42")',
    init:['var s:String="42";','var b:Number=0;','var cst:Number=42;'],
    base:'b=cst;', test:'b=Number(s);', finalize:'_bh += b;', atomicOps:1 },

  { cat:'convert', name:'unary_plus', desc:'+s 一元加',
    init:['var s:String="42";','var b:Number=0;','var cst:Number=42;'],
    base:'b=cst;', test:'b=+s;', finalize:'_bh += Number(b);', atomicOps:1 },

  { cat:'convert', name:'parseint_dec', desc:'parseInt(s)',
    init:['var s:String="42";','var b:Number=0;','var cst:Number=42;'],
    base:'b=cst;', test:'b=parseInt(s);', finalize:'_bh += b;', atomicOps:1 },

  { cat:'convert', name:'parseint_hex', desc:'parseInt(s,16)',
    init:['var s:String="FF";','var b:Number=0;','var cst:Number=255;'],
    base:'b=cst;', test:'b=parseInt(s,16);', finalize:'_bh += b;', atomicOps:1 },

  { cat:'convert', name:'parsefloat', desc:'parseFloat(s)',
    init:['var s:String="3.14";','var b:Number=0;','var cst:Number=3.14;'],
    base:'b=cst;', test:'b=parseFloat(s);', finalize:'_bh += b;', atomicOps:1 },

  { cat:'convert', name:'to_string_num', desc:'String(42)',
    init:['var n:Number=42;','var s:String="";','var cstR:String="42";'],
    base:'s=cstR;', test:'s=String(n);', finalize:'_bh += s.length;', atomicOps:1 },

  { cat:'convert', name:'to_string_concat', desc:'""+n',
    init:['var n:Number=42;','var s:String="";','var cstR:String="42";'],
    base:'s=cstR;', test:'s=""+n;', finalize:'_bh += s.length;', atomicOps:1 },

  { cat:'convert', name:'typeof_num', desc:'typeof(x) number',
    init:['var x=42;','var s:String="";','var cstR:String="number";'],
    base:'s=cstR;', test:'s=typeof(x);', finalize:'_bh += s.length;', atomicOps:1 },

  // v7压缩: typeof_str/typeof_obj 与 typeof_num 同机制，已删除

  { cat:'convert', name:'typeof_undef', desc:'typeof(x) undefined',
    init:['var x;','var s:String="";','var cstR:String="undefined";'],
    base:'s=cstR;', test:'s=typeof(x);', finalize:'_bh += s.length;', atomicOps:1 },

  { cat:'convert', name:'instanceof_direct', desc:'o instanceof Ctor',
    init:['var o:Object=_obj_proto1;','var cst:Boolean=true;','var b:Boolean=false;'],
    base:'b=cst;', test:'b=(o instanceof _BaseProto1);', finalize:'_bh += (b?1:0);', atomicOps:1 },

  // v7压缩: instanceof_proto2 与 instanceof_direct 同模式，已删除

  { cat:'convert', name:'to_bool_num', desc:'Boolean(1)',
    init:['var n:Number=1;','var cst:Boolean=true;','var b:Boolean=false;'],
    base:'b=cst;', test:'b=Boolean(n);', finalize:'_bh += (b?1:0);', atomicOps:1 },

  // v7压缩: to_bool_doublenot 与 branch/double_not 重复，已删除

  // 类型强转
  { cat:'convert', name:'number_cast_num', desc:'Number(n) noop',
    init:['var a:Number=42;','var b:Number=0;'],
    base:'b=a;', test:'b=Number(a);', finalize:'_bh += b;', atomicOps:1 },

  { cat:'convert', name:'number_cast_obj', desc:'Number(obj) valueOf',
    init:['var o:Object=_objWithValueOf;','var b:Number=0;','var cst:Number=42;'],
    base:'b=cst;', test:'b=Number(o);', finalize:'_bh += b;', atomicOps:1 },

  { cat:'convert', name:'number_cast_bool', desc:'Number(true)',
    init:['var t:Boolean=true;','var b:Number=0;','var cst:Number=1;'],
    base:'b=cst;', test:'b=Number(t);', finalize:'_bh += b;', atomicOps:1 },

  { cat:'convert', name:'number_cast_undef', desc:'Number(undefined)→NaN',
    init:['var u;','var b:Number=0;','var cst:Number=0;'],
    base:'b=cst;', test:'b=Number(u);', finalize:'_bh += (isNaN(b)?1:0);', atomicOps:1 },

  // v7压缩: string_cast_num 与 to_string_num 重复，已删除

  { cat:'convert', name:'string_cast_bool', desc:'String(true)',
    init:['var t:Boolean=true;','var s:String="";','var cstR:String="true";'],
    base:'s=cstR;', test:'s=String(t);', finalize:'_bh += s.length;', atomicOps:1 },

  // v7 新增：有类型 vs 无类型变量
  { cat:'convert', name:'typed_vs_untyped_read', desc:'var a:Number vs var a 读取',
    init:['var a:Number=42;','var b:Number=0;'],
    base:'b=a;', test:'b=_untyped_42;', finalize:'_bh += b;', atomicOps:1 },

  // ===================== MATH =====================
  { cat:'math', name:'math_floor', desc:'Math.floor(a)',
    init:['var a:Number=3.7;','var b:Number=0;','var cst:Number=3;'],
    base:'b=cst;', test:'b=Math.floor(a);', finalize:'_bh += b;', atomicOps:1 },

  { cat:'math', name:'math_ceil', desc:'Math.ceil(a)',
    init:['var a:Number=3.2;','var b:Number=0;','var cst:Number=4;'],
    base:'b=cst;', test:'b=Math.ceil(a);', finalize:'_bh += b;', atomicOps:1 },

  { cat:'math', name:'math_round', desc:'Math.round(a)',
    init:['var a:Number=3.5;','var b:Number=0;','var cst:Number=4;'],
    base:'b=cst;', test:'b=Math.round(a);', finalize:'_bh += b;', atomicOps:1 },

  { cat:'math', name:'math_abs', desc:'Math.abs(a)',
    init:['var a:Number=-3;','var b:Number=0;','var cst:Number=3;'],
    base:'b=cst;', test:'b=Math.abs(a);', finalize:'_bh += b;', atomicOps:1 },

  { cat:'math', name:'math_min', desc:'Math.min(a,c)',
    init:['var a:Number=3;','var c:Number=5;','var b:Number=0;','var cst:Number=3;'],
    base:'b=cst;', test:'b=Math.min(a,c);', finalize:'_bh += b;', atomicOps:1 },

  { cat:'math', name:'math_max', desc:'Math.max(a,c)',
    init:['var a:Number=3;','var c:Number=5;','var b:Number=0;','var cst:Number=5;'],
    base:'b=cst;', test:'b=Math.max(a,c);', finalize:'_bh += b;', atomicOps:1 },

  { cat:'math', name:'math_sqrt', desc:'Math.sqrt(a)',
    init:['var a:Number=9;','var b:Number=0;','var cst:Number=3;'],
    base:'b=cst;', test:'b=Math.sqrt(a);', finalize:'_bh += b;', atomicOps:1 },

  { cat:'math', name:'math_sin', desc:'Math.sin(a)',
    init:['var a:Number=1;','var b:Number=0;','var cst:Number=0;'],
    base:'b=cst;', test:'b=Math.sin(a);', finalize:'_bh += b;', atomicOps:1 },

  // v7压缩: math_cos 与 math_sin 同机制，已删除

  { cat:'math', name:'math_atan2', desc:'Math.atan2(a,c)',
    init:['var a:Number=1;','var c:Number=1;','var b:Number=0;','var cst:Number=0;'],
    base:'b=cst;', test:'b=Math.atan2(a,c);', finalize:'_bh += b;', atomicOps:1 },

  { cat:'math', name:'math_random', desc:'Math.random()',
    init:['var b:Number=0;','var cst:Number=0;'],
    base:'b=cst;', test:'b=Math.random();', finalize:'_bh += b;', atomicOps:1 },

  // bit-hacks
  { cat:'math', name:'floor_bitor0', desc:'a|0 取整',
    init:['var a:Number=3.7;','var b:Number=0;','var cst:Number=3;'],
    base:'b=cst;', test:'b=a|0;', finalize:'_bh += b;', atomicOps:1 },

  // v7压缩: floor_rshift0 与 floor_bitor0 同机制，已删除

  { cat:'math', name:'floor_doubletilde', desc:'~~a 取整(双重按位非)',
    init:['var a:Number=3.7;','var b:Number=0;','var cst:Number=3;'],
    base:'b=cst;', test:'b=~~a;', finalize:'_bh += b;', atomicOps:1 },

  { cat:'math', name:'abs_ternary', desc:'a<0?-a:a',
    init:['var a:Number=-3;','var b:Number=0;','var cst:Number=3;'],
    base:'b=cst;', test:'b=(a<0?-a:a);', finalize:'_bh += b;', atomicOps:1 },

  { cat:'math', name:'min_ternary', desc:'a<c?a:c',
    init:['var a:Number=3;','var c:Number=5;','var b:Number=0;','var cst:Number=3;'],
    base:'b=cst;', test:'b=(a<c?a:c);', finalize:'_bh += b;', atomicOps:1 },

  { cat:'math', name:'max_ternary', desc:'a>c?a:c',
    init:['var a:Number=3;','var c:Number=5;','var b:Number=0;','var cst:Number=5;'],
    base:'b=cst;', test:'b=(a>c?a:c);', finalize:'_bh += b;', atomicOps:1 },

  { cat:'math', name:'cached_math_floor', desc:'缓存引用 mf(a)',
    init:['var a:Number=3.7;','var b:Number=0;','var cst:Number=3;'],
    base:'b=cst;', test:'b=_mfloor(a);', finalize:'_bh += b;', atomicOps:1 },

  { cat:'math', name:'cached_math_sin', desc:'缓存引用 ms(a)',
    init:['var a:Number=1;','var b:Number=0;','var cst:Number=0;'],
    base:'b=cst;', test:'b=_msin(a);', finalize:'_bh += b;', atomicOps:1 },

  { cat:'math', name:'clamp_mathminmax', desc:'Math.min(Math.max(a,lo),hi)',
    init:['var a:Number=7;','var lo:Number=0;','var hi:Number=10;','var b:Number=0;','var cst:Number=7;'],
    base:'b=cst;', test:'b=Math.min(Math.max(a,lo),hi);', finalize:'_bh += b;', atomicOps:2 },

  { cat:'math', name:'clamp_ternary', desc:'a<lo?lo:(a>hi?hi:a)',
    init:['var a:Number=7;','var lo:Number=0;','var hi:Number=10;','var b:Number=0;','var cst:Number=7;'],
    base:'b=cst;', test:'b=(a<lo?lo:(a>hi?hi:a));', finalize:'_bh += b;', atomicOps:2 },

  // ===================== SCOPE =====================
  { cat:'scope', name:'local_read', desc:'局部变量读',
    init:['var a:Number=1;','var b:Number=0;','var cst:Number=0;'],
    base:'b=cst;', test:'b=a;', finalize:'_bh += b;', atomicOps:1 },

  { cat:'scope', name:'global_read', desc:'全局变量读',
    init:['var b:Number=0;','var cst:Number=0;'],
    base:'b=cst;', test:'b=_global_var;', finalize:'_bh += b;', atomicOps:1 },

  { cat:'scope', name:'global_write', desc:'全局变量写',
    init:['var a:Number=1;','var b:Number=0;'],
    base:'b=a;', test:'_global_var=a;', finalize:'_bh += _global_var+b;', atomicOps:1 },

  { cat:'scope', name:'root_read', desc:'_root._root_var',
    init:['var b:Number=0;','var cst:Number=0;'],
    base:'b=cst;', test:'b=_root._root_var;', finalize:'_bh += b;', atomicOps:1 },

  { cat:'scope', name:'with_block', desc:'with(o){b=x;}',
    init:['var b:Number=0;','var cst:Number=42;'],
    base:'b=cst;', test:'with(_obj_shallow){b=x;}', finalize:'_bh += b;', atomicOps:1 },

  { cat:'scope', name:'delete_prop', desc:'delete o.tmp',
    init:['var o:Object={};','var a:Number=1;','var b:Number=0;'],
    base:'b=a;', test:'o.tmp=a; delete o.tmp;', finalize:'_bh += (o.tmp==undefined?0:1)+b;', atomicOps:1 },

  { cat:'scope', name:'hasown_hit', desc:'hasOwnProperty("x")',
    init:['var o:Object={x:1};','var cst:Boolean=true;','var b:Boolean=false;'],
    base:'b=cst;', test:'b=o.hasOwnProperty("x");', finalize:'_bh += (b?1:0);', atomicOps:1 },

  // v7压缩: hasown_miss 与 hasown_hit 差距极小，已删除

  { cat:'scope', name:'in_operator_hit', desc:'"x" in o (helper)',
    init:['var o:Object={x:1};','var cst:Boolean=true;','var b:Boolean=false;'],
    base:'b=cst;', test:'b=_in_op("x", o);', finalize:'_bh += (b?1:0);', atomicOps:1 },

  // v7压缩: in_operator_miss 差距小，已删除

  { cat:'scope', name:'isnan_fn', desc:'isNaN(NaN)',
    init:['var n:Number=NaN;','var cst:Boolean=true;','var b:Boolean=false;'],
    base:'b=cst;', test:'b=isNaN(n);', finalize:'_bh += (b?1:0);', atomicOps:1 },

  { cat:'scope', name:'isnan_selfne', desc:'n!=n 替代isNaN',
    init:['var n:Number=NaN;','var cst:Boolean=true;','var b:Boolean=false;'],
    base:'b=cst;', test:'b=(n!=n);', finalize:'_bh += (b?1:0);', atomicOps:1 },

  { cat:'scope', name:'gettimer_call', desc:'getTimer()',
    init:['var b:Number=0;','var cst:Number=0;'],
    base:'b=cst;', test:'b=getTimer();', finalize:'_bh += b;', atomicOps:1 },

  { cat:'scope', name:'undef_eq_null', desc:'x==null',
    init:['var x;','var cst:Boolean=true;','var b:Boolean=false;'],
    base:'b=cst;', test:'b=(x==null);', finalize:'_bh += (b?1:0);', atomicOps:1 },

  // v7压缩: undef_eq_undef 与 undef_eq_null 同模式，已删除

  { cat:'scope', name:'undef_strict_eq', desc:'x===undefined',
    init:['var x;','var cst:Boolean=true;','var b:Boolean=false;'],
    base:'b=cst;', test:'b=(x===undefined);', finalize:'_bh += (b?1:0);', atomicOps:1 },

  // v7压缩: undef_typeof 与 undef_eq_null/undef_strict_eq 重叠，已删除

  // try/catch
  { cat:'scope', name:'try_noexcept', desc:'try{...}catch 无异常',
    kind:'struct',
    init:['var a:Number=1;','var b:Number=0;'],
    base:'b=a;', test:'try{b=a;}catch(e){}', finalize:'_bh += b;', atomicOps:1 },

  { cat:'scope', name:'try_except', desc:'try{throw}catch',
    kind:'struct',
    init:['var a:Number=1;','var b:Number=0;','var err:Object={message:"x"};'],
    base:'b=a;', test:'try{throw err;}catch(e){b=a;}', finalize:'_bh += b;', atomicOps:1 },

  { cat:'scope', name:'eval_varname', desc:'eval("_global_var")',
    kind:'struct',
    init:['var b=0;','var cst=1;'],
    base:'b=cst;', test:'b=eval("_global_var");', finalize:'_bh += b;', atomicOps:1 },

  // ===================== ARRAY METHODS =====================
  { cat:'array', name:'arr_push', desc:'arr.push(1)',
    kind:'struct',
    init:['var arr:Array;','var b:Number=0;'],
    resetEach:['arr=[1,2,3,4,5];'],
    base:'b=0;', test:'arr.push(1);', finalize:'_bh += arr.length+b;', atomicOps:1 },

  { cat:'array', name:'arr_pop', desc:'arr.pop()',
    kind:'struct',
    init:['var arr:Array;','var b=0;'],
    resetEach:['arr=[1,2,3,4,5,6,7,8,9,10];'],
    base:'b=0;', test:'b=arr.pop();', finalize:'_bh += Number(b);', atomicOps:1 },

  { cat:'array', name:'arr_unshift', desc:'arr.unshift(0)',
    kind:'struct',
    init:['var arr:Array;','var b:Number=0;'],
    resetEach:['arr=[1,2,3];'],
    base:'b=0;', test:'arr.unshift(0);', finalize:'_bh += arr.length+b;', atomicOps:1 },

  { cat:'array', name:'arr_shift', desc:'arr.shift()',
    kind:'struct',
    init:['var arr:Array;','var b=0;'],
    resetEach:['arr=[1,2,3,4,5,6,7,8,9,10];'],
    base:'b=0;', test:'b=arr.shift();', finalize:'_bh += Number(b);', atomicOps:1 },

  { cat:'array', name:'arr_splice_mid', desc:'arr.splice(2,1)',
    kind:'struct',
    init:['var arr:Array;','var b:Array;'],
    resetEach:['arr=[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15];'],
    base:'b=arr;', test:'b=arr.splice(2,1);', finalize:'_bh += b.length;', atomicOps:1 },

  { cat:'array', name:'arr_reverse', desc:'arr.reverse()',
    init:['var arr:Array=[1,2,3,4,5];','var b:Number=0;','var cst:Number=0;'],
    base:'b=cst;', test:'arr.reverse();', finalize:'_bh += arr[0]+b;', atomicOps:1 },

  { cat:'array', name:'arr_join', desc:'arr.join(",")',
    init:['var arr:Array=[1,2,3];','var s:String="";','var cstR:String="1,2,3";'],
    base:'s=cstR;', test:'s=arr.join(",");', finalize:'_bh += s.length;', atomicOps:1 },

  { cat:'array', name:'arr_sort_5', desc:'5元素 sort()',
    kind:'struct',
    init:['var arr:Array;','var b:Number=0;'],
    resetEach:['arr=[5,3,1,4,2];'],
    base:'b=0;', test:'arr.sort();', finalize:'_bh += arr[0]+b;', atomicOps:1 },

  { cat:'array', name:'arr_concat', desc:'arr.concat([6,7])',
    init:['var arr:Array=[1,2,3,4,5];','var stub:Array=[6,7];','var r:Array;'],
    base:'r=arr;', test:'r=arr.concat(stub);', finalize:'_bh += r.length;', atomicOps:1 },

  { cat:'array', name:'arr_slice_mid', desc:'arr.slice(1,3)',
    init:['var arr:Array=[1,2,3,4,5];','var r:Array;'],
    base:'r=arr;', test:'r=arr.slice(1,3);', finalize:'_bh += r.length;', atomicOps:1 },

  // v7 新增：arr.length=0 清空
  { cat:'array', name:'arr_length_clear', desc:'arr.length=0 清空',
    kind:'struct',
    init:['var arr:Array;','var b:Number=0;'],
    resetEach:['arr=[1,2,3,4,5];'],
    base:'b=0;', test:'arr.length=0;', finalize:'_bh += arr.length+b;', atomicOps:1 },

  // ===================== GC HEAVY =====================
  { cat:'gc', name:'gc_apply_newarray', desc:'apply([1]) 每次new',
    kind:'gc', init:['var b:Number=0;','var args:Array=[1];'],
    base:'b=_identity_fn.apply(null,args);', test:'b=_identity_fn.apply(null,[1]);',
    finalize:'_bh += b;', atomicOps:1 },

  { cat:'gc', name:'gc_new_object', desc:'new SimpleCtor()',
    kind:'gc', init:['var o:Object;','var b:Number=0;','var cst:Number=0;'],
    base:'b=cst;', test:'o=new _SimpleCtor();',
    finalize:'_bh += (o.x==undefined?0:o.x)+b;', atomicOps:1 },

  { cat:'gc', name:'gc_new_array', desc:'new Array()',
    kind:'gc', init:['var a:Array;','var b:Number=0;','var cst:Number=0;'],
    base:'b=cst;', test:'a=new Array();',
    finalize:'_bh += (a==undefined?0:1)+b;', atomicOps:1 },

  { cat:'gc', name:'gc_obj_literal', desc:'{x:1}',
    kind:'gc', init:['var o:Object;','var b:Number=0;','var cst:Number=0;'],
    base:'b=cst;', test:'o={x:1};',
    finalize:'_bh += (o.x==undefined?0:o.x)+b;', atomicOps:1 },

  { cat:'gc', name:'gc_arr_literal', desc:'[1,2,3]',
    kind:'gc', init:['var a:Array;','var b:Number=0;','var cst:Number=0;'],
    base:'b=cst;', test:'a=[1,2,3];',
    finalize:'_bh += (a==undefined?0:a.length)+b;', atomicOps:1 },

  { cat:'gc', name:'gc_arr_10elem', desc:'[1..10] 10元素',
    kind:'gc', init:['var a:Array;','var b:Number=0;','var cst:Number=0;'],
    base:'b=cst;', test:'a=[1,2,3,4,5,6,7,8,9,10];',
    finalize:'_bh += (a==undefined?0:a.length)+b;', atomicOps:1 },

  { cat:'gc', name:'gc_string_split', desc:'split(",") GC',
    kind:'gc', init:['var s:String="a,b,c";','var r:Array;'],
    base:'r=_split_stub;', test:'r=s.split(",");',
    finalize:'_bh += r.length;', atomicOps:1 },

  { cat:'gc', name:'gc_array_concat', desc:'concat([4,5]) GC',
    kind:'gc', init:['var arr:Array=[1,2,3];','var stub:Array=[4,5];','var r:Array;'],
    base:'r=arr;', test:'r=arr.concat(stub);',
    finalize:'_bh += r.length;', atomicOps:1 },

  // v7压缩: gc_array_slice 与 gc_array_concat 同模式，已删除

  { cat:'gc', name:'gc_string_concat_accum', desc:'s+=x 累积',
    kind:'gc', init:['var s:String="";','var x:String="ab";'],
    base:'s=x;', test:'s+=x;',
    finalize:'_bh += s.length;', atomicOps:1 },

  { cat:'gc', name:'gc_obj_5props', desc:'{a:1..e:5}',
    kind:'gc', init:['var o:Object;','var b:Number=0;','var cst:Number=0;'],
    base:'b=cst;', test:'o={a:1,b:2,c:3,d:4,e:5};',
    finalize:'_bh += (o.a==undefined?0:o.a)+b;', atomicOps:1 },
];

const categories = [
  ['arith',   'ARITH / COMPARE / BITWISE'],
  ['branch',  'BRANCH / CONTROL / LOGIC'],
  ['access',  'ACCESS / MEMBER / ARRAY / CHAIN'],
  ['call',    'CALL / NEW / CLOSURE / ARGUMENTS'],
  ['string',  'STRING'],
  ['convert', 'CONVERT / TYPE / TYPEOF / CAST'],
  ['math',    'MATH / NATIVES / BIT-HACKS'],
  ['scope',   'SCOPE / MISC / UNDEFINED / TRY / EVAL'],
  ['array',   'ARRAY METHODS'],
  ['gc',      'GC HEAVY']
];

// ======================================================================
// CODE GENERATION
// ======================================================================

const pairFns = benches.map(makePairFns).join('\n\n');

function getTotal(b) {
  const kind = b.kind || 'std';
  if (kind === 'gc') return CFG.GC_TOTAL;
  if (kind === 'struct') return CFG.STRUCT_TOTAL;
  return CFG.STD_TOTAL;
}

function emitRunCalls(filterKind) {
  return benches.filter(b => {
    const kind = b.kind || 'std';
    return filterKind === 'gc' ? kind === 'gc' : kind !== 'gc';
  }).map(b => {
    const total = getTotal(b) * (b.atomicOps || 1);
    const isGC = (b.kind === 'gc') ? 'true' : 'false';
    return '    _results.push(_measurePair("' + b.cat + '", "' + b.name + '", "' +
           b.desc.replace(/"/g, '\\"') + '", base_' + b.name + ', test_' + b.name +
           ', ' + total + ', ' + isGC + '));';
  }).join('\n');
}

// Special tests (minimal changes from v6)
const forInFns = [
  'function bench_forin_5props():Number {',
  '    var t0:Number = getTimer();',
  '    var i:Number = ' + CFG.FORIN_OUTER + ';',
  '    var o:Object = {a:1,b:2,c:3,d:4,e:5};',
  '    var k:String;',
  '    while (i--) {',
  Array(CFG.FORIN_UNROLL).fill('        for (k in o) { _bh += 0; }').join('\n'),
  '    }',
  '    return getTimer() - t0;',
  '}',
  '',
  'function bench_forin_20props():Number {',
  '    var t0:Number = getTimer();',
  '    var i:Number = ' + Math.floor(CFG.FORIN_OUTER / 4) + ';',
  '    var k:String;',
  '    while (i--) {',
  Array(CFG.FORIN_UNROLL).fill('        for (k in _obj20props) { _bh += 0; }').join('\n'),
  '    }',
  '    return getTimer() - t0;',
  '}'
].join('\n');

const SWITCH_UNROLL = 20;
const SWITCH_OUTER = 25000;

const switchFn = [
  'function bench_switch_5cases():Number {',
  '    var t0:Number = getTimer();',
  '    var i:Number = ' + SWITCH_OUTER + ';',
  '    var v:Number = 3;',
  '    var b:Number = 0;',
  '    while (i--) {',
  Array(SWITCH_UNROLL).fill([
    '        switch(v) {',
    '            case 1: b=1; break;',
    '            case 2: b=2; break;',
    '            case 3: b=3; break;',
    '            case 4: b=4; break;',
    '            case 5: b=5; break;',
    '            default: b=0;',
    '        }'
  ].join('\n')).join('\n'),
  '    }',
  '    _bh += b;',
  '    return getTimer() - t0;',
  '}'
].join('\n');

const switchIfElseFn = [
  'function bench_ifelse_5cases():Number {',
  '    var t0:Number = getTimer();',
  '    var i:Number = ' + SWITCH_OUTER + ';',
  '    var v:Number = 3;',
  '    var b:Number = 0;',
  '    while (i--) {',
  Array(SWITCH_UNROLL).fill(
    '        if(v==1){b=1;}else if(v==2){b=2;}else if(v==3){b=3;}else if(v==4){b=4;}else if(v==5){b=5;}else{b=0;}'
  ).join('\n'),
  '    }',
  '    _bh += b;',
  '    return getTimer() - t0;',
  '}'
].join('\n');

const switch10Fn = [
  'function bench_switch_10cases():Number {',
  '    var t0:Number = getTimer();',
  '    var i:Number = ' + SWITCH_OUTER + ';',
  '    var v:Number = 7;',
  '    var b:Number = 0;',
  '    while (i--) {',
  Array(SWITCH_UNROLL).fill([
    '        switch(v) {',
    '            case 1: b=1; break; case 2: b=2; break; case 3: b=3; break;',
    '            case 4: b=4; break; case 5: b=5; break; case 6: b=6; break;',
    '            case 7: b=7; break; case 8: b=8; break; case 9: b=9; break;',
    '            case 10: b=10; break; default: b=0;',
    '        }'
  ].join('\n')).join('\n'),
  '    }',
  '    _bh += b;',
  '    return getTimer() - t0;',
  '}'
].join('\n');

const ifelse10Fn = [
  'function bench_ifelse_10cases():Number {',
  '    var t0:Number = getTimer();',
  '    var i:Number = ' + SWITCH_OUTER + ';',
  '    var v:Number = 7;',
  '    var b:Number = 0;',
  '    while (i--) {',
  Array(SWITCH_UNROLL).fill(
    '        if(v==1){b=1;}else if(v==2){b=2;}else if(v==3){b=3;}else if(v==4){b=4;}else if(v==5){b=5;}else if(v==6){b=6;}else if(v==7){b=7;}else if(v==8){b=8;}else if(v==9){b=9;}else if(v==10){b=10;}else{b=0;}'
  ).join('\n'),
  '    }',
  '    _bh += b;',
  '    return getTimer() - t0;',
  '}'
].join('\n');

const LOOP_INNER = 100000;
const LOOP_REPEAT = 20;

const loopFns = [
  'function bench_loop_while():Number {',
  '    var t0:Number = getTimer();',
  '    var j:Number = ' + LOOP_REPEAT + ';',
  '    while (j--) {',
  '        var i:Number = ' + LOOP_INNER + ';',
  '        while (i--) { _bh += 0; }',
  '    }',
  '    return getTimer() - t0;',
  '}',
  '',
  'function bench_loop_for():Number {',
  '    var t0:Number = getTimer();',
  '    var j:Number = ' + LOOP_REPEAT + ';',
  '    while (j--) {',
  '        var i:Number;',
  '        for (i = 0; i < ' + LOOP_INNER + '; i++) { _bh += 0; }',
  '    }',
  '    return getTimer() - t0;',
  '}',
  '',
  'function bench_loop_dowhile():Number {',
  '    var t0:Number = getTimer();',
  '    var j:Number = ' + LOOP_REPEAT + ';',
  '    while (j--) {',
  '        var i:Number = ' + LOOP_INNER + ';',
  '        do { _bh += 0; } while (--i);',
  '    }',
  '    return getTimer() - t0;',
  '}',
  '',
  'function bench_loop_empty_while():Number {',
  '    var t0:Number = getTimer();',
  '    var j:Number = ' + LOOP_REPEAT + ';',
  '    var b:Number = 0;',
  '    while (j--) {',
  '        var i:Number = ' + LOOP_INNER + ';',
  '        while (i--) { b = 0; }',
  '    }',
  '    _bh += b;',
  '    return getTimer() - t0;',
  '}'
].join('\n');

// ======================================================================
// ASSEMBLE OUTPUT
// ======================================================================
const forin20Total = Math.floor(CFG.FORIN_OUTER / 4) * CFG.FORIN_UNROLL;
const switchTotal = SWITCH_OUTER * SWITCH_UNROLL;
const loopTotal = LOOP_REPEAT * LOOP_INNER;

const out = [
'// BenchMain_v7.as  — 自动生成（bench_gen_v7.js）',
'// AVM1/AS2 性能基准测试 v7',
'// v7修复: _quality命名冲突→_qualityTag; NaN感染_bh; base对称化; GC信噪比',
'// 使用建议：Release 模式；独立空场景；关闭动画/网络；固定 FPS=60；同机重复3次',
'',
'// v7: 用 _bh 替代 _blackhole 避免长变量名占用字节',
'var _bh:Number = 0;',
'var _global_var:Number = 1;',
'_root._root_var = 2;',
'var _mc:MovieClip = this;',
'var _split_stub:Array = ["a","b","c"];',
'',
'// v7 新增：无类型变量 (用于 typed vs untyped 对比)',
'var _untyped_42 = 42;',
'',
'// 测试辅助对象',
'var _obj_shallow:Object = {x:42, y:0};',
'_obj_shallow.emptyMethod = function():Void {};',
'_obj_shallow.retMethod = function():Number { return 42; };',
'',
'// valueOf 对象（类型强转测试）',
'var _objWithValueOf:Object = {valueOf:function():Number{return 42;}};',
'',
'// 原型链',
'function _BaseProto1() {}',
'_BaseProto1.prototype.inherited_x = 99;',
'_BaseProto1.prototype.x = 55;',
'var _obj_proto1:Object = new _BaseProto1();',
'',
'function _BaseProto2() {}',
'_BaseProto2.prototype = new _BaseProto1();',
'_BaseProto2.prototype.deep_x = 77;',
'var _obj_proto2:Object = new _BaseProto2();',
'',
'function _BaseProto3() {}',
'_BaseProto3.prototype = new _BaseProto2();',
'_BaseProto3.prototype.very_deep_x = 33;',
'var _obj_proto3:Object = new _BaseProto3();',
'',
'var _chain2:Object = {inner:{x:10}};',
'var _chain3:Object = {mid:{inner:{x:20}}};',
'',
'var _arr100:Array = [];',
'var _i:Number;',
'for (_i = 0; _i < 100; _i++) _arr100[_i] = _i;',
'var _arr1000:Array = [];',
'for (_i = 0; _i < 1000; _i++) _arr1000[_i] = _i;',
'',
'var _obj20props:Object = {};',
'for (_i = 0; _i < 20; _i++) _obj20props["p" + _i] = _i;',
'',
'var _longStr50:String = "01234567890123456789012345678901234567890123456789";',
'var _longStr50b:String = "X1234567890123456789012345678901234567890123456789";',
'',
'function _empty_fn():Void {}',
'function _identity_fn(v:Number):Number { return v; }',
'function _add_fn(a:Number, b:Number):Number { return a + b; }',
'function _add3_fn(a:Number, b:Number, c:Number):Number { return a + b + c; }',
'function _add5_fn(a:Number, b:Number, c:Number, d:Number, e:Number):Number { return a + b + c + d + e; }',
'function _SimpleCtor() { this.x = 1; }',
'function _EmptyCtor() {}',
'',
'function _in_op(key:String, obj:Object):Boolean {',
'    for (var k:String in obj) {',
'        if (k == key) return true;',
'    }',
'    return false;',
'}',
'',
'function _makeClosureReader():Function {',
'    var captured:Number = 42;',
'    return function():Number { return captured; };',
'}',
'var _closure_reader:Function = _makeClosureReader();',
'',
'function _makeDeepClosure2():Function {',
'    var outer:Number = 100;',
'    return function():Number { return outer; };',
'}',
'var _closure_deep2:Function = _makeDeepClosure2();',
'',
'var _mfloor:Function = Math.floor;',
'var _msin:Function = Math.sin;',
'',
'function _args_length_fn():Number { return arguments.length; }',
'function _args_read_fn():Number { return Number(arguments[0]); }',
'',
'function _ProtoMethodCtor() { this.val = 10; }',
'_ProtoMethodCtor.prototype.getValue = function():Number { return this.val; };',
'var _obj_proto_method:Object = new _ProtoMethodCtor();',
'',
'function _InstMethodCtor() {',
'    this.val = 10;',
'    this.getValue = function():Number { return this.val; };',
'}',
'var _obj_inst_method:Object = new _InstMethodCtor();',
'',
'// === 统计工具 ===',
'function _fmt(n:Number, d:Number):String {',
'    if (isNaN(n)) return "NaN";',   // v7fix: AS2中 NaN==NaN 为true，必须用isNaN()
'    var neg:Boolean = (n < 0);',
'    if (neg) n = -n;',
'    var factor:Number = Math.pow(10, d);',
'    var rounded:Number = Math.round(n * factor);',
'    var intPart:Number = Math.floor(rounded / factor);',
'    var fracPart:Number = rounded - intPart * factor;',
'    var fracStr:String = String(fracPart);',
'    while (fracStr.length < d) fracStr = "0" + fracStr;',
'    return (neg ? "-" : "") + String(intPart) + "." + fracStr;',
'}',
'',
'function _cloneArr(src:Array):Array {',
'    var out:Array = [];',
'    var i:Number;',
'    for (i = 0; i < src.length; i++) out[i] = src[i];',
'    return out;',
'}',
'',
'function _sortNums(a:Array):Void {',
'    var n:Number = a.length;',
'    var i:Number; var j:Number; var t:Number;',
'    for (i = 0; i < n - 1; i++) {',
'        for (j = 0; j < n - 1 - i; j++) {',
'            if (a[j] > a[j + 1]) { t = a[j]; a[j] = a[j + 1]; a[j + 1] = t; }',
'        }',
'    }',
'}',
'',
'function _median(src:Array):Number {',
'    var a:Array = _cloneArr(src);',
'    _sortNums(a);',
'    var n:Number = a.length;',
'    if ((n & 1) == 1) return a[n >> 1];',
'    return (a[(n >> 1) - 1] + a[n >> 1]) * 0.5;',
'}',
'',
'function _iqrFilter(src:Array):Array {',
'    var s:Array = _cloneArr(src);',
'    _sortNums(s);',
'    var n:Number = s.length;',
'    if (n < 4) return _cloneArr(src);',
'    var q1:Number = s[Math.floor(n * 0.25)];',
'    var q3:Number = s[Math.floor(n * 0.75)];',
'    var iqr:Number = q3 - q1;',
'    var lo:Number = q1 - 1.5 * iqr;',
'    var hi:Number = q3 + 1.5 * iqr;',
'    var out:Array = [];',
'    var i:Number;',
'    for (i = 0; i < n; i++) {',
'        if (s[i] >= lo && s[i] <= hi) out.push(s[i]);',
'    }',
'    return (out.length >= 3) ? out : _cloneArr(src);',
'}',
'',
'function _mean(a:Array):Number {',
'    var sum:Number = 0; var i:Number;',
'    for (i = 0; i < a.length; i++) sum += a[i];',
'    return sum / a.length;',
'}',
'',
'function _stddev(a:Array, avg:Number):Number {',
'    var sum:Number = 0; var i:Number;',
'    for (i = 0; i < a.length; i++) {',
'        var d:Number = a[i] - avg;',
'        sum += d * d;',
'    }',
'    return Math.sqrt(sum / a.length);',
'}',
'',
'function _minNum(a:Array):Number {',
'    var m:Number = a[0]; var i:Number;',
'    for (i = 1; i < a.length; i++) if (a[i] < m) m = a[i];',
'    return m;',
'}',
'function _maxNum(a:Array):Number {',
'    var m:Number = a[0]; var i:Number;',
'    for (i = 1; i < a.length; i++) if (a[i] > m) m = a[i];',
'    return m;',
'}',
'',
'// v7: 重命名为 _qualityTag 避免与 AS2 内置 _quality 属性冲突',
'function _qualityTag(filtered:Array, deltaMed:Number, quantum:Number):String {',
'    if (deltaMed <= 0) return "BASELINE";',
'    if (deltaMed < quantum * 2) return "NOISY<2q";',
'    var avg:Number = _mean(filtered);',
'    var sd:Number = _stddev(filtered, avg);',
'    if (avg == 0) return "ZERO_AVG";',
'    var cv:Number = sd / (avg < 0 ? -avg : avg);',
'    if (cv > 0.25) return "NOISY_CV>" + _fmt(cv, 2);',
'    if (cv > 0.10) return "FAIR_CV=" + _fmt(cv, 2);',
'    return "OK_CV=" + _fmt(cv, 2);',
'}',
'',
'function _measureTimerQuantum(samples:Number):Number {',
'    var diffs:Array = [];',
'    var i:Number;',
'    for (i = 0; i < samples; i++) {',
'        var t0:Number = getTimer();',
'        var t1:Number = t0;',
'        while (t1 == t0) t1 = getTimer();',
'        diffs.push(t1 - t0);',
'    }',
'    return _median(diffs);',
'}',
'',
'function _measurePair(cat:String, name:String, desc:String, baseFn:Function, testFn:Function, atomicTotal:Number, isGC:Boolean):Object {',
'    var baseRaw:Array = [];',
'    var testRaw:Array = [];',
'    var deltas:Array = [];',
'    var r:Number; var b:Number; var t:Number;',
'    for (r = 0; r < ' + CFG.WARMUP + '; r++) { baseFn(); testFn(); }',
'    for (r = 0; r < ' + CFG.REPEATS + '; r++) {',
'        if ((r & 1) == 0) { b = baseFn(); t = testFn(); }',
'        else { t = testFn(); b = baseFn(); }',
'        baseRaw.push(b);',
'        testRaw.push(t);',
'        deltas.push(t - b);',
'    }',
'    var filtered:Array = _iqrFilter(deltas);',
'    var deltaMed:Number = _median(filtered);',
'    var perOpNs:Number = (deltaMed / atomicTotal) * 1000000;',
'    if (typeof(_bh) != "number") trace("!!! TYPE INFECTED after: " + name + " typeof=" + typeof(_bh) + " val=" + String(_bh).substr(0,80));',
'    if (isNaN(_bh)) trace("!!! NaN INFECTED after: " + name + " typeof=" + typeof(_bh));',
'    return {',
'        cat:cat, name:name, desc:desc,',
'        baseMed:_median(baseRaw), testMed:_median(testRaw),',
'        deltaMed:deltaMed,',
'        deltaMin:_minNum(filtered), deltaMax:_maxNum(filtered),',
'        perOpNs:perOpNs,',
'        atomicTotal:atomicTotal, isGC:isGC,',
'        filtered:filtered',
'    };',
'}',
'',
pairFns,
'',
forInFns,
'',
switchFn,
'',
switchIfElseFn,
'',
switch10Fn,
'',
ifelse10Fn,
'',
loopFns,
'',
'function run_all():Void {',
'    var out:String = "=== AVM1 Benchmark Results v7 ===\\n";',
'    out += "player=" + getVersion() + "\\n";',
'    out += "STD_TOTAL=' + CFG.STD_TOTAL + '  GC_TOTAL=' + CFG.GC_TOTAL + '  STRUCT_TOTAL=' + CFG.STRUCT_TOTAL + '  REPEATS=' + CFG.REPEATS + '  WARMUP=' + CFG.WARMUP + '\\n";',
'    var timerQuantum:Number = _measureTimerQuantum(32);',
'    out += "timer_quantum=" + _fmt(timerQuantum, 2) + "ms\\n";',
'    out += "bh_pre=" + _fmt(_bh, 2) + "\\n\\n";',
'',
'    var _results:Array = [];',
emitRunCalls('std'),
'',
emitRunCalls('gc'),
'',
'    // v7: 用 noop_baseline + add_int 双重基准',
'    var refNs:Number = 1;',
'    var ri:Number;',
'    for (ri = 0; ri < _results.length; ri++) {',
'        if (_results[ri].name == "add_int") { refNs = _results[ri].perOpNs; break; }',
'    }',
'    if (refNs <= 0) refNs = 1;',
'',
'    var ci:Number; var catName:String; var label:String; var i:Number;',
'    for (ci = 0; ci < ' + categories.length + '; ci++) {',
'        catName = ' + JSON.stringify(categories.map(c=>c[0])) + '[ci];',
'        label = ' + JSON.stringify(categories.map(c=>c[1])) + '[ci];',
'        out += "\\n[" + label + "]\\n";',
'        for (i = 0; i < _results.length; i++) {',
'            var row:Object = _results[i];',
'            if (row.cat != catName) continue;',
'            var q:String = _qualityTag(row.filtered, row.deltaMed, timerQuantum);',
'            var rel:Number = row.perOpNs / refNs;',
'            out += "  " + row.name + ": " +',
'                   "delta=" + _fmt(row.deltaMed,2) + "ms  " +',
'                   "per-op=" + _fmt(row.perOpNs,1) + "ns  " +',
'                   "rel=" + _fmt(rel,2) + "x  " +',
'                   "base=" + _fmt(row.baseMed,1) + "  test=" + _fmt(row.testMed,1) + "  " +',
'                   "range=[" + _fmt(row.deltaMin,1) + "," + _fmt(row.deltaMax,1) + "]  " +',
'                   q +',
'                   (row.isGC ? "  [GC]" : "") +',
'                   "\\n";',
'        }',
'    }',
'',
'    out += "\\n[SPECIAL: for-in / switch / if-else / loops]\\n";',
'    if (typeof(_bh) != "number") trace("!!! TYPE before SPECIAL: typeof=" + typeof(_bh));',
'',
'    var forin5Raw:Array = [];',
'    var forin20Raw:Array = [];',
'    var fi:Number;',
'    for (fi = 0; fi < 5; fi++) {',
'        forin5Raw.push(bench_forin_5props());',
'        forin20Raw.push(bench_forin_20props());',
'    }',
'    var forin5Med:Number = _median(forin5Raw);',
'    var forin20Med:Number = _median(forin20Raw);',
'    out += "  forin_5props: med=" + _fmt(forin5Med,1) + "ms  per-iter=" + _fmt((forin5Med/' + CFG.FORIN_TOTAL + ')*1000000,1) + "ns  N=' + CFG.FORIN_TOTAL + '\\n";',
'    out += "  forin_20props: med=" + _fmt(forin20Med,1) + "ms  per-iter=" + _fmt((forin20Med/' + forin20Total + ')*1000000,1) + "ns  N=' + forin20Total + '\\n";',
'',
'    if (typeof(_bh) != "number") trace("!!! TYPE after forin: typeof=" + typeof(_bh));',
'    var switchRaw:Array = [];',
'    var ifelseRaw:Array = [];',
'    var switch10Raw:Array = [];',
'    var ifelse10Raw:Array = [];',
'    for (fi = 0; fi < 5; fi++) {',
'        switchRaw.push(bench_switch_5cases());',
'        ifelseRaw.push(bench_ifelse_5cases());',
'        switch10Raw.push(bench_switch_10cases());',
'        ifelse10Raw.push(bench_ifelse_10cases());',
'    }',
'    out += "  switch_5cases: med=" + _fmt(_median(switchRaw),1) + "ms  per-op=" + _fmt((_median(switchRaw)/' + switchTotal + ')*1000000,1) + "ns  N=' + switchTotal + '\\n";',
'    out += "  ifelse_5cases: med=" + _fmt(_median(ifelseRaw),1) + "ms  per-op=" + _fmt((_median(ifelseRaw)/' + switchTotal + ')*1000000,1) + "ns  N=' + switchTotal + '\\n";',
'    out += "  switch_10cases: med=" + _fmt(_median(switch10Raw),1) + "ms  per-op=" + _fmt((_median(switch10Raw)/' + switchTotal + ')*1000000,1) + "ns  N=' + switchTotal + '\\n";',
'    out += "  ifelse_10cases: med=" + _fmt(_median(ifelse10Raw),1) + "ms  per-op=" + _fmt((_median(ifelse10Raw)/' + switchTotal + ')*1000000,1) + "ns  N=' + switchTotal + '\\n";',
'',
'    if (typeof(_bh) != "number") trace("!!! TYPE after switch: typeof=" + typeof(_bh));',
'    var loopWRaw:Array = [];',
'    var loopFRaw:Array = [];',
'    var loopDRaw:Array = [];',
'    var loopEWRaw:Array = [];',
'    for (fi = 0; fi < 5; fi++) {',
'        loopWRaw.push(bench_loop_while());',
'        loopFRaw.push(bench_loop_for());',
'        loopDRaw.push(bench_loop_dowhile());',
'        loopEWRaw.push(bench_loop_empty_while());',
'    }',
'    out += "  loop_while_dec: med=" + _fmt(_median(loopWRaw),1) + "ms  per-iter=" + _fmt((_median(loopWRaw)/' + loopTotal + ')*1000000,1) + "ns\\n";',
'    out += "  loop_for_inc:   med=" + _fmt(_median(loopFRaw),1) + "ms  per-iter=" + _fmt((_median(loopFRaw)/' + loopTotal + ')*1000000,1) + "ns\\n";',
'    out += "  loop_dowhile:   med=" + _fmt(_median(loopDRaw),1) + "ms  per-iter=" + _fmt((_median(loopDRaw)/' + loopTotal + ')*1000000,1) + "ns\\n";',
'    out += "  loop_empty_while: med=" + _fmt(_median(loopEWRaw),1) + "ms  per-iter=" + _fmt((_median(loopEWRaw)/' + loopTotal + ')*1000000,1) + "ns\\n";',
'',
'    if (typeof(_bh) != "number") trace("!!! TYPE after loop: typeof=" + typeof(_bh));',
'    out += "\\nbh_post=" + _fmt(_bh, 2) + "\\n";',
'    out += "=== END ===\\n";',
'    trace(out);',
'}',
'',
'run_all();',
''
].join('\n');

// Write with BOM
const outFile = path.join(OUT_DIR, 'BenchMain_v7.as');
const bom = Buffer.from([0xEF, 0xBB, 0xBF]);
const content = Buffer.from(out, 'utf8');
fs.writeFileSync(outFile, Buffer.concat([bom, content]));

const manifest = {
  generator: 'bench_gen_v7.js',
  output: 'BenchMain_v7.as',
  config: CFG,
  benchmarks: benches.map(b => ({ cat: b.cat, name: b.name, desc: b.desc, kind: b.kind || 'std', atomicOps: b.atomicOps })),
  standardBenchCount: benches.filter(b => (b.kind || 'std') !== 'gc').length,
  gcBenchCount: benches.filter(b => b.kind === 'gc').length,
  totalBenchCount: benches.length,
  categories,
  specialTests: ['forin_5props', 'forin_20props', 'switch_5cases', 'ifelse_5cases', 'switch_10cases', 'ifelse_10cases', 'loop_while', 'loop_for', 'loop_dowhile', 'loop_empty_while']
};
fs.writeFileSync(path.join(OUT_DIR, 'manifest_v7.json'), JSON.stringify(manifest, null, 2), 'utf8');

const lines = out.split('\n').length;
const sizeKB = Math.round(Buffer.byteLength(out, 'utf8') / 1024);
console.log('Generated:', outFile);
console.log('  Lines:', lines, '  Size:', sizeKB + 'KB');
console.log('  Bench count:', manifest.totalBenchCount, '(std=' + manifest.standardBenchCount + ', gc=' + manifest.gcBenchCount + ')');
console.log('  Special tests:', manifest.specialTests.length);
console.log('  Categories:', categories.length);
