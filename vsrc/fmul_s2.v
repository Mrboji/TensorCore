module fmul_s1 #(
  parameter integer EXPWIDTH    = 5,                 // 指数位宽（fp9）
  parameter integer PRECISION   = 4,                 // 精度，尾数位宽，包括隐含位
  parameter integer M           = PRECISION-1,            // 纯尾数位宽（不含 sign）e5m3
  parameter integer BIAS        = (1<<(EXPWIDTH-1))-1    // FP9(e5m3) -> 15
)(

  inout in_special_case_valid_i,
  inout in_special_case_nan_i,
  inout in_special_case_inf_i,
  inout in_special_case_inv_i,
  inout in_special_case_haszero_i,

  inout in_early_overflow_i,
  inout in_may_be_subnormal_i,

  inout in_rm_i,

  inout in_prod_sign_i,
  inout [EXPWIDTH:0]in_shift_amt_i,
  inout [EXPWIDTH:0]in_exp_shifted_i,

  inout [PRECISION+PRECISION-1:0]prod_i
);


endmodule

`default_nettype wire