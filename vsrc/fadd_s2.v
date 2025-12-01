module fadd_s2#(
    parameter  EXPWIDTH     =   5,
    parameter  PRECISION    =   4
    // 当作为加法树时，EXPWIDTH=5, PRECISION=4
    // 当作为累加器时，EXPWIDTH=8, PRECISION=14
    /*该模块的功能为：
    1. 对第一阶段结果进行舍入处理
    2. 处理溢出情况
    3. 生成最终规格化结果
    4. 输出异常标志*/
)(
    input                                   clk,//时钟信号 
    input                                   rst_n,//复位信号，低有效
    input                                   en_i, //控制信号   
    // 输入数据信号
    input                                   in_far_sign_i,  //far path 符号位
    input [EXPWIDTH - 1:0]                  in_far_exp_i,   //far path 指数位
    input [PRECISION + 3 - 1:0]             in_far_sig_i,   //far path 尾数（带保护位）
    input                                   in_near_sign_i, // near path 符号位
    input [EXPWIDTH - 1:0]                  in_near_exp_i,  // near path 指数位
    input [PRECISION + 3 - 1:0]             in_near_sig_i,  // near path 尾数
    // 路径选择信号
    input                                   in_sel_far_path_i,//路径选择信号（1 表示选择far path）
    // 特殊情况与异常输入
    input [2:0]                             rm_i,//舍入模式（IEEE 754）
    input                                   in_far_mul_of_i,//far path 乘法溢出标志
    input                                   in_near_sig_is_zero_i,//near path 尾数为零标志
    input                                   in_special_case_valid_i,//结果是否有效
    input                                   in_special_case_inv_i,//无效操作标志
    input                                   in_special_case_nan_i,//结果为 NaN 标志
    // 输出数据和标志信号
    output [EXPWIDTH + PRECISION - 1:0]     out_result_o,//浮点加法结果
    output [4:0]                            out_fflags_o,//浮点异常标志(NV, DZ, OF, UF, NX)
    output                                  out_far_uf_o,//far path 下溢标志
    output                                  out_near_of_o//near path 溢出标志
);





endmodule