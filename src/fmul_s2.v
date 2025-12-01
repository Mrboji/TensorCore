///////////////////////////////////////////
//fmul_s2：
//仅透传，没有任何处理，符合“传递第一阶段结果”的功能，但未增加额外标志/校验。
///////////////////////////////////////////
`timescale 1ns/1ps
`default_nettype none

`include "tensor_core_params.svh"

module fmul_s2 #(
  parameter EXPWIDTH  = `TC_EXPWIDTH,
  parameter PRECISION = `TC_PRECISION
) (
  input  wire                         in_special_case_valid_i, // 特殊路径有效
  input  wire                         in_special_case_nan_i,   // NaN 标志
  input  wire                         in_special_case_inf_i,   // Inf 标志
  input  wire                         in_special_case_inv_i,   // 无效操作标志
  input  wire                         in_special_case_haszero_i, // 含零操作数
  input  wire                         in_early_overflow_i,     // 早溢出
  input  wire                         in_may_be_subnormal_i,   // 可能非规格化
  input  wire [2:0]                   in_rm_i,                 // 舍入模式
  input  wire                         in_prod_sign_i,          // 乘积符号
  input  wire [EXPWIDTH:0]            in_shift_amt_i,          // 移位量
  input  wire [EXPWIDTH:0]            in_exp_shifted_i,        // 指数调整值
  input  wire [PRECISION*2-1:0]       prod_i,                  // 尾数乘积
  output wire                         in_special_case_valid_o, // 特殊路径有效输出
  output wire                         in_special_case_nan_o,   // NaN 标志输出
  output wire                         in_special_case_inf_o,   // Inf 标志输出
  output wire                         in_special_case_inv_o,   // 无效操作标志输出
  output wire                         in_special_case_haszero_o, // 含零操作数输出
  output wire                         in_early_overflow_o,     // 早溢出输出
  output wire                         in_may_be_subnormal_o,   // 可能非规格化输出
  output wire [2:0]                   in_rm_o,                 // 舍入模式输出
  output wire                         in_prod_sign_o,          // 乘积符号输出
  output wire [EXPWIDTH:0]            in_shift_amt_o,          // 移位量输出
  output wire [EXPWIDTH:0]            in_exp_shifted_o,        // 指数调整输出
  output wire [PRECISION*2-1:0]       prod_o                   // 尾数乘积输出
);

  assign in_special_case_valid_o   = in_special_case_valid_i;
  assign in_special_case_nan_o     = in_special_case_nan_i;
  assign in_special_case_inf_o     = in_special_case_inf_i;
  assign in_special_case_inv_o     = in_special_case_inv_i;
  assign in_special_case_haszero_o = in_special_case_haszero_i;
  assign in_early_overflow_o       = in_early_overflow_i;
  assign in_may_be_subnormal_o     = in_may_be_subnormal_i;
  assign in_rm_o                   = in_rm_i;
  assign in_prod_sign_o            = in_prod_sign_i;
  assign in_shift_amt_o            = in_shift_amt_i;
  assign in_exp_shifted_o          = in_exp_shifted_i;
  assign prod_o                    = prod_i;

endmodule

`default_nettype wire
