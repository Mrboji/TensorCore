module mm_mul_add #(
    parameter SHAPE_M       = 8,
    parameter SHAPE_N       = 8,
    parameter SHAPE_K       = 8,
    parameter ELEMENT_WIDTH_AB = 9,
    parameter ELEMENT_WIDTH_C  = 22,
    parameter CTRL_C_WIDTH  = 16,
    parameter DEPTH_WARP    = 4
) (
    input  wire                              clk,
    input  wire                              rst_n,

    input  wire [SHAPE_M*SHAPE_N*ELEMENT_WIDTH_AB-1:0]  a_i,
    input  wire [SHAPE_N*SHAPE_K*ELEMENT_WIDTH_AB-1:0]  b_i,
    input  wire [SHAPE_M*SHAPE_K*ELEMENT_WIDTH_C-1:0]   c_i,

    input  wire [2:0]                        rm_i,       
    input  wire [7:0]                        ctrl_reg_idxw_i, 
    input  wire [DEPTH_WARP-1:0]             ctrl_warpid_i,   

    input  wire                              in_valid_i, 
    output reg                               in_ready_o, 
    
    output reg                               out_valid_o,
    input  wire                              out_ready_i, 

    output reg  [SHAPE_M*SHAPE_K*8-1:0]      result_o,
    output reg  [4:0]                        fflags_o
);

wire [SHAPE_M*SHAPE_K*ELEMENT_WIDTH_AB-1:0]  matrix_midle;
wire [SHAPE_M*SHAPE_K*ELEMENT_WIDTH_AB-1:0]  result_midle;

wire [SHAPE_M*ELEMENT_WIDTH_AB-1:0] b_lane         [0:SHAPE_K-1];
wire [SHAPE_M*ELEMENT_WIDTH_AB-1:0] result_lane    [0:SHAPE_K-1];
wire [4:0]                          fflags_lane    [0:SHAPE_K-1];
wire                                in_ready_lane  [0:SHAPE_K-1];
wire                                out_valid_lane [0:SHAPE_K-1];

genvar i;
generate
    for (i = 0; i < SHAPE_K; i = i + 1) begin : SPLIT
        assign b_lane[i] = b_i[(i+1)*SHAPE_N*ELEMENT_WIDTH_AB-1 -: SHAPE_N*ELEMENT_WIDTH_AB];
        assign result_midle[(i+1)*SHAPE_M*ELEMENT_WIDTH_AB-1 -: SHAPE_M*ELEMENT_WIDTH_AB] = result_lane[i];
    end
endgenerate

genvar p, q;
generate
    for (p = 0; p < SHAPE_M; p = p + 1) begin  
        for (q = 0; q < SHAPE_K; q = q + 1) begin
            assign matrix_midle[p * SHAPE_K * ELEMENT_WIDTH_AB + q * ELEMENT_WIDTH_AB +: ELEMENT_WIDTH_AB] = result_midle[q * SHAPE_M * ELEMENT_WIDTH_AB + p * ELEMENT_WIDTH_AB +: ELEMENT_WIDTH_AB];
        end
    end
endgenerate

integer j;
reg       in_ready_r;
reg       out_valid_r;
always @(*) begin
    in_ready_r  = 1'b1;
    out_valid_r = 1'b1;
    for (j = 0; j < SHAPE_M; j = j + 1) begin
        in_ready_r  = in_ready_r  & in_ready_lane[j];
        out_valid_r = out_valid_r & out_valid_lane[j];
    end
end
assign in_ready_o  = in_ready_r;
wire   out_valid_mv_mul = out_valid_r;
wire   in_ready_tc_mm_add;

generate
    for (i = 0; i < SHAPE_K; i = i + 1) begin : MV_MUL_INST
        mv_mul u_mv_mul (
        .clk(clk),
        .rst_n(rst_n),
        .a_i(a_i),
        .b_i(b_lane[i]),

        .rm_i(3'b0),       
        .ctrl_reg_idxw_i(8'b0), 
        .ctrl_warpid_i({DEPTH_WARP{1'b0}}),   

        .in_valid_i(in_valid_i), 
        .in_ready_o(in_ready_lane[i]), 
        .out_valid_o(out_valid_lane[i]),
        .out_ready_i(in_ready_tc_mm_add), 

        .result_o(result_lane[i]),
        .fflags_o(fflags_lane[i])
    );
    end
endgenerate

tc_mm_add u_tc_mm_add(
    .clk(clk),
    .rst_n(rst_n),

    .c_v_i(matrix_midle),
    .matrix_c(c_i),

    .rm_i(3'b0),       
    .ctrl_c_i({CTRL_C_WIDTH{1'b0}}),   
    .ctrl_rm_i(3'b0),  
    .ctrl_reg_idxw_i(8'b0), 
    .ctrl_warpid_i({DEPTH_WARP{1'b0}}),    

    .in_valid_i(out_valid_mv_mul), 
    .in_ready_o(in_ready_tc_mm_add), 
    
    .out_valid_o(out_valid_o),
    .out_ready_i(out_ready_i), 

    .result_o(result_o),
    .fflags_o(fflags_o),

    .ctrl_c_o(),   
    .ctrl_rm_o(), 
    .ctrl_reg_idxw_o(), 
    .ctrl_warpid_o()
);

endmodule


