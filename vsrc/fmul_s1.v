module fmul_s1 #(
  parameter integer EXPWIDTH    = 5,                 // 指数位宽（fp9e5m3）
  parameter integer PRECISION   = 4,                 // 精度，尾数位宽，包括隐含位
  parameter integer M           = PRECISION-1,            // 纯尾数位宽（不含 sign）e5m3
  parameter integer BIAS        = (1<<(EXPWIDTH-1))-1    // FP9(e5m3) -> 15
)(
// ===== input =====
  input  wire [EXPWIDTH+PRECISION-1:0] s_axis_tdata_a,     // A 元素input（位宽 5+4）
  input  wire [EXPWIDTH+PRECISION-1:0] s_axis_tdata_b,     // B 元素input（位宽 5+4）


  input  wire [2:0]           rm_i,               // 舍入（IEEE754）

// ===== 特殊/异常输出 =====
  output reg                  out_special_case_valid_o, // 特殊值标志是否有效
  output reg                  out_special_case_nan_o,   // 结果是否为 NaN
  output reg                  out_special_case_inf_o,   // 结果是否为 ±Inf
  output reg                  out_special_case_inv_o,   // 是否为无效操作（invalid）
  output reg                  out_special_case_haszero_o, // 是否存在零操作数
  output reg                  out_early_overflow_o,     // 是否发生早期溢出（指数预和阶段）
  output reg                  out_may_be_subnormal_o,   // 可能为非规格化数

// ===== 乘法基础数据 =====
  output reg                  out_prod_sign_o,     // 乘积符号位

// ===== 规范化准备量 =====
  output reg  [EXPWIDTH:0]        out_shift_amt_o,     // 最终移位量（乘法路径通常为 0/1，先给占位位宽 5+1）
  output reg  [EXPWIDTH:0]        out_exp_shifted_o,   // 移位后指数（此级先给指数预和）

// =====  舍入  =====
  output reg  [2:0]           out_rm_o
);


// ---------------- 解包 A/B：高 EXPWIDTH 位为指数，低 PRECISION 位={sign, frac[M-1:0]}
  wire                sign_a = s_axis_tdata_a[PRECISION-1];  //符号位
  wire                sign_b = s_axis_tdata_b[PRECISION-1];

  wire [EXPWIDTH-1:0] exp_a  = s_axis_tdata_a[EXPWIDTH+PRECISION-1 : PRECISION];  //指数e5
  wire [EXPWIDTH-1:0] exp_b  = s_axis_tdata_b[EXPWIDTH+PRECISION-1 : PRECISION];

  wire [M-1:0]        frac_a = s_axis_tdata_a[M-1:0];  //m3
  wire [M-1:0]        frac_b = s_axis_tdata_b[M-1:0];

// ---------------- 分类判断
  wire exp_a_all1 = &exp_a;//x11111xxx
  wire exp_b_all1 = &exp_b;

  wire a_is_zero  = (exp_a == {EXPWIDTH{1'b0}}) && (frac_a == {M{1'b0}});//x00000 000
  wire b_is_zero  = (exp_b == {EXPWIDTH{1'b0}}) && (frac_b == {M{1'b0}});

  wire a_is_subn  = (exp_a == {EXPWIDTH{1'b0}}) && (frac_a != {M{1'b0}});//
  wire b_is_subn  = (exp_b == {EXPWIDTH{1'b0}}) && (frac_b != {M{1'b0}});

  wire a_is_inf   =  exp_a_all1 && (frac_a == {M{1'b0}}); 
  wire b_is_inf   =  exp_b_all1 && (frac_b == {M{1'b0}});

  wire a_is_nan   =  exp_a_all1 && (frac_a != {M{1'b0}});
  wire b_is_nan   =  exp_b_all1 && (frac_b != {M{1'b0}});










endmodule

`default_nettype wire