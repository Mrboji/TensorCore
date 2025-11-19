module fmul_s3 #(
  parameter integer EXPWIDTH    = 5,                 // 指数位宽（fp9）
  parameter integer PRECISION   = 4,                 // 精度，尾数位宽，包括隐含位
)
(
    input [PRECISION * 2 - 1 : 0]   in_prod_i,
    input                           in_prod_sign_i,
    input [EXPWIDTH : 0]            in_shift_amt_i,
    input [EXPWIDTH : 0]            in_exp_shifted_i,

    input                           in_special_case_valid_i,
    input                           in_special_case_nan_i,
    input                           in_special_case_inf_i,
    input                           in_special_case_inv_i,
    input                           in_special_case_haszero_i,
    input                           in_early_overflow_i,
    input                           in_may_be_subnormal_i,

    input                           in_rm_i,

    output [EXPWIDTH + PRECISION]   result_o,
    output [ 5 : 0 ]                fflags_o,

    output                          to_fadd_fp_prod_sign_o,
    output [EXPWIDTH - 1 : 0]       to_fadd_fp_prod_exp_o,
    output [PRECISION*2 - 1:0]      to_fadd_fp_prod_sig_o,
    output                          to_fadd_is_nan_o,
    output                          to_fadd_is_inf_o,
    output                          to_fadd_is_inv_o,
    output                          to_fadd_overflow_o,

)

endmodule