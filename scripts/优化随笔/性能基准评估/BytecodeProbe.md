=== BytecodeProbe: 运行所有探针防止 DCE ===
A-and:255
A-or:129
A-xor:254
A-not:-256
A-or0:3
A-dtil:3
A-lsh:4
A-rsh:256
NaN == NaN: true
NaN != NaN: false
NaN === NaN: true
NaN !== NaN: false
n == n: true
n != n: false
isNaN(n): true
B-selfne:false
B-isnan:true
C-uplus:42
C-numcast:42
D-cfold:7
D-varadd:7
D-cmul:42
E-cassign:1
E-cmret:42
E-fncall:1
F-local:42
F-global:42
F-member:42
F-bracket:42
G-typed:42
G-untyped:42
H-strlen:5
H-arrlen:5
H-as1len:5
I-boolcast:true
I-dblnot:true
J-typeof:number
K-mfloor:3
K-cfloor:3
L-sw5:40
L-if5:40
M-eq:true
M-seq:true
M-eqx:true
M-seqx:false
N-new0:[object Object]
N-new1:[object Object]
O-addi:8
O-addf:3.64
O-neg:-7
O-post:0
P-closure:42
P-arglen:0
P-argread:99
Q-arrlocal:30
Q-arrglobal:50
R-with:42
R-tryok:1
R-tryex:1
S-hasown:true
S-forin:3
T-pint:42
T-pfloat:3.14
T-strcast:42
T-strconcat:42
=== 探针组 U: call_empty 异常诊断 ===
U3-ret_df1:0
U4-ret_df2:1
U5-caller_df2:0
U7-ret_df2_1arg:1
U11-base:0
U11-test:0
U12-onearg:42
U15-true_df2_ret:1
=== BytecodeProbe 完成 ===




