module tc_mul #(
    parameter SHAPE_K       = 8,
    parameter ELEMENT_WIDTH = 9,
    parameter CTRL_C_WIDTH  = 16,
    parameter DEPTH_WARP    = 4
) (
    input  wire                              clk,
    input  wire                              rst_n,

    input  wire [SHAPE_K*ELEMENT_WIDTH-1:0]  a_i,
    input  wire [SHAPE_K*ELEMENT_WIDTH-1:0]  b_i,

    input  wire [2:0]                        rm_i,       
    input  wire [CTRL_C_WIDTH-1:0]           ctrl_c_i,   
    input  wire [2:0]                        ctrl_rm_i,  
    input  wire [7:0]                        ctrl_reg_idxw_i, 
    input  wire [DEPTH_WARP-1:0]             ctrl_warpid_i,   

    input  wire                              in_valid_i, 
    output reg                               in_ready_o, 
    
    output reg                               out_valid_o,
    input  wire                              out_ready_i, 

    output reg  [SHAPE_K*ELEMENT_WIDTH-1:0]  result_o,
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

wire [ELEMENT_WIDTH-1:0] a_lane         [0:SHAPE_K-1];
wire [ELEMENT_WIDTH-1:0] b_lane         [0:SHAPE_K-1];
wire [ELEMENT_WIDTH-1:0] result_lane    [0:SHAPE_K-1];
wire [4:0]               fflags_lane    [0:SHAPE_K-1];
wire                     in_ready_lane  [0:SHAPE_K-1];
wire                     out_valid_lane [0:SHAPE_K-1];

genvar i;
generate
    for (i = 0; i < SHAPE_K; i = i + 1) begin : SPLIT
        assign a_lane[i] = a_i[(i+1)*ELEMENT_WIDTH-1 -: ELEMENT_WIDTH];
        assign b_lane[i] = b_i[(i+1)*ELEMENT_WIDTH-1 -: ELEMENT_WIDTH];
        assign result_o[(i+1)*ELEMENT_WIDTH-1 -: ELEMENT_WIDTH] = result_lane[i];
    end
endgenerate

integer j;
reg [4:0] fflags_r;
reg       in_ready_r;
reg       out_valid_r;
always @(*) begin
    fflags_r    = 5'b0;
    in_ready_r  = 1'b1;
    out_valid_r = 1'b1;
    for (j = 0; j < SHAPE_K; j = j + 1) begin
        fflags_r    = fflags_r    | fflags_lane[j];
        in_ready_r  = in_ready_r  & in_ready_lane[j];
        out_valid_r = out_valid_r & out_valid_lane[j];
    end
end
assign fflags_o    = fflags_r;
assign in_ready_o  = in_ready_r;
assign out_valid_o = out_valid_r;


generate
    for (i = 0; i < SHAPE_K; i = i + 1) begin : MUL_INST
        fmul_pipe u_fmul_pipe (
        .clk(clk),
        .rst_n(rst_n),
        .a_i(a_lane[i]),
        .b_i(b_lane[i]),

        .rm_i(3'b0),       
        .ctrl_c_i({CTRL_C_WIDTH{1'b0}}),   
        .ctrl_rm_i(3'b0),  
        .ctrl_reg_idxw_i(8'b0), 
        .ctrl_warpid_i({DEPTH_WARP{1'b0}}),   

        .in_valid_i(in_valid_i), 
        .in_ready_o(in_ready_lane[i]), 
        .out_valid_o(out_valid_lane[i]),
        .out_ready_i(out_ready_i), 

        .result_o(result_lane[i]),
        .fflags_o(fflags_lane[i]),

        .ctrl_c_o(),   
        .ctrl_rm_o(), 
        .ctrl_reg_idxw_o(), 
        .ctrl_warpid_o()
    );
    end
endgenerate


endmodule


