////////////////////////////////////
//fmul_s3：
//做了简单规格化（左移至最高位），调整指数，截取尾数并生成 to_fadd_*，有 OF/UF 粗略设置。
//舍入/GRS 未按 FP22 精确实现，NX/DZ 未处理，尾数截取未使用 guard/round/sticky 细化。
//输出 result_o 直接拼 sign|exp|sig，未严格对齐 FP22/FP32 格式。
////////////////////////////////////////////////////


`timescale 1ns/1ps
`default_nettype none

`include "tensor_core_params.svh"

module fmul_s3 #(
  parameter EXPWIDTH  = `TC_EXPWIDTH,
  parameter PRECISION = `TC_PRECISION
) (
  input  wire [PRECISION*2-1:0] in_prod_i,              // 尾数乘积
  input  wire                   in_prod_sign_i,         // 乘积符号
  input  wire [EXPWIDTH:0]      in_shift_amt_i,         // 移位量
  input  wire [EXPWIDTH:0]      in_exp_shifted_i,       // 指数调整值
  input  wire                   in_special_case_valid_i,// 特殊路径有效
  input  wire                   in_special_case_nan_i,  // NaN 标志
  input  wire                   in_special_case_inf_i,  // Inf 标志
  input  wire                   in_special_case_inv_i,  // 无效操作标志
  input  wire                   in_special_case_haszero_i, // 含零操作数
  input  wire                   in_early_overflow_i,    // 早溢出
  input  wire                   in_may_be_subnormal_i,  // 可能非规格化
  input  wire [2:0]             in_rm_i,                // 舍入模式
  output wire [EXPWIDTH+PRECISION-1:0] result_o,        // 规格化结果
  output wire [4:0]             fflags_o,               // 异常标志
  output wire                   to_fadd_fp_prod_sign_o, // 输出给加法器的符号
  output wire [EXPWIDTH-1:0]    to_fadd_fp_prod_exp_o,  // 输出给加法器的指数
  output wire [2*PRECISION-2:0] to_fadd_fp_prod_sig_o,  // 输出给加法器的尾数
  output wire                   to_fadd_is_nan_o,       // NaN 标志到加法器
  output wire                   to_fadd_is_inf_o,       // Inf 标志到加法器
  output wire                   to_fadd_is_inv_o,       // 无效操作标志到加法器
  output wire                   to_fadd_overflow_o      // 溢出标志到加法器
);

  localparam BIAS = (1 << (EXPWIDTH-1)) - 1;
  reg [EXPWIDTH-1:0] exp_res;
  reg [PRECISION-1:0] sig_res;
  reg [4:0] flags;
  reg [2*PRECISION-2:0] sig_to_add;

  reg [EXPWIDTH:0] exp_work;
  reg [PRECISION*2-1:0] mant_work;
  integer shift;

  always @(*) begin
    // 默认
    flags = 5'b0;
    exp_res = 0;
    sig_res = 0;
    sig_to_add = 0;
    exp_work = in_exp_shifted_i;
    mant_work = in_prod_i;

    if (in_special_case_nan_i) begin
      flags[4] = 1'b1; // NV
      exp_res = {EXPWIDTH{1'b1}};
      sig_res = {PRECISION{1'b1}};
    end else if (in_special_case_inf_i) begin
      flags[1] = 1'b1; // OF
      exp_res = {EXPWIDTH{1'b1}};
      sig_res = {PRECISION{1'b0}};
    end else begin
      // 规格化：确保最高位位于 bit (PRECISION*2-1)
      shift = 0;
      while (shift < PRECISION*2 && mant_work[PRECISION*2-1-shift]==0) begin
        shift = shift + 1;
      end
      exp_work = exp_work - shift;
      mant_work = mant_work << shift;

      // 截取尾数（含保护位）
      sig_res = mant_work[PRECISION*2-1 -: PRECISION];
      sig_to_add = mant_work[PRECISION*2-2:0];

      // 溢出/下溢
      if (exp_work[EXPWIDTH]) begin
        flags[1] = 1'b1; // OF
        exp_res = {EXPWIDTH{1'b1}};
        sig_res = 0;
      end else if (exp_work == 0) begin
        flags[2] = 1'b1; // UF
        exp_res = 0;
        sig_res = 0;
      end else begin
        exp_res = exp_work[EXPWIDTH-1:0];
      end
    end
  end

  assign result_o               = {in_prod_sign_i, exp_res, sig_res[PRECISION-2:0]};
  assign fflags_o               = flags;
  assign to_fadd_fp_prod_sign_o = in_prod_sign_i;
  assign to_fadd_fp_prod_exp_o  = exp_res;
  assign to_fadd_fp_prod_sig_o  = sig_to_add;
  assign to_fadd_is_nan_o       = in_special_case_nan_i;
  assign to_fadd_is_inf_o       = in_special_case_inf_i;
  assign to_fadd_is_inv_o       = in_special_case_inv_i;
  assign to_fadd_overflow_o     = flags[1];

endmodule

`default_nettype wire
