module tc_mm_add #(
    parameter SHAPE_M           = 8,
    parameter SHAPE_N           = 8,
    parameter EXPWIDTH_MID      = 5,
    parameter PRECISION_MID     = 3,
    parameter ELEMENT_WIDTH_MID = 9,
    parameter EXPWIDTH_C        = 8,
    parameter PRECISION_C       = 13,
    parameter ELEMENT_WIDTH_C   = 22,
    parameter EXPWIDTH_OUT      = 4,
    parameter PRECISION_OUT     = 3,
    parameter ELEMENT_WIDTH_OUT = 8,
    parameter CTRL_C_WIDTH      = 16,
    parameter DEPTH_WARP        = 4
) (
    input  wire                              clk,
    input  wire                              rst_n,

    input  wire [SHAPE_M*SHAPE_N*ELEMENT_WIDTH_MID-1:0]  c_v_i,
    input  wire [SHAPE_M*SHAPE_N*ELEMENT_WIDTH_C-1:0]    matrix_c,

    input  wire [2:0]                        rm_i,       
    input  wire [CTRL_C_WIDTH-1:0]           ctrl_c_i,   
    input  wire [2:0]                        ctrl_rm_i,  
    input  wire [7:0]                        ctrl_reg_idxw_i, 
    input  wire [DEPTH_WARP-1:0]             ctrl_warpid_i,   

    input  wire                              in_valid_i, 
    output reg                               in_ready_o, 
    
    output reg                               out_valid_o,
    input  wire                              out_ready_i, 

    output reg  [SHAPE_M*SHAPE_N*8-1:0]      result_o,
    output reg  [4:0]                        fflags_o,

    output wire [CTRL_C_WIDTH-1:0]           ctrl_c_o,   
    output wire [2:0]                        ctrl_rm_o, 
    output wire [7:0]                        ctrl_reg_idxw_o, 
    output wire [DEPTH_WARP-1:0]             ctrl_warpid_o
);

assign ctrl_c_o        = ctrl_c_i;
assign ctrl_rm_o       = ctrl_rm_i;
assign ctrl_reg_idxw_o = ctrl_reg_idxw_i;
assign ctrl_warpid_o   = ctrl_warpid_i;

wire [ELEMENT_WIDTH_MID-1:0] c_v_lane_fp9   [0:SHAPE_M*SHAPE_N-1];
wire [ELEMENT_WIDTH_C-1:0]   c_v_lane_fp22  [0:SHAPE_M*SHAPE_N-1];
wire [ELEMENT_WIDTH_C-1:0]   matrix_c_lane  [0:SHAPE_M*SHAPE_N-1];
wire [ELEMENT_WIDTH_C-1:0] result_fp22_lane [0:SHAPE_M*SHAPE_N-1];
wire                         in_ready_lane  [0:SHAPE_M*SHAPE_N-1];
wire                         out_valid_lane [0:SHAPE_M*SHAPE_N-1];
wire [4:0]                   fflags_lane    [0:SHAPE_M*SHAPE_N-1];
wire [ELEMENT_WIDTH_OUT-1:0] result_lane    [0:SHAPE_M*SHAPE_N-1];
wire [SHAPE_M*SHAPE_N*ELEMENT_WIDTH_OUT-1:0] result_out;

genvar i;
generate
    for (i = 0; i < SHAPE_M*SHAPE_N; i = i + 1) begin : SPLIT
        assign c_v_lane_fp9[i]  = c_v_i[(i+1)*ELEMENT_WIDTH_MID-1 -: ELEMENT_WIDTH_MID];
        assign matrix_c_lane[i] = matrix_c[(i+1)*ELEMENT_WIDTH_C-1 -: ELEMENT_WIDTH_C];
        assign result_out[(i+1)*ELEMENT_WIDTH_OUT-1 -: ELEMENT_WIDTH_OUT] = result_lane[i];
    end
endgenerate

assign result_o = result_out;

genvar j;
generate
    for (j = 0; j < SHAPE_M*SHAPE_N; j = j + 1) begin : SPLIT_TRAN
        precision_tran #(
            .EXP_WIDTH_IN(EXPWIDTH_MID),
            .FRAC_WIDTH_IN(PRECISION_MID),
            .ELEMENT_WIDTH_IN(ELEMENT_WIDTH_MID),
            .EXP_WIDTH_OUT(EXPWIDTH_C),
            .FRAC_WIDTH_OUT(PRECISION_C),
            .ELEMENT_WIDTH_OUT(ELEMENT_WIDTH_C)
        ) u_precision_tran_in (
            .float_num_in(c_v_lane_fp9[j]),
            .float_num_out(c_v_lane_fp22[j]),

            .invalid(),
            .overflow(),
            .underflow()
        );
    end
endgenerate

integer q;
reg [4:0] fflags_r;
reg       in_ready_r;
reg       out_valid_r;
always @(*) begin
    fflags_r    = 5'b0;
    in_ready_r  = 1'b1;
    out_valid_r = 1'b1;
    for (q = 0; q < SHAPE_M*SHAPE_N; q = q + 1) begin
        fflags_r    = fflags_r    | fflags_lane[q];
        in_ready_r  = in_ready_r  & in_ready_lane[q];
        out_valid_r = out_valid_r & out_valid_lane[q];
    end
end
assign fflags_o    = fflags_r;
assign in_ready_o  = in_ready_r;
assign out_valid_o = out_valid_r;

genvar k;
generate
    for (k = 0; k < SHAPE_M*SHAPE_N; k = k + 1) begin : SPLIT_ADD
        fadd_pipe #(
            .EXPWIDTH(8),
            .PRECISION(13),
            .CTRL_C_WIDTH(16),
            .DEPTH_WARP(4)
        )u_fadd_pipe(
            .clk(clk),
            .rst_n(rst_n),

            .a_i(c_v_lane_fp22[k]),
            .b_i(matrix_c_lane[k]),

            .rm_i(3'b0),       
            .ctrl_c_i({CTRL_C_WIDTH{1'b0}}),   
            .ctrl_rm_i(3'b0),  
            .ctrl_reg_idxw_i(8'b0), 
            .ctrl_warpid_i({DEPTH_WARP{1'b0}}),    

            .in_valid_i(in_valid_i), 
            .in_ready_o(in_ready_lane[k]), 
            
            .out_valid_o(out_valid_lane[k]),
            .out_ready_i(out_ready_i), 

            .result_o(result_fp22_lane[k]),
            .fflags_o(fflags_lane[k]),

            .ctrl_c_o(),   
            .ctrl_rm_o(), 
            .ctrl_reg_idxw_o(), 
            .ctrl_warpid_o()
        );
    end
endgenerate

genvar p;
generate
    for (p = 0; p < SHAPE_M*SHAPE_N; p = p + 1) begin : SPLIT_TRAN
        precision_tran #(
            .EXP_WIDTH_IN(EXPWIDTH_C),
            .FRAC_WIDTH_IN(PRECISION_C),
            .ELEMENT_WIDTH_IN(ELEMENT_WIDTH_C),
            .EXP_WIDTH_OUT(EXPWIDTH_OUT),
            .FRAC_WIDTH_OUT(PRECISION_OUT),
            .ELEMENT_WIDTH_OUT(ELEMENT_WIDTH_OUT)
        ) u_precision_tran_out (
            .float_num_in(result_fp22_lane[p]),
            .float_num_out(result_lane[p]),

            .invalid(),
            .overflow(),
            .underflow()
        );
    end
endgenerate


endmodule
