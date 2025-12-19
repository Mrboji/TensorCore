module tc_add #(
    parameter EXPWIDTH  = 5,
    parameter PRECISION = 8,
    parameter OUTPC     = 4
    //当作为加法树时，EXPWIDTH=5, PRECISION=8, OUTPC=4
    //当作为累加器时，EXPWIDTH=8, PRECISION=28, OUTPC=14
)(
    input                           clk,       //时钟信号
    input                           rst_n,     //复位信号，低有效
    input                           en_i,      //控制信号

    input   [2:0]                   rm_i,      //舍入模式（IEEE 754）

    // {sign, exp[EXPWIDTH-1:0], frac[PRECISION-1:0]}
    input   [EXPWIDTH+PRECISION:0]      a_i,       //操作数a
    input   [EXPWIDTH+PRECISION:0]      b_i,       //操作数b

    // 输出数据和标志信号
    //out_result_o还有符号位，因此位宽需要修正为1+EXPWIDTH+PRECISION
    output  reg [EXPWIDTH+OUTPC:0]  out_result_o,//浮点加法结果
    output  reg [4:0]               out_fflags_o,//浮点异常标志(NV, DZ, OF, UF, NX)
    output  reg                     out_far_uf_o,//far path 下溢标志
    output  reg                     out_near_of_o//near path 溢出标志 
);

    // 定义一些局部参数
    localparam INTWIDTH = OUTPC;                  // 有效尾数位数
    localparam RESWIDTH = 1 + EXPWIDTH + OUTPC;   // 输出总宽度（sign + exp + frac）

    // 全部为1用作 Inf/NaN 的指数
    localparam [EXPWIDTH-1:0] EXP_MAX = {EXPWIDTH{1'b1}};

    // 阶段1：解包、对齐
    wire a_sign = a_i[EXPWIDTH + PRECISION];
    wire b_sign = b_i[EXPWIDTH + PRECISION];

    wire [EXPWIDTH-1:0] E_a = a_i[EXPWIDTH + PRECISION - 1 : PRECISION];
    wire [EXPWIDTH-1:0] E_b = b_i[EXPWIDTH + PRECISION - 1 : PRECISION];

    wire a_is_zero = (E_a == 0) && (a_i[PRECISION-1:0] == 0);
    wire b_is_zero = (E_b == 0) && (b_i[PRECISION-1:0] == 0);

    wire a_is_nan  = (&E_a) && (|a_i[PRECISION-1:0]);
    wire b_is_nan  = (&E_b) && (|b_i[PRECISION-1:0]);

    wire a_is_inf  = (&E_a) && (~|a_i[PRECISION-1:0]);
    wire b_is_inf  = (&E_b) && (~|b_i[PRECISION-1:0]);
    //IEEE754特殊情况
    wire sp_nan   = a_is_nan | b_is_nan | (a_is_inf & b_is_inf & (a_sign ^ b_sign));
    wire sp_iv    = (a_is_inf & b_is_inf & (a_sign ^ b_sign));
    wire sp_valid = sp_nan | sp_iv;
    wire sp_inf   = (a_is_inf | b_is_inf) & (~sp_nan) & (~sp_iv);
    wire sp_inf_sign = a_is_inf ? a_sign : b_sign;

    wire hidden_a = |E_a ? 1'b1 : 1'b0;//隐藏位 hidden_a = E_a > 0 ? 1'b1 : 1'b0;
    wire hidden_b = |E_b ? 1'b1 : 1'b0;

    wire [EXPWIDTH-1:0] a_exp = |E_a ? E_a : {{(EXPWIDTH-1){1'b0}},1'b1};
    wire [EXPWIDTH-1:0] b_exp = |E_b ? E_b : {{(EXPWIDTH-1){1'b0}},1'b1};

    wire [PRECISION+2:0] a_frac = {hidden_a, a_i[PRECISION-1:0], 2'b00};//尾数位 + 有效位 + 2位保护位
    wire [PRECISION+2:0] b_frac = {hidden_b, b_i[PRECISION-1:0], 2'b00};

    // 阶码比较与移位计算
    wire a_ge_b = (a_exp >= b_exp);

    wire sign_large = a_ge_b ? a_sign : b_sign;
    wire sign_small = a_ge_b ? b_sign : a_sign;

    wire [EXPWIDTH-1:0] exp_large = a_ge_b ? a_exp : b_exp;
    wire [EXPWIDTH-1:0] exp_small = a_ge_b ? b_exp : a_exp;

    wire [PRECISION+2:0] frac_large = a_ge_b ? a_frac : b_frac;
    wire [PRECISION+2:0] frac_small = a_ge_b ? b_frac : a_frac;

    wire [EXPWIDTH-1:0] shift =
        a_ge_b ? (a_exp - b_exp) : (b_exp - a_exp);

    wire [PRECISION+2:0] lostBits =
        (shift <= (PRECISION+3)) ? (frac_small << (PRECISION+3-shift)) : frac_small;

    wire [PRECISION+3:0] shifted_fraction_small =
        { (frac_small >> shift), (|lostBits) };

    //移位与计算sticky
    wire [PRECISION+5:0] FRAC_SMALL =
        sign_small ? {sign_small, sign_small, (~shifted_fraction_small + 1'b1)}
                   : {sign_small, sign_small, shifted_fraction_small};

    wire [PRECISION+5:0] FRAC_LARGE =
        sign_large ? {sign_large, sign_large, (~frac_large + 1'b1), 1'b0}
                   : {sign_large, sign_large,  frac_large,           1'b0};

    wire [PRECISION+5:0] sum = FRAC_LARGE + FRAC_SMALL;

    // 阶段1 -> 阶段2流水线寄存器
    reg [PRECISION+5:0] sum_stage2;
    reg [EXPWIDTH-1:0]  exp_large_stage2;
    reg [EXPWIDTH + PRECISION:0] a_reg, b_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sum_stage2       <= {(PRECISION+6){1'b0}};
            exp_large_stage2 <= {EXPWIDTH{1'b0}};
            a_reg            <= {(EXPWIDTH+PRECISION+1){1'b0}};
            b_reg            <= {(EXPWIDTH+PRECISION+1){1'b0}};
        end else if (en_i) begin
            sum_stage2       <= sum;
            exp_large_stage2 <= exp_large;
            a_reg            <= a_i;
            b_reg            <= b_i;
        end
    end

    // 阶段2：加法
    wire [PRECISION+5:0] SUM = sum_stage2[PRECISION+5] ? (~sum_stage2 + 1'b1) : sum_stage2;

    //前导1检测
    wire [($clog2(PRECISION + 5) - 1):0] k;
generate    //目前仅支持PRECISION=8和PRECISION=28两种情况
  if (PRECISION == 8) begin     
    wire [3:0]  data_chk;           // 5位标志编码
    wire [15:0] expand_SUM_16bit;   // 将 SUM 扩展到16位以适应前导1检测  
    wire [7:0]  Part_1;             // 第一级16位选择 PRECISION=28时需要32位 
    wire [3:0]  Part_2;             // 第二级8位选择
    wire [1:0]  Part_3;             // 第三级4位选择
  //wire [1:0]  Part_4;             // 第四级2位选择

    assign expand_SUM_16bit = {3'b000, SUM[12:0]};
    assign data_chk[3] = |expand_SUM_16bit[15:8];       // 高8位是否有1
    assign data_chk[2] = |Part_1[7:4];                  // 选中的8位中的高4位
    assign data_chk[1] = |Part_2[3:2];                  // 选中的4位中的高2位
    assign data_chk[0] = |Part_3[1];                    // 选中的2位中的高1位
  //assign data_chk[0] = |Part_4[1];                    // 选中的1位中的高0位
  // 逐级选择包含前导1的数据段
    assign Part_1 = (|expand_SUM_16bit[15:8]) ? expand_SUM_16bit[15:8]  : expand_SUM_16bit[7:0];
    assign Part_2 = (|Part_1[7:4]) ? Part_1[7:4]    : Part_1[3:0];
    assign Part_3 = (|Part_2[3:2]) ? Part_2[3:2]    : Part_2[1:0];
    //assign Part_1 = (data_chk[3]) ? expand_SUM_16bit[15:8]  : expand_SUM_16bit[7:0]; verilatior 组合逻辑优化报错  
    //assign Part_2 = (data_chk[2]) ? Part_1[7:4]    : Part_1[3:0];
    //assign Part_3 = (data_chk[1]) ? Part_2[3:2]    : Part_2[1:0];
  //assign Part_4 = (data_chk[1]) ? Part_3[3:2]    : Part_3[1:0];

    assign k = data_chk;
  end
  else if (PRECISION == 28) begin
    wire [4:0]  data_chk;       // 5位标志编码
    wire [15:0] Part_1;         // 第一级16位选择 PRECISION=28时需要32位 
    wire [7:0]  Part_2;         // 第二级8位选择
    wire [3:0]  Part_3;         // 第三级4位选择
    wire [1:0]  Part_4;         // 第四级2位选择

    assign data_chk[4] = |SUM[31:16];       // 高16位是否有1
    assign data_chk[3] = |Part_1[15:8];    // 选中的16位中的高8位
    assign data_chk[2] = |Part_2[7:4];     // 选中的8位中的高4位
    assign data_chk[1] = |Part_3[3:2];     // 选中的4位中的高2位
    assign data_chk[0] = |Part_4[1];       // 选中的2位中的高1位
  // 逐级选择包含前导1的数据段
    assign Part_1 = (|SUM[31:16]) ? SUM[31:16]     : SUM[15:0];
    assign Part_2 = (|Part_1[15:8]) ? Part_1[15:8]   : Part_1[7:0];
    assign Part_3 = (|Part_2[7:4]) ? Part_2[7:4]    : Part_2[3:0];
    assign Part_4 = (|Part_3[3:2]) ? Part_3[3:2]    : Part_3[1:0];

    assign k = SUM[32]?{{(($clog2(PRECISION + 5) - 1)-6){1'b0}},6'b100000}:data_chk;
  end
  else begin
        // 非法参数时强制报错，且不生成任何assign
        initial begin
            $fatal(1, "ERROR: PRECISION must be 8 or 28! Current: %0d", PRECISION);
        end
    end
endgenerate
  // 生成最终位置输出

  wire [PRECISION+5:0] normalizedSum =
        (k > (PRECISION+2)) ? (SUM >> (k - (PRECISION+3)))
                            : (SUM << ((PRECISION+3) - k));

    wire [EXPWIDTH-1:0] EXPONENT =
        (k > (PRECISION+2)) ? (exp_large_stage2 + (k - (PRECISION+3)))
                            : (exp_large_stage2 - ((PRECISION+3) - k));

    wire [EXPWIDTH-1:0] EpreFinal =
        ((exp_large_stage2 + k) > (PRECISION+3)) ? EXPONENT : {EXPWIDTH{1'b0}};

    wire [PRECISION+5:0] NorSum =
        ((exp_large_stage2 + k) > (PRECISION+3)) ? normalizedSum
                                                 : (SUM << (exp_large_stage2 - 1));

    wire [PRECISION+5:0] sticky =
        (k > (PRECISION+2)) ? (SUM << (2*(PRECISION+4) - k))
                            : (SUM << (PRECISION+5));

    wire [PRECISION+5:0] NorSumm = {NorSum[PRECISION+5:1], |sticky};

    
    // NorSumm: [PRECISION+5:0] = 14 bits when PRECISION=8
    // 目标 pre_sig: [OUTPC+2:0] = 7 bits when OUTPC=4
    // 约定：
    //   pre_sig[6:3] mantissa (4 bits)
    //   pre_sig[2]   guard
    //   pre_sig[1]   round
    //   pre_sig[0]   stky

    wire [OUTPC-1:0] s1_mant = NorSumm[PRECISION+5 -: OUTPC];         // NorSumm[13:10]
    wire             s1_guard = NorSumm[PRECISION+5-OUTPC-1];           // NorSumm[9]
    wire             s1_round = NorSumm[PRECISION+5-OUTPC-2];           // NorSumm[8]

    // sticky：把更低位全部 OR（注意边界下标要合法）
    wire             s1_stky = |NorSumm[PRECISION+5-OUTPC-3 : 0];     // OR NorSumm[7:0]

    wire [OUTPC+2:0] s1_sig  = {s1_mant, s1_guard, s1_round, s1_stky}; // 7 bits 

    wire s1_sign = sum_stage2[PRECISION+5];      // 补码符号位
    wire [EXPWIDTH-1:0] s1_exp = EpreFinal;

    wire s1_sel_far = (shift >= 2);

    //0 bypass,若 a=0 -> 直接输出 b；若 b=0 -> 直接输出 a
    wire bypass_a0 = a_is_zero & ~b_is_zero;
    wire bypass_b0 = b_is_zero & ~a_is_zero;

    //将bypass的操作数压缩成OUTPC+3 sig（从 PRECISION frac 降到 OUTPC + GRS）
    function [OUTPC+2:0] pack_sig_from_frac;
        input [PRECISION-1:0] frac_in;
        reg [OUTPC-1:0] mant;
        reg g, r, s;
        begin
            mant = frac_in[PRECISION-1 -: OUTPC];
            g = frac_in[PRECISION-1-OUTPC];
            r = frac_in[PRECISION-2-OUTPC];
            s = |frac_in[PRECISION-3-OUTPC:0];
            pack_sig_from_frac = {mant, g, r, s};
        end
    endfunction

    wire [OUTPC+2:0] bz_sig_a = pack_sig_from_frac(a_i[PRECISION-1:0]);
    wire [OUTPC+2:0] bz_sig_b = pack_sig_from_frac(b_i[PRECISION-1:0]);

    // 阶段1 -> 阶段2流水线寄存器
    reg                s2_sign;
    reg [EXPWIDTH-1:0] s2_exp;
    reg [OUTPC+2:0]    s2_sig;
    reg                s2_sel_far;

    reg                s2_sp_nan;
    reg                s2_sp_iv;
    reg                s2_sp_inf;
    reg                s2_sp_inf_sign;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_sign <= 1'b0;
            s2_exp  <= {EXPWIDTH{1'b0}};
            s2_sig  <= {(OUTPC+3){1'b0}};
            s2_sel_far <= 1'b0;

            s2_sp_nan <= 1'b0;
            s2_sp_iv  <= 1'b0;
            s2_sp_inf <= 1'b0;
            s2_sp_inf_sign <= 1'b0;
        end
        else if (en_i) begin
            // special cases 优先级：NaN/IV/Inf/Zero bypass
            s2_sp_nan <= sp_nan;
            s2_sp_iv  <= sp_iv;
            s2_sp_inf <= sp_inf;
            s2_sp_inf_sign <= sp_inf_sign;

            s2_sel_far <= s1_sel_far;

            if (bypass_a0) begin
                s2_sign <= b_i[EXPWIDTH+PRECISION];
                s2_exp  <= b_i[EXPWIDTH+PRECISION-1:PRECISION];
                s2_sig  <= bz_sig_b;
            end
            else if (bypass_b0) begin
                s2_sign <= a_i[EXPWIDTH+PRECISION];
                s2_exp  <= a_i[EXPWIDTH+PRECISION-1:PRECISION];
                s2_sig  <= bz_sig_a;
            end
            else begin
                s2_sign <= s1_sign;
                s2_exp  <= s1_exp;
                s2_sig  <= s1_sig;
            end
        end
    end
// Stage2：rounding + overflow/underflow + pack + fflags

    //解析 mant/guard/sticky
    wire [OUTPC-1:0] mant_trunc = s2_sig[OUTPC+2:3];
    wire guard_bit = s2_sig[2];
    wire sticky_bit = |s2_sig[1:0];
    wire any_round_bits = guard_bit | sticky_bit;

    //计算舍入增量（inc = 是否 +1）
    reg inc_round;
    always @(*) begin
        case (rm_i)
            3'b000: inc_round = guard_bit & (sticky_bit | mant_trunc[0]); // RNE
            3'b001: inc_round = 1'b0;                                     // RTZ
            3'b010: inc_round = (~s2_sign) & any_round_bits;              // RUP
            3'b011: inc_round = ( s2_sign) & any_round_bits;              // RDN
            default: inc_round = guard_bit & (sticky_bit | mant_trunc[0]);
        endcase
    end

    //尾数舍入 & 指数调整
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
            if (s2_exp == EXP_MAX - 1'b1) begin
                // 进一步 +1 会到 EXP_MAX，视作 Overflow -> Inf
                exp_final     = EXP_MAX;
                mant_final    = {OUTPC{1'b0}}; // 表示 Inf
                flag_overflow = 1'b1;
            end
            else begin
                exp_final = s2_exp + 1'b1;
            end
        end
        else begin
            // 尾数无进位，仅复制
            mant_final = mant_ext_rounded[OUTPC-1 : 0];
            exp_final  = s2_exp;

            // 非严格的 underflow 判定（当指数已经在最小附近且仍然发生了舍入）
            if (s2_exp == {EXPWIDTH{1'b0}} && any_round_bits && (mant_trunc == {OUTPC{1'b0}})) begin
                flag_underflow = 1'b1;
            end
        end
    end

    // normal result
    wire [RESWIDTH-1:0] result_normal = {s2_sign, exp_final, mant_final};
    
    // special result
    wire [RESWIDTH-1:0] result_qnan = {1'b0, EXP_MAX, {1'b1, {OUTPC-1{1'b0}}}};
    wire [RESWIDTH-1:0] result_inf  = {s2_sp_inf_sign, EXP_MAX, {OUTPC{1'b0}}};

    wire use_nan = s2_sp_nan | s2_sp_iv;   // invalid -> NaN
    wire use_inf = s2_sp_inf & ~use_nan;

    wire [RESWIDTH-1:0] result_comb = use_nan ? result_qnan :
                                      use_inf ? result_inf  :
                                      result_normal;
                        
    //fflags 汇总
    wire nx_flag = any_round_bits | flag_overflow | flag_underflow;

    wire [4:0] fflags_comb = {
        /*NV*/ s2_sp_iv,
        /*OF*/ (~use_nan & ~use_inf) ? flag_overflow  : 1'b0,
        /*UF*/ (~use_nan & ~use_inf) ? flag_underflow : 1'b0,
        /*DZ*/ 1'b0,
        /*NX*/ (~use_nan & ~use_inf) ? nx_flag        : 1'b0
    };

    wire far_uf_comb  = s2_sel_far  ? ((~use_nan & ~use_inf) & flag_underflow) : 1'b0;
    wire near_of_comb = (~s2_sel_far) ? ((~use_nan & ~use_inf) & flag_overflow) : 1'b0;

    //输出结果
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_result_o  <= {RESWIDTH{1'b0}};
            out_fflags_o  <= 5'b0;
            out_far_uf_o  <= 1'b0;
            out_near_of_o <= 1'b0;
        end
        else if (en_i) begin
            out_result_o  <= result_comb;
            out_fflags_o  <= fflags_comb;
            out_far_uf_o  <= far_uf_comb;
            out_near_of_o <= near_of_comb;
        end
    end

endmodule
