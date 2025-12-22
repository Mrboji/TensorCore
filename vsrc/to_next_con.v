// module to_next_con #(
//     parameter EXP_WIDTH_IN      = 4,
//     parameter FRAC_WIDTH_IN     = 3,
//     parameter ELEMENT_WIDTH_IN  = EXP_WIDTH + FRAC_WIDTH + 1,
//     parameter NUM_ELEMET        = 512 / ELEMENT_WIDTH_IN,
//     parameter EXP_WIDTH_OUT     = 5,
//     parameter FRAC_WIDTH_OUT    = 3,
//     parameter ELEMENT_WIDTH_OUT = EXP_WIDTH + FRAC_WIDTH + 1
// )(
//     input  [4:0]   type_cd_i,

//     input  [511:0] c_i,
//     output [64*ELEMENT_WIDTH] c_o
// );

// localparam TYPE_FP4  = 5'd0;
// localparam TYPE_FP8  = 5'd1;
// localparam TYPE_FP16 = 5'd2;

// // wire [3:0] exp_width_in = (type_cd_i == TYPE_FP4)  ? 4'd2 :
// //                           (type_cd_i == TYPE_FP8)  ? 4'd4 :
// //                           (type_cd_i == TYPE_FP16) ? 4'd5 : 4'd0;

// // wire [3:0] frac_width_in = (type_cd_i == TYPE_FP4)  ? 4'd1 :
// //                            (type_cd_i == TYPE_FP8)  ? 4'd3 :
// //                            (type_cd_i == TYPE_FP16) ? 4'd10 : 4'd0;

// wire [ELEMENT_WIDTH_IN-1 : 0] c_i_lane [0 : NUM_ELEMET - 1];

// genvar i;
// generate
//     for( i = 0; i < NUM_ELEMET; i++)begin
//         assign c_i_lane[i] = c_i[(i+1)*ELEMENT_WIDTH_IN-1 -: ELEMENT_WIDTH_IN];
//     end
// endgenerate




// endmodule