ConstantPool "NaN", "NaN == NaN: ", "NaN != NaN: ", "NaN === NaN: ", "NaN !== NaN: ", "n == n: ", "n != n: ", "isNaN(n): ", "isNaN", "42", "_emptyFn", "_identityFn", "_gObj", "emptyMethod", "retMethod", "call", "_gVar", "x", "hello", "length", "Boolean", "", "Math", "floor", "_ProbeCtor0", "_ProbeCtor1", "captured", "outer", "mid", "_gArr100", "b", "message", "tmp", "hasOwnProperty", "a", "c", "parseInt", "3.14", "parseFloat", "_callU_decl_only_df1", "_callU_empty_df2", "_callU_empty_df1", "_callU_ret_df1", "_callU_ret_df2", "_callU_void_nosig", "y", "_pI", "=== BytecodeProbe: 运行所有探针防止 DCE ===", "A-and:", "probe_bit_and", "A-or:", "probe_bit_or", "A-xor:", "probe_bit_xor", "A-not:", "probe_bit_not", "A-or0:", "probe_bit_or_zero", "A-dtil:", "probe_double_tilde", "A-lsh:", "probe_lshift", "A-rsh:", "probe_rshift", "probe_nan_eq", "B-selfne:", "probe_isnan_selfne", "B-isnan:", "probe_isnan_fn", "C-uplus:", "probe_unary_plus", "C-numcast:", "probe_number_cast", "D-cfold:", "probe_const_fold", "D-varadd:", "probe_var_add", "D-cmul:", "probe_const_mul", "probe_call_void", "E-cassign:", "probe_call_assign", "probe_call_method", "E-cmret:", "probe_call_method_ret", "E-fncall:", "probe_fn_dot_call", "F-local:", "probe_local_read", "F-global:", "probe_global_read", "F-member:", "probe_member_read", "F-bracket:", "probe_bracket_read", "G-typed:", "probe_typed_local", "G-untyped:", "probe_untyped_local", "H-strlen:", "probe_str_length", "H-arrlen:", "probe_arr_length", "H-as1len:", "probe_str_length_as1", "I-boolcast:", "probe_boolean_cast", "I-dblnot:", "probe_double_not", "J-typeof:", "probe_typeof", "K-mfloor:", "probe_math_floor", "K-cfloor:", "probe_cached_floor", "L-sw5:", "probe_switch_5", "L-if5:", "probe_ifelse_5", "M-eq:", "probe_eq_same_type", "M-seq:", "probe_strict_eq_same", "M-eqx:", "probe_eq_cross_type", "M-seqx:", "probe_strict_eq_cross", "N-new0:", "probe_new_empty", "N-new1:", "probe_new_simple", "O-addi:", "probe_add_int", "O-addf:", "probe_add_float", "O-neg:", "probe_negate", "O-post:", "probe_incr_post", "_pClosure", "probe_closure_factory", "P-closure:", "P-arglen:", "probe_arguments_length", "P-argread:", "probe_arguments_read", "Q-arrlocal:", "probe_arr_local_read", "Q-arrglobal:", "probe_arr_global_read", "R-with:", "probe_with_block", "R-tryok:", "probe_try_noexcept", "R-tryex:", "probe_try_except", "probe_delete_prop", "S-hasown:", "probe_hasown", "S-forin:", "probe_forin", "T-pint:", "probe_parseint", "T-pfloat:", "probe_parsefloat", "T-strcast:", "probe_string_cast", "T-strconcat:", "probe_string_concat_cast", "=== 探针组 U: call_empty 异常诊断 ===", "probe_U1_void_df1", "probe_U2_void_df2", "U3-ret_df1:", "probe_U3_ret_df1", "U4-ret_df2:", "probe_U4_ret_df2", "U5-caller_df2:", "probe_U5_caller_df2_void_df1", "probe_U6_void_df2_1arg", "U7-ret_df2_1arg:", "probe_U7_ret_df2_1arg", "probe_U8_void_nosig", "probe_U9_df2_0args", "probe_U10_double_void", "U11-base:", "probe_U11_bench_base", "U11-test:", "probe_U11_bench_test", "U12-onearg:", "probe_U12_onearg_test", "probe_U13_decl_only", "probe_U14_true_df2", "U15-true_df2_ret:", "probe_U15_true_df2_ret", "=== BytecodeProbe 完成 ==="
DefineFunction "_emptyFn", 0 {
}
DefineFunction2 "_identityFn", 1, 2, false, false, true, false, true, false, true, false, false, 1, "v" {
Push register1
Return
}
DefineFunction2 "probe_bit_and", 0, 3, false, false, true, false, true, false, true, false, false {
Push 255
StoreRegister 2
Pop
Push 0
StoreRegister 1
Pop
Push register2, 255
BitAnd
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_bit_or", 0, 3, false, false, true, false, true, false, true, false, false {
Push 128
StoreRegister 2
Pop
Push 0
StoreRegister 1
Pop
Push register2, 1
BitOr
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_bit_xor", 0, 3, false, false, true, false, true, false, true, false, false {
Push 255
StoreRegister 2
Pop
Push 0
StoreRegister 1
Pop
Push register2, 1
BitXor
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_bit_not", 0, 3, false, false, true, false, true, false, true, false, false {
Push 255
StoreRegister 2
Pop
Push 0
StoreRegister 1
Pop
Push register2, 4294967295
BitXor
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_bit_or_zero", 0, 3, false, false, true, false, true, false, true, false, false {
Push 3.7
StoreRegister 2
Pop
Push 0
StoreRegister 1
Pop
Push register2, 0
BitOr
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_double_tilde", 0, 3, false, false, true, false, true, false, true, false, false {
Push 3.7
StoreRegister 2
Pop
Push 0
StoreRegister 1
Pop
Push register2, 4294967295
BitXor
Push 4294967295
BitXor
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_lshift", 0, 3, false, false, true, false, true, false, true, false, false {
Push 1
StoreRegister 2
Pop
Push 0
StoreRegister 1
Pop
Push register2, 2
BitLShift
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_rshift", 0, 3, false, false, true, false, true, false, true, false, false {
Push 1024
StoreRegister 2
Pop
Push 0
StoreRegister 1
Pop
Push register2, 2
BitRShift
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_nan_eq", 0, 2, false, false, true, false, true, false, true, false, false {
Push "NaN"
GetVariable
StoreRegister 1
Pop
Push "NaN == NaN: ", "NaN"
GetVariable
Push "NaN"
GetVariable
Equals2
Add2
Trace
Push "NaN != NaN: ", "NaN"
GetVariable
Push "NaN"
GetVariable
Equals2
Not
Add2
Trace
Push "NaN === NaN: ", "NaN"
GetVariable
Push "NaN"
GetVariable
StrictEquals
Add2
Trace
Push "NaN !== NaN: ", "NaN"
GetVariable
Push "NaN"
GetVariable
StrictEquals
Not
Add2
Trace
Push "n == n: ", register1, register1
Equals2
Add2
Trace
Push "n != n: ", register1, register1
Equals2
Not
Add2
Trace
Push "isNaN(n): ", register1, 1, "isNaN"
CallFunction
Add2
Trace
}
DefineFunction2 "probe_isnan_selfne", 0, 3, false, false, true, false, true, false, true, false, false {
Push "NaN"
GetVariable
StoreRegister 2
Pop
Push false
StoreRegister 1
Pop
Push register2, register2
Equals2
Not
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_isnan_fn", 0, 3, false, false, true, false, true, false, true, false, false {
Push "NaN"
GetVariable
StoreRegister 2
Pop
Push false
StoreRegister 1
Pop
Push register2, 1, "isNaN"
CallFunction
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_unary_plus", 0, 3, false, false, true, false, true, false, true, false, false {
Push "42"
StoreRegister 2
Pop
Push 0
StoreRegister 1
Pop
Push register2
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_number_cast", 0, 3, false, false, true, false, true, false, true, false, false {
Push "42"
StoreRegister 2
Pop
Push 0
StoreRegister 1
Pop
Push register2
ToNumber
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_const_fold", 0, 2, false, false, true, false, true, false, true, false, false {
Push 0
StoreRegister 1
Pop
Push 7
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_var_add", 0, 4, false, false, true, false, true, false, true, false, false {
Push 3
StoreRegister 3
Pop
Push 4
StoreRegister 2
Pop
Push 0
StoreRegister 1
Pop
Push register3, register2
Add2
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_const_mul", 0, 2, false, false, true, false, true, false, true, false, false {
Push 0
StoreRegister 1
Pop
Push 42
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction "probe_call_void", 0 {
Push 0, "_emptyFn"
CallFunction
Pop
}
DefineFunction2 "probe_call_assign", 0, 2, false, false, true, false, true, false, true, false, false {
Push 0
StoreRegister 1
Pop
Push 1, 1, "_identityFn"
CallFunction
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction "probe_call_method", 0 {
Push 0, "_gObj"
GetVariable
Push "emptyMethod"
CallMethod
Pop
}
DefineFunction2 "probe_call_method_ret", 0, 2, false, false, true, false, true, false, true, false, false {
Push 0
StoreRegister 1
Pop
Push 0, "_gObj"
GetVariable
Push "retMethod"
CallMethod
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_fn_dot_call", 0, 2, false, false, true, false, true, false, true, false, false {
Push 0
StoreRegister 1
Pop
Push 1, null, 2, "_identityFn"
GetVariable
Push "call"
CallMethod
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_local_read", 0, 3, false, false, true, false, true, false, true, false, false {
Push 42
StoreRegister 2
Pop
Push 0
StoreRegister 1
Pop
Push register2
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_global_read", 0, 2, false, false, true, false, true, false, true, false, false {
Push 0
StoreRegister 1
Pop
Push "_gVar"
GetVariable
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_member_read", 0, 2, false, false, true, false, true, false, true, false, false {
Push 0
StoreRegister 1
Pop
Push "_gObj"
GetVariable
Push "x"
GetMember
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_bracket_read", 0, 2, false, false, true, false, true, false, true, false, false {
Push 0
StoreRegister 1
Pop
Push "_gObj"
GetVariable
Push "x"
GetMember
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_root_read", 0, 3, false, true, true, false, true, false, true, false, false {
Push 0
StoreRegister 2
Pop
Push register1, "_gVar"
GetMember
StoreRegister 2
Pop
Push register2
Return
}
DefineFunction2 "probe_typed_local", 0, 3, false, false, true, false, true, false, true, false, false {
Push 42
StoreRegister 2
Pop
Push 0
StoreRegister 1
Pop
Push register2
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_untyped_local", 0, 3, false, false, true, false, true, false, true, false, false {
Push 42
StoreRegister 2
Pop
Push 0
StoreRegister 1
Pop
Push register2
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_str_length", 0, 3, false, false, true, false, true, false, true, false, false {
Push "hello"
StoreRegister 2
Pop
Push 0
StoreRegister 1
Pop
Push register2, "length"
GetMember
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_arr_length", 0, 3, false, false, true, false, true, false, true, false, false {
Push 5, 4, 3, 2, 1, 5
InitArray
StoreRegister 2
Pop
Push 0
StoreRegister 1
Pop
Push register2, "length"
GetMember
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_str_length_as1", 0, 3, false, false, true, false, true, false, true, false, false {
Push "hello"
StoreRegister 2
Pop
Push 0
StoreRegister 1
Pop
Push register2
StringLength
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_boolean_cast", 0, 3, false, false, true, false, true, false, true, false, false {
Push 1
StoreRegister 2
Pop
Push false
StoreRegister 1
Pop
Push register2, 1, "Boolean"
CallFunction
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_double_not", 0, 3, false, false, true, false, true, false, true, false, false {
Push 1
StoreRegister 2
Pop
Push false
StoreRegister 1
Pop
Push register2
Not
Not
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_typeof", 0, 3, false, false, true, false, true, false, true, false, false {
Push 42
StoreRegister 2
Pop
Push ""
StoreRegister 1
Pop
Push register2
TypeOf
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_math_floor", 0, 3, false, false, true, false, true, false, true, false, false {
Push 3.7
StoreRegister 2
Pop
Push 0
StoreRegister 1
Pop
Push register2, 1, "Math"
GetVariable
Push "floor"
CallMethod
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_cached_floor", 0, 4, false, false, true, false, true, false, true, false, false {
Push "Math"
GetVariable
Push "floor"
GetMember
StoreRegister 3
Pop
Push 3.7
StoreRegister 2
Pop
Push 0
StoreRegister 1
Pop
Push register2, 1, register3, undefined
CallMethod
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_switch_5", 1, 2, false, false, true, false, true, false, true, false, false, 1, "v" {
Push register1
StoreRegister 0
Push 0
StrictEquals
If loc1612
Push register0, 1
StrictEquals
If loc161b
Push register0, 2
StrictEquals
If loc1624
Push register0, 3
StrictEquals
If loc162d
Push register0, 4
StrictEquals
If loc1636
Jump loc163f
loc1612:Push 10
Return
loc161b:Push 20
Return
loc1624:Push 30
Return
loc162d:Push 40
Return
loc1636:Push 50
Return
loc163f:Push 0
Return
}
DefineFunction2 "probe_ifelse_5", 1, 2, false, false, true, false, true, false, true, false, false, 1, "v" {
Push register1, 0
Equals2
Not
If loc1689
Push 10
Return
loc1689:Push register1, 1
Equals2
Not
If loc16a6
Push 20
Return
loc16a6:Push register1, 2
Equals2
Not
If loc16c3
Push 30
Return
loc16c3:Push register1, 3
Equals2
Not
If loc16e0
Push 40
Return
loc16e0:Push register1, 4
Equals2
Not
If loc16fd
Push 50
Return
loc16fd:Push 0
Return
}
DefineFunction2 "probe_eq_same_type", 0, 3, false, false, true, false, true, false, true, false, false {
Push 42
StoreRegister 2
Pop
Push false
StoreRegister 1
Pop
Push register2, 42
Equals2
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_strict_eq_same", 0, 3, false, false, true, false, true, false, true, false, false {
Push 42
StoreRegister 2
Pop
Push false
StoreRegister 1
Pop
Push register2, 42
StrictEquals
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_eq_cross_type", 0, 3, false, false, true, false, true, false, true, false, false {
Push "42"
StoreRegister 2
Pop
Push false
StoreRegister 1
Pop
Push register2, 42
Equals2
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_strict_eq_cross", 0, 3, false, false, true, false, true, false, true, false, false {
Push "42"
StoreRegister 2
Pop
Push false
StoreRegister 1
Pop
Push register2, 42
StrictEquals
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction "_ProbeCtor0", 0 {
}
DefineFunction2 "_ProbeCtor1", 0, 2, false, false, true, false, true, false, false, true, false {
Push register1, "x", 1
SetMember
}
DefineFunction2 "probe_new_empty", 0, 2, false, false, true, false, true, false, true, false, false {
Push 0, "_ProbeCtor0"
NewObject
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_new_simple", 0, 2, false, false, true, false, true, false, true, false, false {
Push 0, "_ProbeCtor1"
NewObject
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_add_int", 0, 3, false, false, true, false, true, false, true, false, false {
Push 7
StoreRegister 2
Pop
Push 0
StoreRegister 1
Pop
Push register2, 1
Add2
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_add_float", 0, 3, false, false, true, false, true, false, true, false, false {
Push 3.14
StoreRegister 2
Pop
Push 0
StoreRegister 1
Pop
Push register2, 0.5
Add2
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_negate", 0, 3, false, false, true, false, true, false, true, false, false {
Push 7
StoreRegister 2
Pop
Push 0
StoreRegister 1
Pop
Push 0, register2
Subtract
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_incr_post", 0, 3, false, false, true, false, true, false, true, false, false {
Push 0
StoreRegister 2
Pop
Push 0
StoreRegister 1
Pop
Push register2, register2
Increment
StoreRegister 2
Pop
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction "probe_closure_factory", 0 {
Push "captured", 42
DefineLocal
DefineFunction "", 0 {
Push "captured"
GetVariable
Return
}
Return
}
DefineFunction2 "probe_deep_closure_factory", 0, 2, false, false, true, false, true, false, true, false, false {
Push "outer", 100
DefineLocal
DefineFunction "", 0 {
Push "mid", "outer"
GetVariable
Push 1
Add2
DefineLocal
DefineFunction "", 0 {
Push "mid"
GetVariable
Return
}
Return
}
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_arguments_length", 0, 2, false, false, true, false, false, true, true, false, false {
Push register1, "length"
GetMember
Return
}
DefineFunction2 "probe_arguments_read", 0, 2, false, false, true, false, false, true, true, false, false {
Push register1, 0
GetMember
ToNumber
Return
}
DefineFunction2 "probe_arr_local_read", 0, 4, false, false, true, false, true, false, true, false, false {
Push 50, 40, 30, 20, 10, 5
InitArray
StoreRegister 2
Pop
Push 2
StoreRegister 3
Pop
Push 0
StoreRegister 1
Pop
Push register2, register3
GetMember
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_arr_global_read", 0, 3, false, false, true, false, true, false, true, false, false {
Push 50
StoreRegister 2
Pop
Push 0
StoreRegister 1
Pop
Push "_gArr100"
GetVariable
Push register2
GetMember
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction "probe_with_block", 0 {
Push "b", 0
DefineLocal
Push "_gObj"
GetVariable
With {
Push "b", "x"
GetVariable
SetVariable
}
Push "b"
GetVariable
Return
}
DefineFunction2 "probe_try_noexcept", 0, 3, false, false, true, false, true, false, true, false, false {
Push 1
StoreRegister 2
Pop
Push 0
StoreRegister 1
Pop
Try "e" {
Push register2
StoreRegister 1
Pop
}
Catch {
Push register1
Return
}
DefineFunction2 "probe_try_except", 0, 5, false, false, true, false, true, false, true, false, false {
Push 1
StoreRegister 2
Pop
Push 0
StoreRegister 1
Pop
Push "message", "x", 1
InitObject
StoreRegister 3
Pop
Try "e" {
Push register3
Throw
}
Catch {
Push register2
StoreRegister 1
Pop
}
Push register1
Return
}
DefineFunction2 "probe_delete_prop", 0, 3, false, false, true, false, true, false, true, false, false {
Push "tmp", 1, 1
InitObject
StoreRegister 1
Pop
Push register1, "tmp"
Delete
Pop
}
DefineFunction2 "probe_hasown", 0, 3, false, false, true, false, true, false, true, false, false {
Push "x", 1, 1
InitObject
StoreRegister 1
Pop
Push "x", 1, register1, "hasOwnProperty"
CallMethod
Return
}
DefineFunction2 "probe_forin", 0, 7, false, false, true, false, true, false, true, false, false {
Push "a", 1, "b", 2, "c", 3, 3
InitObject
StoreRegister 2
Pop
Push 0
StoreRegister 1
Pop
Push register2
Enumerate2
loc1e20:StoreRegister 0
Push null
Equals2
If loc1e48
Push register0
StoreRegister 3
Pop
Push register1
Increment
StoreRegister 1
Pop
Jump loc1e20
loc1e48:Push register1
Return
}
DefineFunction2 "probe_parseint", 0, 3, false, false, true, false, true, false, true, false, false {
Push "42"
StoreRegister 2
Pop
Push 0
StoreRegister 1
Pop
Push register2, 1, "parseInt"
CallFunction
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_parsefloat", 0, 3, false, false, true, false, true, false, true, false, false {
Push "3.14"
StoreRegister 2
Pop
Push 0
StoreRegister 1
Pop
Push register2, 1, "parseFloat"
CallFunction
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_string_cast", 0, 3, false, false, true, false, true, false, true, false, false {
Push 42
StoreRegister 2
Pop
Push ""
StoreRegister 1
Pop
Push register2
ToString
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_string_concat_cast", 0, 3, false, false, true, false, true, false, true, false, false {
Push 42
StoreRegister 2
Pop
Push ""
StoreRegister 1
Pop
Push "", register2
Add2
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction "_callU_empty_df1", 0 {
}
DefineFunction "_callU_decl_only_df1", 1, "d"  {
}
DefineFunction2 "_callU_empty_df2", 1, 3, false, false, true, false, true, false, true, false, false, 2, "d" {
Push register2
StoreRegister 1
Pop
}
DefineFunction "_callU_ret_df1", 0 {
Push 0
Return
}
DefineFunction2 "_callU_ret_df2", 1, 2, false, false, true, false, true, false, true, false, false, 1, "d" {
Push register1
Return
}
DefineFunction "_callU_void_nosig", 0 {
}
DefineFunction "probe_U13_decl_only", 0 {
Push 0, 1, "_callU_decl_only_df1"
CallFunction
Pop
}
DefineFunction "probe_U14_true_df2", 0 {
Push 0, 1, "_callU_empty_df2"
CallFunction
Pop
}
DefineFunction2 "probe_U15_true_df2_ret", 0, 2, false, false, true, false, true, false, true, false, false {
Push 0
StoreRegister 1
Pop
Push 0, 1, "_callU_empty_df2"
CallFunction
Pop
Push 1
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction "probe_U1_void_df1", 0 {
Push 0, "_callU_empty_df1"
CallFunction
Pop
}
DefineFunction "probe_U2_void_df2", 0 {
Push 0, 1, "_callU_empty_df2"
CallFunction
Pop
}
DefineFunction2 "probe_U3_ret_df1", 0, 2, false, false, true, false, true, false, true, false, false {
Push 0
StoreRegister 1
Pop
Push 0, "_callU_ret_df1"
CallFunction
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_U4_ret_df2", 0, 2, false, false, true, false, true, false, true, false, false {
Push 0
StoreRegister 1
Pop
Push 1, 1, "_callU_ret_df2"
CallFunction
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_U5_caller_df2_void_df1", 0, 2, false, false, true, false, true, false, true, false, false {
Push 0
StoreRegister 1
Pop
Push 0, "_callU_empty_df1"
CallFunction
Pop
Push register1
Return
}
DefineFunction "probe_U6_void_df2_1arg", 0 {
Push 0, 1, "_callU_empty_df2"
CallFunction
Pop
}
DefineFunction2 "probe_U7_ret_df2_1arg", 0, 2, false, false, true, false, true, false, true, false, false {
Push 0
StoreRegister 1
Pop
Push 1, 1, "_callU_ret_df2"
CallFunction
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction "probe_U8_void_nosig", 0 {
Push 0, "_callU_void_nosig"
CallFunction
Pop
}
DefineFunction "probe_U9_df2_0args", 0 {
Push 0, "_callU_empty_df2"
CallFunction
Pop
}
DefineFunction "probe_U10_double_void", 0 {
Push 0, "_callU_empty_df1"
CallFunction
Pop
Push 0, "_callU_empty_df1"
CallFunction
Pop
}
DefineFunction2 "probe_U11_bench_base", 0, 3, false, false, true, false, true, false, true, false, false {
Push 0
StoreRegister 1
Pop
Push 0
StoreRegister 2
Pop
Push register2
StoreRegister 1
Pop
Push register1
Return
}
DefineFunction2 "probe_U11_bench_test", 0, 2, false, false, true, false, true, false, true, false, false {
Push 0
StoreRegister 1
Pop
Push 0, 1, "_callU_empty_df2"
CallFunction
Pop
Push register1
Return
}
DefineFunction2 "probe_U12_onearg_test", 0, 3, false, false, true, false, true, false, true, false, false {
Push 0
StoreRegister 1
Pop
Push 42
StoreRegister 2
Pop
Push register2, 1, "_callU_ret_df2"
CallFunction
StoreRegister 1
Pop
Push register1
Return
}
Push "_gVar", 42
DefineLocal
Push "_gObj", "x", 42, "y", 0, 2
InitObject
DefineLocal
Push "_gObj"
GetVariable
Push "emptyMethod"
DefineFunction "", 0 {
}
SetMember
Push "_gObj"
GetVariable
Push "retMethod"
DefineFunction "", 0 {
Push 42
Return
}
SetMember
Push "_gArr100", 0
InitArray
DefineLocal
Push "_pI"
DefineLocal2
Push "_pI", 0
SetVariable
loc2514:Push "_pI"
GetVariable
Push 100
Less2
Not
If loc254e
Push "_gArr100"
GetVariable
Push "_pI"
GetVariable
Push "_pI"
GetVariable
SetMember
Push "_pI", "_pI"
GetVariable
Increment
SetVariable
Jump loc2514
loc254e:Push "=== BytecodeProbe: 运行所有探针防止 DCE ==="
Trace
Push "A-and:", 0, "probe_bit_and"
CallFunction
Add2
Trace
Push "A-or:", 0, "probe_bit_or"
CallFunction
Add2
Trace
Push "A-xor:", 0, "probe_bit_xor"
CallFunction
Add2
Trace
Push "A-not:", 0, "probe_bit_not"
CallFunction
Add2
Trace
Push "A-or0:", 0, "probe_bit_or_zero"
CallFunction
Add2
Trace
Push "A-dtil:", 0, "probe_double_tilde"
CallFunction
Add2
Trace
Push "A-lsh:", 0, "probe_lshift"
CallFunction
Add2
Trace
Push "A-rsh:", 0, "probe_rshift"
CallFunction
Add2
Trace
Push 0, "probe_nan_eq"
CallFunction
Pop
Push "B-selfne:", 0, "probe_isnan_selfne"
CallFunction
Add2
Trace
Push "B-isnan:", 0, "probe_isnan_fn"
CallFunction
Add2
Trace
Push "C-uplus:", 0, "probe_unary_plus"
CallFunction
Add2
Trace
Push "C-numcast:", 0, "probe_number_cast"
CallFunction
Add2
Trace
Push "D-cfold:", 0, "probe_const_fold"
CallFunction
Add2
Trace
Push "D-varadd:", 0, "probe_var_add"
CallFunction
Add2
Trace
Push "D-cmul:", 0, "probe_const_mul"
CallFunction
Add2
Trace
Push 0, "probe_call_void"
CallFunction
Pop
Push "E-cassign:", 0, "probe_call_assign"
CallFunction
Add2
Trace
Push 0, "probe_call_method"
CallFunction
Pop
Push "E-cmret:", 0, "probe_call_method_ret"
CallFunction
Add2
Trace
Push "E-fncall:", 0, "probe_fn_dot_call"
CallFunction
Add2
Trace
Push "F-local:", 0, "probe_local_read"
CallFunction
Add2
Trace
Push "F-global:", 0, "probe_global_read"
CallFunction
Add2
Trace
Push "F-member:", 0, "probe_member_read"
CallFunction
Add2
Trace
Push "F-bracket:", 0, "probe_bracket_read"
CallFunction
Add2
Trace
Push "G-typed:", 0, "probe_typed_local"
CallFunction
Add2
Trace
Push "G-untyped:", 0, "probe_untyped_local"
CallFunction
Add2
Trace
Push "H-strlen:", 0, "probe_str_length"
CallFunction
Add2
Trace
Push "H-arrlen:", 0, "probe_arr_length"
CallFunction
Add2
Trace
Push "H-as1len:", 0, "probe_str_length_as1"
CallFunction
Add2
Trace
Push "I-boolcast:", 0, "probe_boolean_cast"
CallFunction
Add2
Trace
Push "I-dblnot:", 0, "probe_double_not"
CallFunction
Add2
Trace
Push "J-typeof:", 0, "probe_typeof"
CallFunction
Add2
Trace
Push "K-mfloor:", 0, "probe_math_floor"
CallFunction
Add2
Trace
Push "K-cfloor:", 0, "probe_cached_floor"
CallFunction
Add2
Trace
Push "L-sw5:", 3, 1, "probe_switch_5"
CallFunction
Add2
Trace
Push "L-if5:", 3, 1, "probe_ifelse_5"
CallFunction
Add2
Trace
Push "M-eq:", 0, "probe_eq_same_type"
CallFunction
Add2
Trace
Push "M-seq:", 0, "probe_strict_eq_same"
CallFunction
Add2
Trace
Push "M-eqx:", 0, "probe_eq_cross_type"
CallFunction
Add2
Trace
Push "M-seqx:", 0, "probe_strict_eq_cross"
CallFunction
Add2
Trace
Push "N-new0:", 0, "probe_new_empty"
CallFunction
Add2
Trace
Push "N-new1:", 0, "probe_new_simple"
CallFunction
Add2
Trace
Push "O-addi:", 0, "probe_add_int"
CallFunction
Add2
Trace
Push "O-addf:", 0, "probe_add_float"
CallFunction
Add2
Trace
Push "O-neg:", 0, "probe_negate"
CallFunction
Add2
Trace
Push "O-post:", 0, "probe_incr_post"
CallFunction
Add2
Trace
Push "_pClosure", 0, "probe_closure_factory"
CallFunction
DefineLocal
Push "P-closure:", 0, "_pClosure"
CallFunction
Add2
Trace
Push "P-arglen:", 0, "probe_arguments_length"
CallFunction
Add2
Trace
Push "P-argread:", 99, 1, "probe_arguments_read"
CallFunction
Add2
Trace
Push "Q-arrlocal:", 0, "probe_arr_local_read"
CallFunction
Add2
Trace
Push "Q-arrglobal:", 0, "probe_arr_global_read"
CallFunction
Add2
Trace
Push "R-with:", 0, "probe_with_block"
CallFunction
Add2
Trace
Push "R-tryok:", 0, "probe_try_noexcept"
CallFunction
Add2
Trace
Push "R-tryex:", 0, "probe_try_except"
CallFunction
Add2
Trace
Push 0, "probe_delete_prop"
CallFunction
Pop
Push "S-hasown:", 0, "probe_hasown"
CallFunction
Add2
Trace
Push "S-forin:", 0, "probe_forin"
CallFunction
Add2
Trace
Push "T-pint:", 0, "probe_parseint"
CallFunction
Add2
Trace
Push "T-pfloat:", 0, "probe_parsefloat"
CallFunction
Add2
Trace
Push "T-strcast:", 0, "probe_string_cast"
CallFunction
Add2
Trace
Push "T-strconcat:", 0, "probe_string_concat_cast"
CallFunction
Add2
Trace
Push "=== 探针组 U: call_empty 异常诊断 ==="
Trace
Push 0, "probe_U1_void_df1"
CallFunction
Pop
Push 0, "probe_U2_void_df2"
CallFunction
Pop
Push "U3-ret_df1:", 0, "probe_U3_ret_df1"
CallFunction
Add2
Trace
Push "U4-ret_df2:", 0, "probe_U4_ret_df2"
CallFunction
Add2
Trace
Push "U5-caller_df2:", 0, "probe_U5_caller_df2_void_df1"
CallFunction
Add2
Trace
Push 0, "probe_U6_void_df2_1arg"
CallFunction
Pop
Push "U7-ret_df2_1arg:", 0, "probe_U7_ret_df2_1arg"
CallFunction
Add2
Trace
Push 0, "probe_U8_void_nosig"
CallFunction
Pop
Push 0, "probe_U9_df2_0args"
CallFunction
Pop
Push 0, "probe_U10_double_void"
CallFunction
Pop
Push "U11-base:", 0, "probe_U11_bench_base"
CallFunction
Add2
Trace
Push "U11-test:", 0, "probe_U11_bench_test"
CallFunction
Add2
Trace
Push "U12-onearg:", 0, "probe_U12_onearg_test"
CallFunction
Add2
Trace
Push 0, "probe_U13_decl_only"
CallFunction
Pop
Push 0, "probe_U14_true_df2"
CallFunction
Pop
Push "U15-true_df2_ret:", 0, "probe_U15_true_df2_ret"
CallFunction
Add2
Trace
Push "=== BytecodeProbe 完成 ==="
Trace