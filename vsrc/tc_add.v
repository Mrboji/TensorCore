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

    //用于 fma 指令的标志信号，根据需要选择性保留
    input                                   b_inter_valid_i,       //中间结果是否有效
    input                                   b_inter_flags_is_nan_i, //中间结果为 NaN 标志   
    input                                   b_inter_flags_is_inf_i, //中间结果为无穷标志
    input                                   b_inter_flags_is_inv_i, //无效操作标志
    input                                   b_inter_flags_overflow_i, //溢出标志

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

    // fflags bit index: {NV, OF, UF, DZ, NX}
    localparam IDX_NV = 4;
    localparam IDX_OF = 3;
    localparam IDX_UF = 2;
    localparam IDX_DZ = 1;
    localparam IDX_NX = 0;

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

    wire [PRECISION+2:0] frac_small_sr;
    reg  sticky_align;
    integer j;

    // 右移主体（组合）
    assign frac_small_sr =
        (shift >= (PRECISION+3)) ? { (PRECISION+3){1'b0} } :
        (shift == 0)             ? frac_small :
                                (frac_small >> shift);

    // 计算 sticky_align：OR 被移位丢弃的低位
    always @(*) begin
        sticky_align = 1'b0;

        if (shift > 0) begin
            if (shift >= (PRECISION+3)) begin
                // 全部被移掉
                sticky_align = |frac_small;
            end
            else begin
                // OR frac_small[shift-1 : 0]
                for (j = 0; j < shift; j = j + 1) begin
                    sticky_align = sticky_align | frac_small[j];
                end
            end
        end
    end

    // 拼接成 {右移结果, sticky}
    wire [PRECISION+3:0] shifted_fraction_small =
        { frac_small_sr, 1'b0 };

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
    // 控制信号（Stage1 锁存）
    reg [2:0] s2_rm;              // 你已加入：rm pipeline
    reg       s1_sel_far;         // shift>=2 pipeline
    reg       s1_bypass_a0;
    reg       s1_bypass_b0;
    reg       s1_sp_nan;
    reg       s1_sp_iv;
    reg       s1_sp_inf;
    reg       s1_sp_inf_sign;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sum_stage2       <= {(PRECISION+6){1'b0}};
            exp_large_stage2 <= {EXPWIDTH{1'b0}};
            a_reg            <= {(EXPWIDTH+PRECISION+1){1'b0}};
            b_reg            <= {(EXPWIDTH+PRECISION+1){1'b0}};

            s2_rm            <= 3'b000;
            s1_sel_far       <= 1'b0;
            s1_bypass_a0     <= 1'b0;
            s1_bypass_b0     <= 1'b0;
            s1_sp_nan        <= 1'b0;
            s1_sp_iv         <= 1'b0;
            s1_sp_inf        <= 1'b0;
            s1_sp_inf_sign   <= 1'b0;
        end
        else if (en_i) begin
            sum_stage2       <= sum;
            exp_large_stage2 <= exp_large;
            a_reg            <= a_i;
            b_reg            <= b_i;

            s2_rm            <= rm_i;
            s1_sel_far       <= (shift >= 2);
            s1_bypass_a0     <= (a_is_zero & ~b_is_zero);
            s1_bypass_b0     <= (b_is_zero & ~a_is_zero);
            s1_sp_nan        <= sp_nan;
            s1_sp_iv         <= sp_iv;
            s1_sp_inf        <= sp_inf;
            s1_sp_inf_sign   <= sp_inf_sign;
        end
    end

    // 阶段2：加法
    wire [PRECISION+5:0] SUM = sum_stage2[PRECISION+5] ? (~sum_stage2 + 1'b1) : sum_stage2;
    wire sum_is_zero = (SUM == { (PRECISION+6){1'b0} });

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

    wire sticky = |NorSum[PRECISION+5-OUTPC-3 : 0];

    wire [PRECISION+5:0] NorSumm = { NorSum[PRECISION+5:1], sticky };

    
    // NorSumm: [PRECISION+5:0] = 14 bits when PRECISION=8
    // 目标 pre_sig: [OUTPC+2:0] = 7 bits when OUTPC=4
    // 约定：
    //   pre_sig[6:3] mantissa (4 bits)
    //   pre_sig[2]   guard
    //   pre_sig[1]   round
    //   pre_sig[0]   stky

    wire [OUTPC-1:0] s1_mant  = NorSumm[10:7];
    wire              s1_guard = NorSumm[6];
    wire              s1_round = NorSumm[5];
    wire              s1_stky  = |NorSumm[4:0];

    wire [OUTPC+2:0] s1_sig  = {s1_mant, s1_guard, s1_round, s1_stky}; // 7 bits 

    wire s1_sign = sum_stage2[PRECISION+5];      // 补码符号位
    wire [EXPWIDTH-1:0] s1_exp = EpreFinal;

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

    wire [OUTPC+2:0] bz_sig_a = pack_sig_from_frac(a_reg[PRECISION-1:0]);
    wire [OUTPC+2:0] bz_sig_b = pack_sig_from_frac(b_reg[PRECISION-1:0]);

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
            // special cases flags：用 Stage1 锁存版本
            s2_sp_nan <= s1_sp_nan;
            s2_sp_iv  <= s1_sp_iv;
            s2_sp_inf <= s1_sp_inf;
            s2_sp_inf_sign <= s1_sp_inf_sign;

            // far/near：用 Stage1 锁存版本
            s2_sel_far <= s1_sel_far;

            // 最高优先级：完全抵消 -> +0
            if (sum_is_zero) begin
                s2_sign <= 1'b0;
                s2_exp  <= {EXPWIDTH{1'b0}};
                s2_sig  <= {(OUTPC+3){1'b0}};
            end
            // bypass：用 Stage1 锁存版本，并使用 a_reg/b_reg
            else if (s1_bypass_a0) begin
                s2_sign <= b_reg[EXPWIDTH+PRECISION];
                s2_exp  <= b_reg[EXPWIDTH+PRECISION-1:PRECISION];
                s2_sig  <= bz_sig_b;
            end
            else if (s1_bypass_b0) begin
                s2_sign <= a_reg[EXPWIDTH+PRECISION];
                s2_exp  <= a_reg[EXPWIDTH+PRECISION-1:PRECISION];
                s2_sig  <= bz_sig_a;
            end
            // 正常路径
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
    wire guard_bit  = s2_sig[2];
    wire round_bit  = s2_sig[1];
    wire sticky_bit = s2_sig[0];
    wire any_round_bits = guard_bit | round_bit | sticky_bit;

    //计算舍入增量（inc = 是否 +1）
    reg inc_round;
    always @(*) begin
        case (s2_rm)
            3'b000: inc_round = guard_bit & (round_bit | sticky_bit | mant_trunc[0]); // RNE
            //3'b001: inc_round = 1'b0;                                                 // RTZ
            //3'b010: inc_round = (~s2_sign) & any_round_bits;                          // RUP
            //3'b011: inc_round = ( s2_sign) & any_round_bits;                          // RDN
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
        mant_ext_rounded = {1'b0, mant_trunc};
        //默认是在原尾数前加一个0，便于计算进位。加上的进位信号为尾数位个0+计算出来的是否舍入值
        mant_final       = mant_trunc;
        exp_final        = s2_exp;

        flag_overflow    = 1'b0;
        flag_underflow   = 1'b0;

        //规格化后指数已经进入 EXP_MAX 区域：视为 overflow
        //EXP_MAX(全1) 是 Inf/NaN 指数，不能作为 normal
        if (s2_exp >= EXP_MAX) begin
            exp_final     = EXP_MAX;
            mant_final    = {OUTPC{1'b0}}; // Inf
            flag_overflow = 1'b1;
            flag_underflow= 1'b0;
        end
        else begin
            //按舍入模式决定是否 +1
            mant_ext_rounded = {1'b0, mant_trunc} + {{OUTPC{1'b0}}, inc_round};

            //溢出：舍入导致 mantissa 进位 -> 指数 +1
            if (mant_ext_rounded[OUTPC]) begin
                mant_final = mant_ext_rounded[OUTPC:1];

                // 指数 +1 后如果到 EXP_MAX -> overflow -> Inf
                if (s2_exp == (EXP_MAX - 1'b1)) begin
                    exp_final     = EXP_MAX;
                    mant_final    = {OUTPC{1'b0}}; // Inf
                    flag_overflow = 1'b1;
                end
                else begin
                    exp_final = s2_exp + 1'b1;
                end
            end
            else begin
                // 无进位，指数不变
                mant_final = mant_ext_rounded[OUTPC-1:0];
                exp_final  = s2_exp;

                if (s2_exp == {EXPWIDTH{1'b0}} && any_round_bits &&
                    (mant_trunc == {OUTPC{1'b0}})) begin
                    flag_underflow = 1'b1;
                end
            end
        end
    end

    // normal result
    wire [RESWIDTH-1:0] result_normal = {s2_sign, exp_final, mant_final};
    
    // special result
    wire [RESWIDTH-1:0] result_qnan = {1'b0, EXP_MAX, {1'b1, {OUTPC-1{1'b0}}}};
    wire [RESWIDTH-1:0] result_inf  = {s2_sp_inf_sign, EXP_MAX, {OUTPC{1'b0}}};

    wire gen_overflow_inf = flag_overflow;  // IEEE: 运算溢出 → Inf

    wire use_nan = s2_sp_nan | s2_sp_iv;
    wire use_inf = (s2_sp_inf | gen_overflow_inf) & ~use_nan;

    wire [RESWIDTH-1:0] result_comb = use_nan ? result_qnan :
                                      use_inf ? result_inf  :
                                      result_normal;
                        
    //fflags 汇总
    wire use_special = use_nan | use_inf;

    reg [RESWIDTH-1:0] result_comb_r;
    reg [4:0]          fflags_comb_r;
    reg                far_uf_comb_r, near_of_comb_r;

    always @(*) begin
        // ---------- result select ----------
        result_comb_r = use_nan ? result_qnan :
                        use_inf ? result_inf  :
                                result_normal;

        // ---------- default ----------
        fflags_comb_r  = 5'b0;
        far_uf_comb_r  = 1'b0;
        near_of_comb_r = 1'b0;

        // ---------- NaN / Invalid ----------
        if (use_nan) begin
            fflags_comb_r[IDX_NV] = 1'b1;
        end
        else begin
            // ---------- normal ----------
            fflags_comb_r[IDX_NV] = 1'b0;
            fflags_comb_r[IDX_OF] = flag_overflow;
            fflags_comb_r[IDX_UF] = flag_underflow;
            fflags_comb_r[IDX_DZ] = 1'b0;
            fflags_comb_r[IDX_NX] =
                any_round_bits | flag_overflow | flag_underflow;

            far_uf_comb_r  = s2_sel_far  & flag_underflow;
            near_of_comb_r = (~s2_sel_far) & flag_overflow;
        end
    end

    // connect to output stage
    wire [RESWIDTH-1:0] result_comb  = result_comb_r;
    wire [4:0]          fflags_comb  = fflags_comb_r;
    wire                far_uf_comb  = far_uf_comb_r;
    wire                near_of_comb = near_of_comb_r;

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