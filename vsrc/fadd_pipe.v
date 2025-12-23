module fadd_pipe #(
    parameter EXPWIDTH    = 5,
    parameter PRECISION   = 3,
    parameter CTRL_C_WIDTH = 16,
    parameter DEPTH_WARP   = 4
)(
    input  wire                              clk,
    input  wire                              rst_n,

    input  wire [EXPWIDTH+PRECISION:0]       a_i,
    input  wire [EXPWIDTH+PRECISION:0]       b_i,

    input  wire [2:0]                        rm_i,       
    input  wire [CTRL_C_WIDTH-1:0]           ctrl_c_i,   
    input  wire [2:0]                        ctrl_rm_i,  
    input  wire [7:0]                        ctrl_reg_idxw_i, 
    input  wire [DEPTH_WARP-1:0]             ctrl_warpid_i,   

    input  wire                              in_valid_i, 
    output reg                               in_ready_o, 
    
    output reg                               out_valid_o,
    input  wire                              out_ready_i, 

    output reg  [EXPWIDTH+PRECISION:0]       result_o,
    output reg  [4:0]                        fflags_o,
    // output reg                               overflow,
    // output reg                               underflow,
    // output reg                               invalid,
    output wire [CTRL_C_WIDTH-1:0]           ctrl_c_o,   
    output wire [2:0]                        ctrl_rm_o, 
    output wire [7:0]                        ctrl_reg_idxw_o, 
    output wire [DEPTH_WARP-1:0]             ctrl_warpid_o
);

    localparam TOTAL_WIDTH = EXPWIDTH + PRECISION + 1;  // 总位宽
    localparam FRAC_WIDTH  = PRECISION + 3;             // 隐含位 + 尾数 + 2位保护位
    localparam SUM_WIDTH   = FRAC_WIDTH + 2;            // 加法器宽度（带符号扩展）

    assign ctrl_c_o        = ctrl_c_i;
    assign ctrl_rm_o       = ctrl_rm_i;
    assign ctrl_reg_idxw_o = ctrl_reg_idxw_i;
    assign ctrl_warpid_o   = ctrl_warpid_i;

    reg overflow;
    reg underflow;
    reg invalid;

    // 阶段1信号
    wire sign_a;
    wire [EXPWIDTH-1:0] E_a;
    wire [EXPWIDTH-1:0] exponent_a;
    wire hidden_a;
    wire [FRAC_WIDTH-1:0] fraction_a;  // 10位尾数 + 2位保护位 + hidden位

    wire sign_b;
    wire [EXPWIDTH-1:0] E_b;
    wire [EXPWIDTH-1:0] exponent_b;
    wire hidden_b;
    wire [FRAC_WIDTH-1:0] fraction_b;  // 10位尾数 + 2位保护位 + hidden位

    wire sign_large;
    wire [EXPWIDTH-1:0] exponent_large;
    wire [FRAC_WIDTH-1:0] fraction_large;
    wire [FRAC_WIDTH+2:0] FRACTION_LARGE; // 14 + 2

    wire sign_small;
    wire [EXPWIDTH-1:0] exponent_small;
    wire [FRAC_WIDTH-1:0] fraction_small;
    wire [FRAC_WIDTH+2:0] FRACTION_SMALL; // 14 + 2

    wire [FRAC_WIDTH:0] shifted_fraction_small;  // 13 + |lostBits

    wire [SUM_WIDTH:0] sum;
    wire [SUM_WIDTH:0] SUM;
    wire [SUM_WIDTH:0] normalizedSum;
    wire [SUM_WIDTH:0] NorSum;
    wire [SUM_WIDTH:0] NorSumm;
    wire [SUM_WIDTH:0] Sum;
    wire [SUM_WIDTH:0] SUMFINAL;

    wire [EXPWIDTH-1:0] Exponent;
    wire [EXPWIDTH-1:0] EXPONENT;
    wire [EXPWIDTH-1:0] EpreFinal;
    wire [EXPWIDTH-1:0] EFinal;
    wire [EXPWIDTH-1:0] EFINAL;

    wire [EXPWIDTH-1:0] subtraction;
    wire [EXPWIDTH-1:0] shift;

    wire [FRAC_WIDTH-1:0] lostBits;
    wire [SUM_WIDTH:0] sticky;

    wire [EXPWIDTH-1:0] k;
    wire carry;
    reg  [TOTAL_WIDTH-1:0] a_reg;
    reg  [TOTAL_WIDTH-1:0] b_reg;

    reg [FRAC_WIDTH+2:0]FRACTION_SMALL_stage2;
    reg [FRAC_WIDTH+2:0]FRACTION_LARGE_stage2;
    reg [EXPWIDTH-1:0] Exponent_stage2;
    reg [TOTAL_WIDTH-1:0] a_stage2;
    reg [TOTAL_WIDTH-1:0] b_stage2;
    reg [SUM_WIDTH:0] sum_stage2;
    reg stage1_valid;
    reg stage2_valid;
    wire[SUM_WIDTH:0] result;

    // 阶段1：解包、对齐
    assign sign_a = a_i[EXPWIDTH+PRECISION];
    assign sign_b = b_i[EXPWIDTH+PRECISION];
    assign E_a = a_i[EXPWIDTH+PRECISION-1:PRECISION];
    assign E_b = b_i[EXPWIDTH+PRECISION-1:PRECISION];
    assign hidden_a = |E_a;  // FP16隐含位
    assign hidden_b = |E_b;

    assign exponent_a = E_a > 0 ? E_a : {{EXPWIDTH-1{1'b0}}, 1'b1};
    assign exponent_b = E_b > 0 ? E_b : {{EXPWIDTH-1{1'b0}}, 1'b1};

    assign fraction_a = {hidden_a, a_i[PRECISION-1:0], 2'b00};    // 10位尾数 + 2位保护位
    assign fraction_b = {hidden_b, b_i[PRECISION-1:0], 2'b00};

    // 阶码比较与移位计算,如果a>b,carry=0,否则carry=1
    assign {carry, subtraction} = exponent_a - exponent_b;

    assign sign_small = carry == 0 ? sign_b : sign_a;
    assign sign_large = carry == 0 ? sign_a : sign_b;

    assign exponent_small = carry == 0 ? exponent_b : exponent_a;
    assign exponent_large = carry == 0 ? exponent_a : exponent_b;

    assign Exponent = exponent_large;

    assign fraction_small = carry == 0 ? fraction_b : fraction_a;  
    assign fraction_large = carry == 0 ? fraction_a : fraction_b;

    assign shift = carry == 0 ? subtraction : -subtraction;

    assign lostBits = shift <= FRAC_WIDTH ? fraction_small << (FRAC_WIDTH - shift) : fraction_small;

    assign shifted_fraction_small = {fraction_small >> shift, |lostBits};

    // 尾数对齐

    assign FRACTION_SMALL = sign_small ? {sign_small, sign_small, -shifted_fraction_small} : {sign_small, sign_small, shifted_fraction_small};
    assign FRACTION_LARGE = sign_large ? {sign_large, sign_large, -fraction_large, 1'b0} : {sign_large, sign_large, fraction_large, 1'b0};
    assign sum = FRACTION_LARGE + FRACTION_SMALL;    

    // 阶段1 -> 阶段2流水线寄存器
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage1_valid <= 1'b0;
            FRACTION_LARGE_stage2 <= {FRAC_WIDTH+3{1'b0}};
            FRACTION_SMALL_stage2 <= {FRAC_WIDTH+3{1'b0}};
            Exponent_stage2 <= {EXPWIDTH{1'b0}};
            a_reg <= {TOTAL_WIDTH{1'b0}};
            b_reg <= {TOTAL_WIDTH{1'b0}};
            sum_stage2 <= {SUM_WIDTH+1{1'b0}};
        end else begin
            stage1_valid <= in_valid_i && in_ready_o;
            FRACTION_LARGE_stage2 <= FRACTION_LARGE;
            FRACTION_SMALL_stage2 <= FRACTION_SMALL;
            Exponent_stage2 <= Exponent;
            a_reg <= a_i;
            b_reg <= b_i;
            sum_stage2 <= sum;
        end
    end

    // 阶段2：加法
    assign SUM = sum_stage2[SUM_WIDTH] ? -sum_stage2 : sum_stage2;

    reg [EXPWIDTH-1:0] k_reg;
    always @(*) begin
        k_reg = {EXPWIDTH{1'b0}};
        for (integer i = SUM_WIDTH-1; i >= 0; i = i - 1) begin
            if (SUM[i]) begin
                k_reg = i[EXPWIDTH-1:0];;  // 找到最高位1的位置
                break;  // 找到后可以退出
            end
        end
    end
    assign k = k_reg;

    assign normalizedSum = k > (PRECISION + 2) ? SUM >> (k - FRAC_WIDTH) : SUM << (FRAC_WIDTH - k);
    assign EXPONENT      = k > (PRECISION + 2) ? (Exponent_stage2 + k - FRAC_WIDTH) : (Exponent_stage2 - FRAC_WIDTH + k);

    assign EpreFinal = Exponent_stage2 + k > FRAC_WIDTH ? EXPONENT : {EXPWIDTH{1'b0}}; 
    assign NorSum    = Exponent_stage2 + k > FRAC_WIDTH ? normalizedSum : SUM << (Exponent_stage2 - 1);

    // 舍入（就近舍入到偶数）
    assign sticky = (k > (FRAC_WIDTH-1)) ? SUM << (FRAC_WIDTH*2+2 - k) : SUM << SUM_WIDTH;  // 26 = 2*13 (类似FP32的54=2*27)
    assign NorSumm = {NorSum[SUM_WIDTH:1], |sticky};               // 取 NorSum[12:1] + sticky
    // 4. 舍入逻辑（与FP32完全相同，位宽自适应）
    assign Sum = NorSumm[2] == 0 ? NorSumm :
                 NorSumm[1] == 1 ? (NorSumm + {{SUM_WIDTH-3{1'b0}}, 4'b1000}) :
                 NorSumm[0] == 1 ? (NorSumm + {{SUM_WIDTH-3{1'b0}}, 4'b1000}) :
                 NorSumm[3] == 0 ? NorSumm : (NorSumm + {{SUM_WIDTH-3{1'b0}}, 4'b1000});

    assign EFinal = |SUM ? EpreFinal : {EXPWIDTH{1'b0}};
    //if there is no 1 the exponent and the number are both 0 (denormalized)

    assign SUMFINAL = Sum[SUM_WIDTH-1] ? Sum >> 1 : Sum; 
    assign EFINAL =  Sum[SUM_WIDTH-1] ? EFinal + 1 : EFinal;
    //renormalize in case of special situations after rounding 
    assign result = (a_reg[EXPWIDTH+PRECISION-1:0] == 0) ? b_reg :
                      (b_reg[EXPWIDTH+PRECISION-1:0] == 0) ? a_reg : 
                      (a_reg[EXPWIDTH+PRECISION-1:PRECISION] == {EXPWIDTH{1'b1}}) && (a_reg[PRECISION-1:0] == 0) ? {1'b0, {EXPWIDTH{1'b1}}, {PRECISION{1'b0}}} :
                      (b_reg[EXPWIDTH+PRECISION-1:PRECISION] == {EXPWIDTH{1'b1}}) && (b_reg[PRECISION-1:0] == 0) ? {1'b0, {EXPWIDTH{1'b1}}, {PRECISION{1'b0}}} : 
                      (a_reg[EXPWIDTH+PRECISION-1:PRECISION] == {EXPWIDTH{1'b1}}) && (a_reg[PRECISION-1:0] != 0) ? {1'b0, {EXPWIDTH{1'b1}}, 1'b1, {PRECISION-1{1'b0}}} :
                      (b_reg[EXPWIDTH+PRECISION-1:PRECISION] == {EXPWIDTH{1'b1}}) && (b_reg[PRECISION-1:0] != 0) ? {1'b0, {EXPWIDTH{1'b1}}, 1'b1, {PRECISION-1{1'b0}}} : 
                      {sum_stage2[SUM_WIDTH], EFINAL, SUMFINAL[FRAC_WIDTH-1:3]};

    assign overflow = result[EXPWIDTH+PRECISION-1:PRECISION] == {EXPWIDTH{1'b1}}; // Set overflow flag if the result is too large
    assign invalid  = (result[EXPWIDTH+PRECISION-1:PRECISION] == {EXPWIDTH{1'b1}}) && (result[PRECISION-1:0] != 0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage2_valid<= 1'b0;
            result_o    <= {EXPWIDTH+PRECISION+1{1'b0}};
            fflags_o    <= 5'b0;
        end else begin
            stage2_valid <= stage1_valid;
            if (stage1_valid) begin
                result_o    <= result;
                fflags_o    <= {1'b0, 1'b0, invalid, underflow, overflow};
            end
        end
    end

    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)
            in_ready_o <= 1'b0;
        else if(~in_ready_o && in_valid_i)
            in_ready_o <= 1'b1;
        else
            in_ready_o <= 1'b0;
    end

    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)
            out_valid_o <= 1'b0;
        else if(stage1_valid)
            out_valid_o <= 1'b1;
        else if(out_ready_i)
            out_valid_o <= 1'b0;
        else
            out_valid_o <= out_valid_o;
    end

endmodule
