module fp1684_to_fp9 #(
    parameter EXP_WIDTH_IN      = 4,
    parameter FRAC_WIDTH_IN     = 3,
    parameter ELEMENT_WIDTH_IN  = EXP_WIDTH_IN + FRAC_WIDTH_IN + 1,
    parameter EXP_WIDTH_OUT     = 5,
    parameter FRAC_WIDTH_OUT    = 3,
    parameter ELEMENT_WIDTH_OUT = EXP_WIDTH_OUT + FRAC_WIDTH_OUT + 1
) (
    input      [4:0]   type_cd_i,
    input      [EXP_WIDTH_IN + FRAC_WIDTH_IN : 0]  float_num_in,
    output reg [EXP_WIDTH_OUT + FRAC_WIDTH_OUT : 0] float_num_out,

    output reg invalid,
    output reg overflow,
    output reg underflow
);

localparam TYPE_FP4  = 5'd0;
localparam TYPE_FP8  = 5'd1;
localparam TYPE_FP16 = 5'd2;
    
localparam BIAS_IN  = (1 << (EXP_WIDTH_IN  - 1)) - 1;
localparam BIAS_OUT = (1 << (EXP_WIDTH_OUT - 1)) - 1;

wire is_fp4_in  = (type_cd_i == TYPE_FP4);
wire is_fp8_in  = (type_cd_i == TYPE_FP8);
wire is_fp16_in = (type_cd_i == TYPE_FP16);

wire sign_in;
wire [EXP_WIDTH_IN-1:0]  exp_in;
wire [FRAC_WIDTH_IN-1:0] frac_in;

reg [EXP_WIDTH_OUT-1:0]  exp_out;
reg [FRAC_WIDTH_OUT-1:0] frac_out;

assign sign_in = float_num_in[EXP_WIDTH_IN + FRAC_WIDTH_IN];
assign exp_in  = float_num_in[EXP_WIDTH_IN + FRAC_WIDTH_IN - 1 : FRAC_WIDTH_IN];
assign frac_in = float_num_in[FRAC_WIDTH_IN - 1 : 0];

wire exp_all_zeros = (exp_in == 0);
wire exp_all_ones  = (&exp_in);
wire frac_is_zero  = (frac_in == 0);

wire is_zero = exp_all_zeros && frac_is_zero;
wire is_subnormal = exp_all_zeros && !frac_is_zero;
wire is_inf  = exp_all_ones && frac_is_zero;
wire is_nan  = exp_all_ones && !frac_is_zero;

always @(*) begin
    float_num_out = 0;
    invalid   = 1'b0;
    overflow  = 1'b0;
    underflow = 1'b0;
    if (is_nan) begin
        invalid = 1'b1;
        float_num_out = {
            sign_in,
            {EXP_WIDTH_OUT{1'b1}},
            {1'b1, {FRAC_WIDTH_OUT-1{1'b0}}} 
        };
    end
    else if (is_inf) begin
        float_num_out = {
            sign_in,
            {EXP_WIDTH_OUT{1'b1}},
            {FRAC_WIDTH_OUT{1'b0}}
        };
    end
    else if (is_zero) begin
        float_num_out = {
            sign_in,
            {EXP_WIDTH_OUT{1'b0}},
            {FRAC_WIDTH_OUT{1'b0}}
        };
    end
    else if (is_subnormal) begin
        exp_out  = is_fp4_in ? 5'd14 :
                   is_fp8_in ? ((frac_in[2] == 1'b1) ? 5'd8 : 
                                (frac_in[2] == 1'b0) && (frac_in[1] == 1'b1) ? 5'd7 : 5'd6) :
                   is_fp16_in ? exp_in : 5'b0;
        frac_out = is_fp4_in ? 3'd0 :
                   is_fp8_in ? ((frac_in[2] == 1'b1) ? {frac_in[1:0],1'b0} : 
                                (frac_in[2] == 1'b0) && (frac_in[1] == 1'b1) ? {frac_in[0], 2'b0} : 3'd0) :
                   is_fp16_in ? frac_in[9:7] : 3'b0;
        float_num_out = {sign_in, exp_out, frac_out};
    end
    else begin
        exp_out  = is_fp4_in ? {3'b0, exp_in} + BIAS_OUT - BIAS_IN :
                   is_fp8_in ? {1'b0, exp_in} + BIAS_OUT - BIAS_IN :
                   is_fp16_in ? exp_in : 5'b0;
        frac_out = is_fp4_in ? {frac_in[0], 2'b0} :
                   is_fp8_in ? frac_in:
                   is_fp16_in ? frac_in[9:7] : 3'b0;
        float_num_out = {sign_in, exp_out, frac_out};
    end
end

endmodule

