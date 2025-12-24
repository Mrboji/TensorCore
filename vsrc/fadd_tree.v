module fadd_tree #(
    parameter SHAPE_K       = 8,
    parameter ELEMENT_WIDTH = 9,
    parameter CTRL_C_WIDTH  = 16,
    parameter DEPTH_WARP    = 4
)(
    input  wire                              clk,
    input  wire                              rst_n,

    input  wire [SHAPE_K*ELEMENT_WIDTH-1:0]  data_i,

    input  wire [2:0]                        rm_i,       
    input  wire [CTRL_C_WIDTH-1:0]           ctrl_c_i,   
    input  wire [2:0]                        ctrl_rm_i,  
    input  wire [7:0]                        ctrl_reg_idxw_i, 
    input  wire [DEPTH_WARP-1:0]             ctrl_warpid_i,   

    input  wire                              in_valid_i, 
    output reg                               in_ready_o, 
    
    output reg                               out_valid_o,
    input  wire                              out_ready_i, 

    output reg  [ELEMENT_WIDTH-1:0]          result_o,
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

wire [ELEMENT_WIDTH-1:0] data_lane         [0:SHAPE_K-1];
wire [ELEMENT_WIDTH-1:0] data_min          [0:SHAPE_K/2-1];
wire [ELEMENT_WIDTH-1:0] data_high         [0:SHAPE_K/4-1];
wire                     in_ready_lane_low [0:SHAPE_K/2-1];
wire                     out_valid_lane_low[0:SHAPE_K/2-1];
wire                     in_ready_lane_min [0:SHAPE_K/4-1];
wire                     out_valid_lane_min[0:SHAPE_K/4-1];
wire                     in_ready_high;


genvar i;
generate
    for (i = 0; i < SHAPE_K; i = i + 1) begin : SPLIT
        assign data_lane[i] = data_i[(i+1)*ELEMENT_WIDTH-1 -: ELEMENT_WIDTH];
    end
endgenerate

integer j;
reg       in_ready_r;
reg       out_valid_r;
always @(*) begin
    in_ready_r  = 1'b1;
    out_valid_r = 1'b1;
    for (j = 0; j < SHAPE_K/2; j = j + 1) begin
        in_ready_r  = in_ready_r  & in_ready_lane_low[j];
        out_valid_r = out_valid_r & out_valid_lane_low[j];
    end
end
assign in_ready_o  = in_ready_r;
wire   out_valid_low = out_valid_r;

integer k;
reg       in_ready_r_min;
reg       out_valid_r_min;
always @(*) begin
    in_ready_r_min  = 1'b1;
    out_valid_r_min = 1'b1;
    for (k = 0; k < SHAPE_K/4; k = k + 1) begin
        in_ready_r_min  = in_ready_r_min  & in_ready_lane_min[k];
        out_valid_r_min = out_valid_r_min & out_valid_lane_min[k];
    end
end
wire in_ready_min = in_ready_r_min;
wire out_valid_min = out_valid_r_min;

generate
    for (i = 0; i < SHAPE_K/2; i = i + 1) begin : ADD_INST_LOW
        fadd_pipe u_add_pipe_low(
            .clk(clk),
            .rst_n(rst_n),

            .a_i(data_lane[i]),
            .b_i(data_lane[i+4]),

            .rm_i(3'b0),       
            .ctrl_c_i({CTRL_C_WIDTH{1'b0}}),   
            .ctrl_rm_i(3'b0),  
            .ctrl_reg_idxw_i(8'b0), 
            .ctrl_warpid_i({DEPTH_WARP{1'b0}}),    

            .in_valid_i(in_valid_i), 
            .in_ready_o(in_ready_lane_low[i]), 
            
            .out_valid_o(out_valid_lane_low[i]),
            .out_ready_i(in_ready_min), 

            .result_o(data_min[i]),
            .fflags_o(),

            .ctrl_c_o(),   
            .ctrl_rm_o(), 
            .ctrl_reg_idxw_o(), 
            .ctrl_warpid_o()
        );
    end
endgenerate

generate
    for (i = 0; i < SHAPE_K/4; i = i + 1) begin : ADD_INST_MIN
        fadd_pipe u_add_pipe_min(
            .clk(clk),
            .rst_n(rst_n),

            .a_i(data_min[i]),
            .b_i(data_min[i+2]),

            .rm_i(3'b0),       
            .ctrl_c_i({CTRL_C_WIDTH{1'b0}}),   
            .ctrl_rm_i(3'b0),  
            .ctrl_reg_idxw_i(8'b0), 
            .ctrl_warpid_i({DEPTH_WARP{1'b0}}),    

            .in_valid_i(out_valid_low), 
            .in_ready_o(in_ready_lane_min[i]), 
            
            .out_valid_o(out_valid_lane_min[i]),
            .out_ready_i(in_ready_high), 

            .result_o(data_high[i]),
            .fflags_o(),

            .ctrl_c_o(),   
            .ctrl_rm_o(), 
            .ctrl_reg_idxw_o(), 
            .ctrl_warpid_o()
        );
    end
endgenerate

fadd_pipe u_add_pipe_high(
    .clk(clk),
    .rst_n(rst_n),

    .a_i(data_high[0]),
    .b_i(data_high[1]),

    .rm_i(3'b0),       
    .ctrl_c_i({CTRL_C_WIDTH{1'b0}}),   
    .ctrl_rm_i(3'b0),  
    .ctrl_reg_idxw_i(8'b0), 
    .ctrl_warpid_i({DEPTH_WARP{1'b0}}),    

    .in_valid_i(out_valid_min), 
    .in_ready_o(in_ready_high), 
    
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


