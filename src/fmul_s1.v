/////////////////////////////////////////////////
//输入统一 FP9：代码按 FP9 拆符号/指数/尾数，偏置取 15，次正规隐藏位取 0，规格化隐藏位取 1，这点符合“进入乘法前已统一成 FP9”的前提
//
//特殊值处理：检测 NaN/Inf/零/次正规并生成 special_case_* 标志；NV 在 Inf×0 时置位。文档中异常 NV/OF/UF/DZ/NX 需完整支持，当前 DZ/NX 未覆盖，OF/UF 也未在 fmul_s1 设置。
//////////////////////////////////////////////


////////////////////////////////////
//文档中异常 NV/OF/UF/DZ/NX 需完整支持，当前 DZ/NX 未覆盖，OF/UF 也未在 fmul_s1 设置。
//FP22 的具体格式（指数宽度、尾数宽度、偏置）以及 FP9 → FP22、FP22 → FP32 的精确转换规则。
//异常标志触发条件的详细定义（特别是 DZ、NX、OF/UF 在乘法链路中的判定）。
////////////////////////////////////
`timescale 1ns/1ps
`default_nettype none

`include "tensor_core_params.svh"

module fmul_s1 #(
  parameter EXPWIDTH  = `TC_EXPWIDTH,
  parameter PRECISION = `TC_PRECISION
) (
  input  wire [EXPWIDTH+PRECISION-1:0] s_axis_tdata_a, // 操作数 A
  input  wire [EXPWIDTH+PRECISION-1:0] s_axis_tdata_b, // 操作数 B
  input  wire [2:0]                    rm_i,           // 舍入模式
  output wire                          out_special_case_valid_o, // 特殊路径有效
  output wire                          out_special_case_nan_o,   // NaN 标志
  output wire                          out_special_case_inf_o,   // Inf 标志
  output wire                          out_special_case_inv_o,   // 无效操作标志
  output wire                          out_special_case_haszero_o, // 含零操作数
  output wire                          out_early_overflow_o,     // 早溢出
  output wire                          out_may_be_subnormal_o,   // 可能非规格化
  output wire                          out_prod_sign_o,          // 乘积符号
  output wire [EXPWIDTH:0]             out_shift_amt_o,          // 尾数移位量
  output wire [EXPWIDTH:0]             out_exp_shifted_o,        // 指数调整值
  output wire [2:0]                    out_rm_o                  // 舍入模式透传
);

  localparam BIAS = (1 << (EXPWIDTH-1)) - 1; // 15 for EXPWIDTH=5

  wire s_a = s_axis_tdata_a[EXPWIDTH+PRECISION-1];
  wire s_b = s_axis_tdata_b[EXPWIDTH+PRECISION-1];
  wire [EXPWIDTH-1:0] e_a = s_axis_tdata_a[EXPWIDTH+PRECISION-2:PRECISION];
  wire [EXPWIDTH-1:0] e_b = s_axis_tdata_b[EXPWIDTH+PRECISION-2:PRECISION];
  wire [PRECISION-1:0] f_a = s_axis_tdata_a[PRECISION-1:0];
  wire [PRECISION-1:0] f_b = s_axis_tdata_b[PRECISION-1:0];

  wire a_is_zero = (e_a == 0) && (f_a == 0);
  wire b_is_zero = (e_b == 0) && (f_b == 0);
  wire a_is_inf  = (e_a == {EXPWIDTH{1'b1}}) && (f_a == 0);
  wire b_is_inf  = (e_b == {EXPWIDTH{1'b1}}) && (f_b == 0);
  wire a_is_nan  = (e_a == {EXPWIDTH{1'b1}}) && (f_a != 0);
  wire b_is_nan  = (e_b == {EXPWIDTH{1'b1}}) && (f_b != 0);

  wire a_is_sub  = (e_a == 0) && (f_a != 0);
  wire b_is_sub  = (e_b == 0) && (f_b != 0);

  wire prod_sign = s_a ^ s_b;

  // 生成隐藏位（规格化为1，非规=0）
  wire [PRECISION:0] m_a = a_is_zero ? 0 : {~a_is_sub, f_a};
  wire [PRECISION:0] m_b = b_is_zero ? 0 : {~b_is_sub, f_b};

  // 尾数相乘交给下一级（naivemultiplier 使用 4 bit）
  assign out_special_case_valid_o   = a_is_nan | b_is_nan | a_is_inf | b_is_inf | a_is_zero | b_is_zero;
  assign out_special_case_nan_o     = a_is_nan | b_is_nan | (a_is_inf & b_is_zero) | (b_is_inf & a_is_zero);
  assign out_special_case_inf_o     = (a_is_inf & ~b_is_zero & ~b_is_nan) | (b_is_inf & ~a_is_zero & ~a_is_nan);
  assign out_special_case_inv_o     = (a_is_inf & b_is_zero) | (b_is_inf & a_is_zero);
  assign out_special_case_haszero_o = a_is_zero | b_is_zero;
  assign out_early_overflow_o       = 1'b0;
  assign out_may_be_subnormal_o     = a_is_sub | b_is_sub;
  assign out_prod_sign_o            = prod_sign;
  assign out_shift_amt_o            = { (EXPWIDTH+1){1'b0} };
  assign out_exp_shifted_o          = (e_a==0 ? 1 : e_a) + (e_b==0 ? 1 : e_b) - BIAS;
  assign out_rm_o                   = rm_i;

endmodule

`default_nettype wire
