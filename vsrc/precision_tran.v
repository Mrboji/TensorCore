module precision_tran #(
    parameter EXP_WIDTH_IN      = 4,
    parameter FRAC_WIDTH_IN     = 3,
    parameter ELEMENT_WIDTH_IN  = EXP_WIDTH_IN + FRAC_WIDTH_IN + 1,
    parameter EXP_WIDTH_OUT     = 5,
    parameter FRAC_WIDTH_OUT    = 3,
    parameter ELEMENT_WIDTH_OUT = EXP_WIDTH_OUT + FRAC_WIDTH_OUT + 1
) (
    input      [EXP_WIDTH_IN + FRAC_WIDTH_IN : 0]  float_num_in,
    output reg [EXP_WIDTH_OUT + FRAC_WIDTH_OUT : 0] float_num_out,

    output reg invalid,
    output reg overflow,
    output reg underflow
);

parameter  LENGTH_ALIGN = 64;

localparam BIAS_IN  = (1 << (EXP_WIDTH_IN  - 1)) - 1;
localparam BIAS_OUT = (1 << (EXP_WIDTH_OUT - 1)) - 1;


wire sign_in;
wire [LENGTH_ALIGN-1:0] exp_in;
wire [LENGTH_ALIGN-1:0] frac_in;

reg [LENGTH_ALIGN-1:0] exp_out;
reg [LENGTH_ALIGN-1:0] frac_out;

assign sign_in = float_num_in[EXP_WIDTH_IN + FRAC_WIDTH_IN];
assign exp_in  = {{LENGTH_ALIGN-EXP_WIDTH_IN{1'b0}}, float_num_in[EXP_WIDTH_IN + FRAC_WIDTH_IN - 1 : FRAC_WIDTH_IN]};
assign frac_in = {{LENGTH_ALIGN-FRAC_WIDTH_IN{1'b0}}, float_num_in[FRAC_WIDTH_IN - 1 : 0]};

wire exp_all_zeros = (exp_in == 0);
wire exp_all_ones  = (&exp_in[EXP_WIDTH_IN-1:0]);
wire frac_is_zero  = (frac_in == 0);

wire is_zero = exp_all_zeros && frac_is_zero;
wire is_subnormal = exp_all_zeros && !frac_is_zero;
wire is_inf  = exp_all_ones && frac_is_zero;
wire is_nan  = exp_all_ones && !frac_is_zero;

wire exp_in_large = EXP_WIDTH_IN > EXP_WIDTH_OUT;
wire exp_in_small = EXP_WIDTH_IN < EXP_WIDTH_OUT;
wire exp_equal    = EXP_WIDTH_IN == EXP_WIDTH_OUT;

wire frac_in_large = FRAC_WIDTH_IN > FRAC_WIDTH_OUT;
wire frac_in_small = FRAC_WIDTH_IN < FRAC_WIDTH_OUT;
wire frac_equal    = FRAC_WIDTH_IN == FRAC_WIDTH_OUT;

always @(*) begin
    float_num_out = {ELEMENT_WIDTH_OUT{1'b0}};
    invalid   = 1'b0;
    overflow  = 1'b0;
    underflow = 1'b0;
    exp_out   = {LENGTH_ALIGN{1'b0}};
    frac_out  = {LENGTH_ALIGN{1'b0}};
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
    else if (is_zero || is_subnormal) begin
        float_num_out = {
            sign_in,
            {EXP_WIDTH_OUT{1'b0}},
            {FRAC_WIDTH_OUT{1'b0}}
        };
    end
    else begin
        exp_out  = exp_in_small ? exp_in + BIAS_OUT - BIAS_IN :
                   exp_equal    ? exp_in :
                   exp_in_large ? (
                    exp_in >  BIAS_OUT + BIAS_IN ? {LENGTH_ALIGN{1'b1}} :
                    exp_in <= BIAS_IN - BIAS_OUT ? {LENGTH_ALIGN{1'b0}} :
                    exp_in - BIAS_IN + BIAS_OUT
                   ) : {LENGTH_ALIGN{1'b0}};
                   
        frac_out = exp_out == {LENGTH_ALIGN{1'b1}} ? {LENGTH_ALIGN{1'b0}} :
                   exp_out == {LENGTH_ALIGN{1'b0}} ? {LENGTH_ALIGN{1'b0}} :
                   frac_in_large ? {{LENGTH_ALIGN-FRAC_WIDTH_OUT{1'b0}}, frac_in[FRAC_WIDTH_IN-1 : FRAC_WIDTH_IN-FRAC_WIDTH_OUT]} :
                   frac_equal    ? frac_in :
                   frac_in_small ? {frac_in[LENGTH_ALIGN-FRAC_WIDTH_OUT+FRAC_WIDTH_IN-1:0], {FRAC_WIDTH_OUT-FRAC_WIDTH_IN{1'b0}}} : 
                   {LENGTH_ALIGN{1'b0}};
        float_num_out = {sign_in, exp_out[EXP_WIDTH_OUT-1:0], frac_out[FRAC_WIDTH_OUT-1:0]};
    end
end

endmodule
