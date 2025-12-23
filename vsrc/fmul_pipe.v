// Three-stage floating-point multiplier with simple mantissa multiplier.
module fmul_pipe #(
    parameter EXP_WIDTH    = 5,
    parameter FRAC_WIDTH   = 3,
    parameter CTRL_C_WIDTH = 16,
    parameter DEPTH_WARP   = 4
) (
    input  wire                              clk,
    input  wire                              rst_n,

    input  wire [EXP_WIDTH+FRAC_WIDTH:0]     a_i,
    input  wire [EXP_WIDTH+FRAC_WIDTH:0]     b_i,

    input  wire [2:0]                        rm_i,       
    input  wire [CTRL_C_WIDTH-1:0]           ctrl_c_i,   
    input  wire [2:0]                        ctrl_rm_i,  
    input  wire [7:0]                        ctrl_reg_idxw_i, 
    input  wire [DEPTH_WARP-1:0]             ctrl_warpid_i,   

    input  wire                              in_valid_i, 
    output reg                               in_ready_o, 
    
    output reg                               out_valid_o,
    input  wire                              out_ready_i, 

    output reg  [EXP_WIDTH+FRAC_WIDTH:0]     result_o,
    output reg  [4:0]                        fflags_o,

    output wire [CTRL_C_WIDTH-1:0]           ctrl_c_o,   
    output wire [2:0]                        ctrl_rm_o, 
    output wire [7:0]                        ctrl_reg_idxw_o, 
    output wire [DEPTH_WARP-1:0]             ctrl_warpid_o
);

    localparam integer MAN_WIDTH      = FRAC_WIDTH + 1;
    localparam integer PROD_WIDTH     = MAN_WIDTH * 2;
    localparam integer EXP_SUM_WIDTH  = EXP_WIDTH + 3;
    localparam integer BIAS           = (1 << (EXP_WIDTH - 1)) - 1;
    localparam signed [EXP_SUM_WIDTH:0] BIAS_VALUE = BIAS[EXP_SUM_WIDTH:0];
    localparam integer EXP_MAX        = (1 << EXP_WIDTH) - 1;
    localparam integer INDEX_MSB      = PROD_WIDTH - 3;
    localparam integer INDEX_LSB      = PROD_WIDTH - FRAC_WIDTH - 2;
    localparam integer GUARD_INDEX    = INDEX_LSB - 1;
    localparam integer ROUND_INDEX    = GUARD_INDEX - 1;

    assign ctrl_c_o        = ctrl_c_i;
    assign ctrl_rm_o       = ctrl_rm_i;
    assign ctrl_reg_idxw_o = ctrl_reg_idxw_i;
    assign ctrl_warpid_o   = ctrl_warpid_i;

    // Stage 1 registers.
    reg                               stage1_valid;
    reg                               stage1_sign_a;
    reg                               stage1_sign_b;
    reg  [EXP_WIDTH-1:0]              stage1_exp_a;
    reg  [EXP_WIDTH-1:0]              stage1_exp_b;
    reg  [MAN_WIDTH-1:0]              stage1_mant_a;
    reg  [MAN_WIDTH-1:0]              stage1_mant_b;
    reg  signed [EXP_SUM_WIDTH:0]     stage1_exp_a_eff;
    reg  signed [EXP_SUM_WIDTH:0]     stage1_exp_b_eff;
    reg                               stage1_is_zero_a;
    reg                               stage1_is_zero_b;
    reg                               stage1_is_inf_a;
    reg                               stage1_is_inf_b;
    reg                               stage1_is_nan_a;
    reg                               stage1_is_nan_b;

    // Stage 2 registers.
    reg                               stage2_valid;
    reg                               stage2_sign;
    reg  [PROD_WIDTH-1:0]             stage2_mant_product;
    reg  signed [EXP_SUM_WIDTH:0]     stage2_exp_sum;
    reg                               stage2_is_nan;
    reg                               stage2_is_inf;
    reg                               stage2_is_zero;
    reg                               stage2_invalid;

    reg                               stage3_valid;

    wire [PROD_WIDTH-1:0]             mant_product_w;
    wire signed [EXP_SUM_WIDTH:0]     exp_sum_w;
    wire                              invalid_w;
    wire                              nan_w;
    wire                              inf_w;
    wire                              zero_w;

    wire [EXP_WIDTH-1:0]              exp_a_w;
    wire [EXP_WIDTH-1:0]              exp_b_w;
    wire [FRAC_WIDTH-1:0]             frac_a_w;
    wire [FRAC_WIDTH-1:0]             frac_b_w;
    wire                              is_zero_a_w;
    wire                              is_zero_b_w;
    wire                              is_inf_a_w;
    wire                              is_inf_b_w;
    wire                              is_nan_a_w;
    wire                              is_nan_b_w;
    wire [MAN_WIDTH-1:0]              mant_a_w;
    wire [MAN_WIDTH-1:0]              mant_b_w;
    wire signed [EXP_SUM_WIDTH:0]     exp_a_eff_w;
    wire signed [EXP_SUM_WIDTH:0]     exp_b_eff_w;

    assign exp_a_w = a_i[EXP_WIDTH+FRAC_WIDTH-1:FRAC_WIDTH];
    assign exp_b_w = b_i[EXP_WIDTH+FRAC_WIDTH-1:FRAC_WIDTH];
    assign frac_a_w = a_i[FRAC_WIDTH-1:0];
    assign frac_b_w = b_i[FRAC_WIDTH-1:0];
    assign is_zero_a_w = (exp_a_w == {EXP_WIDTH{1'b0}}) && (frac_a_w == {FRAC_WIDTH{1'b0}});
    assign is_zero_b_w = (exp_b_w == {EXP_WIDTH{1'b0}}) && (frac_b_w == {FRAC_WIDTH{1'b0}});
    assign is_inf_a_w = (exp_a_w == {EXP_WIDTH{1'b1}}) && (frac_a_w == {FRAC_WIDTH{1'b0}});
    assign is_inf_b_w = (exp_b_w == {EXP_WIDTH{1'b1}}) && (frac_b_w == {FRAC_WIDTH{1'b0}});
    assign is_nan_a_w = (exp_a_w == {EXP_WIDTH{1'b1}}) && (frac_a_w != {FRAC_WIDTH{1'b0}});
    assign is_nan_b_w = (exp_b_w == {EXP_WIDTH{1'b1}}) && (frac_b_w != {FRAC_WIDTH{1'b0}});
    assign mant_a_w = (exp_a_w == {EXP_WIDTH{1'b0}}) ? {1'b0, frac_a_w} :
                                                       {1'b1, frac_a_w};
    assign mant_b_w = (exp_b_w == {EXP_WIDTH{1'b0}}) ? {1'b0, frac_b_w} :
                                                       {1'b1, frac_b_w};
    assign exp_a_eff_w = is_zero_a_w ? {EXP_SUM_WIDTH+1{1'b0}} :
                         ((exp_a_w == {EXP_WIDTH{1'b0}}) ?
                          {{EXP_SUM_WIDTH{1'b0}}, 1'b1} :
                          {{(EXP_SUM_WIDTH+1-EXP_WIDTH){1'b0}}, exp_a_w});
    assign exp_b_eff_w = is_zero_b_w ? {EXP_SUM_WIDTH+1{1'b0}} :
                         ((exp_b_w == {EXP_WIDTH{1'b0}}) ?
                          {{EXP_SUM_WIDTH{1'b0}}, 1'b1} :
                          {{(EXP_SUM_WIDTH+1-EXP_WIDTH){1'b0}}, exp_b_w});

    // Stage 1: decode operands.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage1_valid     <= 1'b0;
            stage1_sign_a    <= 1'b0;
            stage1_sign_b    <= 1'b0;
            stage1_exp_a     <= {EXP_WIDTH{1'b0}};
            stage1_exp_b     <= {EXP_WIDTH{1'b0}};
            stage1_mant_a    <= {MAN_WIDTH{1'b0}};
            stage1_mant_b    <= {MAN_WIDTH{1'b0}};
            stage1_exp_a_eff <= {EXP_SUM_WIDTH+1{1'b0}};
            stage1_exp_b_eff <= {EXP_SUM_WIDTH+1{1'b0}};
            stage1_is_zero_a <= 1'b0;
            stage1_is_zero_b <= 1'b0;
            stage1_is_inf_a  <= 1'b0;
            stage1_is_inf_b  <= 1'b0;
            stage1_is_nan_a  <= 1'b0;
            stage1_is_nan_b  <= 1'b0;
        end else begin
            stage1_valid  <= in_valid_i && in_ready_o;
            if (in_valid_i && in_ready_o) begin
                stage1_sign_a <= a_i[EXP_WIDTH+FRAC_WIDTH];
                stage1_sign_b <= b_i[EXP_WIDTH+FRAC_WIDTH];
                stage1_exp_a  <= exp_a_w;
                stage1_exp_b  <= exp_b_w;
                stage1_mant_a <= mant_a_w;
                stage1_mant_b <= mant_b_w;
                stage1_is_zero_a <= is_zero_a_w;
                stage1_is_zero_b <= is_zero_b_w;
                stage1_is_inf_a  <= is_inf_a_w;
                stage1_is_inf_b  <= is_inf_b_w;
                stage1_is_nan_a  <= is_nan_a_w;
                stage1_is_nan_b  <= is_nan_b_w;
                stage1_exp_a_eff <= exp_a_eff_w;
                stage1_exp_b_eff <= exp_b_eff_w;
            end
        end
    end

    assign invalid_w = (stage1_is_inf_a && stage1_is_zero_b) ||
                       (stage1_is_inf_b && stage1_is_zero_a);
    assign nan_w = stage1_is_nan_a || stage1_is_nan_b || invalid_w;
    assign inf_w = (stage1_is_inf_a || stage1_is_inf_b) && !nan_w;
    assign zero_w = (stage1_is_zero_a || stage1_is_zero_b) && !inf_w && !nan_w;

    naiveMultiplier #(
        .WIDTH(MAN_WIDTH)
    ) mant_mul (
        .in_a(stage1_mant_a),
        .in_b(stage1_mant_b),
        .product(mant_product_w)
    );

    assign exp_sum_w = stage1_exp_a_eff + stage1_exp_b_eff - BIAS_VALUE;

    // Stage 2: core multiply and exponent addition.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage2_valid        <= 1'b0;
            stage2_sign         <= 1'b0;
            stage2_mant_product <= {PROD_WIDTH{1'b0}};
            stage2_exp_sum      <= {EXP_SUM_WIDTH+1{1'b0}};
            stage2_is_nan       <= 1'b0;
            stage2_is_inf       <= 1'b0;
            stage2_is_zero      <= 1'b0;
            stage2_invalid      <= 1'b0;
        end else begin
            stage2_valid        <= stage1_valid;
            if (stage1_valid) begin
                stage2_sign         <= stage1_sign_a ^ stage1_sign_b;
                stage2_mant_product <= mant_product_w;
                stage2_exp_sum      <= exp_sum_w;
                stage2_is_nan       <= nan_w;
                stage2_is_inf       <= inf_w;
                stage2_is_zero      <= zero_w;
                stage2_invalid      <= invalid_w;
            end
        end
    end

    // Stage 3: normalization, rounding, and packing.
    reg [EXP_WIDTH+FRAC_WIDTH:0] result_comb;
    reg                          overflow_comb;
    reg                          underflow_comb;
    reg                          invalid_comb;
    reg [PROD_WIDTH-1:0]         norm_mant;
    reg signed [EXP_SUM_WIDTH:0] norm_exp;
    reg signed [EXP_SUM_WIDTH:0] exp_after_round;
    reg [FRAC_WIDTH-1:0]         mantissa_field;
    reg                          guard_bit;
    reg                          round_bit;
    reg                          sticky_bit;
    reg                          round_up;
    reg [FRAC_WIDTH:0]           mantissa_rounded;
    reg                          found_one;
    integer                      i;

    always @(*) begin
        result_comb    = {EXP_WIDTH+FRAC_WIDTH+1{1'b0}};
        overflow_comb  = 1'b0;
        underflow_comb = 1'b0;
        invalid_comb   = 1'b0;
        norm_mant      = stage2_mant_product;
        norm_exp       = stage2_exp_sum;
        exp_after_round = stage2_exp_sum;
        mantissa_field = {FRAC_WIDTH{1'b0}};
        guard_bit      = 1'b0;
        round_bit      = 1'b0;
        sticky_bit     = 1'b0;
        round_up       = 1'b0;
        mantissa_rounded = {(FRAC_WIDTH+1){1'b0}};
        found_one      = 1'b0;
        
        if (stage2_is_nan) begin
            result_comb  = {1'b0, {EXP_WIDTH{1'b1}}, {FRAC_WIDTH{1'b0}}};
            if (FRAC_WIDTH > 0) begin
                result_comb[FRAC_WIDTH-1:0] = {1'b1, {FRAC_WIDTH-1{1'b0}}};
            end
            invalid_comb = 1'b1;
        end else if (stage2_is_inf) begin
            result_comb = {stage2_sign, {EXP_WIDTH{1'b1}}, {FRAC_WIDTH{1'b0}}};
        end else if (stage2_is_zero || (stage2_mant_product == {PROD_WIDTH{1'b0}})) begin
            result_comb = {stage2_sign, {EXP_WIDTH{1'b0}}, {FRAC_WIDTH{1'b0}}};
        end else begin
            norm_mant = stage2_mant_product;
            norm_exp  = stage2_exp_sum;

            if (norm_mant[PROD_WIDTH-1]) begin
                norm_mant = norm_mant >> 1;
                norm_exp  = norm_exp + 1'b1;
            end else begin
                found_one = 1'b0;
                for (i = 0; i < PROD_WIDTH-1; i = i + 1) begin
                    if (!found_one) begin
                        if (norm_mant[PROD_WIDTH-2]) begin
                            found_one = 1'b1;
                        end else begin
                            norm_mant = norm_mant << 1;
                            norm_exp  = norm_exp - 1'b1;
                        end
                    end
                end
            end

            mantissa_field = (INDEX_MSB >= INDEX_LSB) ?
                             norm_mant[INDEX_MSB:INDEX_LSB] :
                             {FRAC_WIDTH{1'b0}};
            guard_bit = (GUARD_INDEX >= 0) ? norm_mant[GUARD_INDEX] : 1'b0;
            round_bit = (ROUND_INDEX >= 0) ? norm_mant[ROUND_INDEX] : 1'b0;
            if (ROUND_INDEX > 0) begin
                sticky_bit = |norm_mant[ROUND_INDEX-1:0];
            end else begin
                sticky_bit = 1'b0;
            end

            if (FRAC_WIDTH > 0) begin
                round_up = guard_bit & (round_bit | sticky_bit | mantissa_field[0]);
            end else begin
                round_up = guard_bit & (round_bit | sticky_bit);
            end
            mantissa_rounded = {1'b0, mantissa_field} + { {FRAC_WIDTH{1'b0}}, round_up };

            exp_after_round = norm_exp;
            if (mantissa_rounded[FRAC_WIDTH]) begin
                mantissa_field   = mantissa_rounded[FRAC_WIDTH:1];
                exp_after_round  = norm_exp + 1'b1;
            end else begin
                mantissa_field = mantissa_rounded[FRAC_WIDTH-1:0];
            end

            if ($signed(exp_after_round) >= $signed(EXP_MAX[EXP_SUM_WIDTH:0])) begin
                result_comb   = {stage2_sign, {EXP_WIDTH{1'b1}}, {FRAC_WIDTH{1'b0}}};
                overflow_comb = 1'b1;
            end else if (exp_after_round <= 0) begin
                result_comb    = {stage2_sign, {EXP_WIDTH{1'b0}}, {FRAC_WIDTH{1'b0}}};
                underflow_comb = 1'b1;
            end else begin
                result_comb = {stage2_sign,
                               exp_after_round[EXP_WIDTH-1:0],
                               mantissa_field};
            end
        end

        if (stage2_invalid) begin
            invalid_comb = 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage3_valid<= 1'b0;
            result_o    <= {EXP_WIDTH+FRAC_WIDTH+1{1'b0}};
            fflags_o    <= 5'b0;
        end else begin
            stage3_valid <= stage2_valid;
            if (stage2_valid) begin
                result_o    <= result_comb;
                fflags_o    <= {1'b0, 1'b0, invalid_comb, underflow_comb, overflow_comb};
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
        else if(stage3_valid)
            out_valid_o <= 1'b1;
        else if(out_ready_i)
            out_valid_o <= 1'b0;
        else
            out_valid_o <= out_valid_o;
    end

endmodule

// Combinational multiplier used for mantissa products.
module naiveMultiplier #(
    parameter WIDTH = 24
) (
    input  wire [WIDTH-1:0]  in_a,
    input  wire [WIDTH-1:0]  in_b,
    output wire [2*WIDTH-1:0] product
);
    assign product = in_a * in_b;
endmodule
