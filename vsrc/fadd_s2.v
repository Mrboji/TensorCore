// NOTE:
//   1) 文档中位宽有一些前后不一致，这里做了如下假设：
//      - s1 输出的 far/near 尾数位宽 = OUTPC + 3
//      - s2 输入 in_far_sig_i / in_near_sig_i 也使用 OUTPC + 3
//      - 最终结果 out_result_o = {sign, exponent, fraction}
//        宽度 = 1 + EXPWIDTH + OUTPC
//   2) 这里的 GRS（guard / sticky）编码是假设：
//        in_*_sig_i[OUTPC+2 : 3]  -> 主尾数 (OUTPC bits)
//        in_*_sig_i[2]           -> guard bit
//        in_*_sig_i[1:0]         -> 其它保留位合并成 sticky
//      如果在 s1 中采用了不同的编码，只需要在本模块中
//      重新解析 guard / sticky 即可。
// -------------------------------------------------------------
module fadd_s2#(
    parameter  EXPWIDTH     =   5,
    parameter  PRECISION    =   4,
    // OUTPC: 有效输出尾数位数（与 s1 的 OUTPC 保持一致）
    parameter OUTPC     = PRECISION
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
    input                                   in_special_case_iv_i,//无效操作标志
    input                                   in_special_case_nan_i,//结果为 NaN 标志
    // 输出数据和标志信号
    //out_result_o还有符号位，因此位宽需要修正为1+EXPWIDTH+PRECISION
    output reg [EXPWIDTH + PRECISION:0]     out_result_o,//浮点加法结果
    output reg [4:0]                        out_fflags_o,//浮点异常标志(NV, DZ, OF, UF, NX)
    output reg                              out_far_uf_o,//far path 下溢标志
    output reg                              out_near_of_o//near path 溢出标志
);

    // 定义一些局部参数
    localparam INTWIDTH = OUTPC;                  // 有效尾数位数
    localparam RESWIDTH = 1 + EXPWIDTH + OUTPC;   // 输出总宽度（sign + exp + frac）

    // fflags bit index: {NV, OF, UF, DZ, NX}
    localparam IDX_NV = 4;
    localparam IDX_OF = 3;
    localparam IDX_UF = 2;
    localparam IDX_DZ = 1;
    localparam IDX_NX = 0;

    // 全部为1用作 Inf/NaN 的指数
    localparam [EXPWIDTH-1:0] EXP_MAX = {EXPWIDTH{1'b1}};

    // ------------------------------
    // 1. 选择 far / near 路径的预处理结果
    // ------------------------------
    wire sel_far = in_sel_far_path_i;

    wire                     pre_sign = sel_far ? in_far_sign_i : in_near_sign_i;
    wire [EXPWIDTH-1:0]      pre_exp  = sel_far ? in_far_exp_i  : in_near_exp_i;
    wire [OUTPC+2:0]         pre_sig  = sel_far ? in_far_sig_i  : in_near_sig_i;

    // 主尾数、guard、sticky 的解析
    wire [OUTPC-1:0] mant_trunc = pre_sig[OUTPC+2 : 3];      // OUTPC bits
    wire             guard_bit  = pre_sig[2];
    wire             sticky_bit = |pre_sig[1:0];

    wire             any_round_bits = guard_bit | sticky_bit;

    // ------------------------------
    // 2. 舍入增量的计算（inc = 是否 +1）
    // ------------------------------
    reg inc_round;

    always @(*) begin
        case (rm_i)
            3'b000: begin
                // Round to nearest, ties to even
                // 需要 guard = 1，且 (sticky = 1 或 LSB(mant) = 1)
                inc_round = guard_bit & (sticky_bit | mant_trunc[0]);
            end

            3'b001: begin
                // Toward zero
                inc_round = 1'b0;
            end

            3'b010: begin
                // Toward +infinity
                inc_round = (~pre_sign) & any_round_bits;
            end

            3'b011: begin
                // Toward -infinity
                inc_round = (pre_sign) & any_round_bits;
            end

            default: begin
                // 默认也使用 round-to-nearest-even
                inc_round = guard_bit & (sticky_bit | mant_trunc[0]);
            end
        endcase
    end

    // ------------------------------
    // 3. 尾数舍入 & 指数调整
    // ------------------------------
    reg [OUTPC:0]   mant_ext_rounded;  // OUTPC+1 bits
    reg [OUTPC-1:0] mant_final;
    reg [EXPWIDTH-1:0] exp_final;

    reg flag_overflow;
    reg flag_underflow;

    always @(*) begin
        // 默认值
        mant_ext_rounded = {1'b0, mant_trunc} + {{OUTPC{1'b0}}, inc_round};
        //默认是在原尾数前加一个0，便于计算进位。加上的进位信号为尾数位个0+计算出来的是否舍入值

        flag_overflow    = 1'b0;
        flag_underflow   = 1'b0;

        // 溢出：尾数进位
        if (mant_ext_rounded[OUTPC]) begin
            // 尾数向右移 1 位并指数 +1
            mant_final = mant_ext_rounded[OUTPC : 1];

            // 指数 +1，检查是否溢出到 INF/NaN 范围
            if (pre_exp == EXP_MAX - 1'b1) begin
                // 进一步 +1 会到 EXP_MAX，视作 Overflow -> Inf
                exp_final     = EXP_MAX;
                mant_final    = {OUTPC{1'b0}}; // 表示 Inf
                flag_overflow = 1'b1;
            end
            else begin
                exp_final = pre_exp + 1'b1;
            end
        end
        else begin
            // 尾数无进位，仅复制
            mant_final = mant_ext_rounded[OUTPC-1 : 0];
            exp_final  = pre_exp;

            // 非严格的 underflow 判定（当指数已经在最小附近且仍然发生了舍入）
            if (pre_exp == {EXPWIDTH{1'b0}} && any_round_bits && (mant_trunc == {OUTPC{1'b0}})) begin
                flag_underflow = 1'b1;
            end
        end
    end

    // ------------------------------
    // 4. 特殊情况（NaN、Invalid 等）覆盖
    // ------------------------------
    reg [RESWIDTH-1:0] result_normal;
    reg [RESWIDTH-1:0] result_special;
    reg                 use_special;

    always @(*) begin
        // 正常路径结果
        result_normal = {pre_sign, exp_final, mant_final};

        // 特殊路径（NaN / Invalid）的缺省模式：
        //   - NaN / Invalid -> sign = 0, exp = EXP_MAX, frac = 1 << (OUTPC-1)
        result_special = {1'b0, EXP_MAX, {1'b1, {OUTPC-1{1'b0}}}};

        use_special = in_special_case_valid_i &
                      (in_special_case_nan_i | in_special_case_iv_i);
    end

    // ------------------------------
    // 5. fflags 汇总
    // ------------------------------
    reg [RESWIDTH-1:0] result_comb;
    reg [4:0]          fflags_comb;
    reg                far_uf_comb, near_of_comb;

    always @(*) begin
        result_comb = use_special ? result_special : result_normal;

        fflags_comb = 5'b0;
        // NV: Invalid operation
        fflags_comb[IDX_NV] = in_special_case_iv_i;
        // OF: overflow
        fflags_comb[IDX_OF] = flag_overflow | (sel_far ? in_far_mul_of_i : 1'b0);
        // UF: underflow
        fflags_comb[IDX_UF] = flag_underflow;
        // DZ: divide by zero（加法器通常不会产生，这里直接为 0）
        fflags_comb[IDX_DZ] = 1'b0;
        // NX: inexact（发生了舍入或者 overflow / underflow）
        fflags_comb[IDX_NX] = any_round_bits | flag_overflow | flag_underflow;
        // 额外的路径相关标志（简单地由当前选择的路径 & OF/UF 推导）
        far_uf_comb  = sel_far  ? flag_underflow : 1'b0;
        // near path 的“溢出”这里简单映射为 flag_overflow 且选择 near
        near_of_comb = (~sel_far) ? flag_overflow : 1'b0;
    end

    // ------------------------------
    // 6. 输出结果
    // ------------------------------
     always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_result_o  <= {RESWIDTH{1'b0}};
            out_fflags_o  <= 5'b0;
            out_far_uf_o  <= 1'b0;
            out_near_of_o <= 1'b0;
        end
        else if (en_i) begin
            // 更新流水寄存器
            out_result_o  <= result_comb;
            out_fflags_o  <= fflags_comb;
            out_far_uf_o  <= far_uf_comb;
            out_near_of_o <= near_of_comb;
        end
    end

endmodule