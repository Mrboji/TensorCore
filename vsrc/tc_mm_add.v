`timescale 1ns/1ps
`default_nettype none

`include "tensor_core_params.svh"

// tc_mm_add ??????????
// - ?? 8x8 fp9(e5m3) ? 8x8 fp22(EXP=8,FRAC=14) ??? [row*8+col]
// - ???? fp9??? fp22 ????????? OUTPUT_MODE ??/??? fp8(E4M3)/fp16/fp32
// - ?????4 ? beat ?? 64 ????? 16 ?????? 512bit?fflags ???? beat ??
module tc_mm_add #(
  parameter MATRIX_BUS_WIDTH = `TC_MATRIX_BUS_WIDTH,
  parameter SHAPE_M          = `TC_SHAPE_M,
  parameter SHAPE_N          = `TC_SHAPE_N,
  parameter FP_AB_WIDTH      = `TC_FP_AB_WIDTH,
  parameter FP_C_MAX_WIDTH   = `TC_FP_C_MAX_WIDTH,
  parameter OUTPUT_MODE      = 2'b10            // 00:fp8(E4M3) 01:fp16 10:fp32?????
) (
  input  wire                         clk,             // ??
  input  wire                         rst_n,           // ?????
  input  wire [SHAPE_M*SHAPE_N*FP_AB_WIDTH-1:0]    c_v_fp9_i,      // 8x8 ?????fp9?????
  input  wire [SHAPE_M*SHAPE_N*FP_C_MAX_WIDTH-1:0] c_v_fp22_i,     // 8x8 ?????fp22?????
  input  wire [2:0]                   rm_i,            // ????????????
  input  wire [15:0]                  ctrl_c_i,        // ???????? C
  input  wire [2:0]                   ctrl_rm_i,       // ?????????
  input  wire [7:0]                   ctrl_reg_idxw_i, // ????????????
  input  wire [`TC_DEPTH_WARP-1:0]    ctrl_warpid_i,   // ?????Warp ID
  input  wire                         in_valid_i,      // ?????????
  input  wire                         out_ready_i,     // ??????????
  output wire                         in_ready_o,      // ??????????
  output wire                         out_valid_o,     // ?????????
  output wire [MATRIX_BUS_WIDTH-1:0]  result_o,        // 512bit ??????16 ??/beat
  output wire [4:0]                   fflags_o,        // {NV,OF,UF,DZ,NX} ?? beat ????
  output wire [15:0]                  ctrl_c_o,        // ????
  output wire [2:0]                   ctrl_rm_o,       // ????
  output wire [7:0]                   ctrl_reg_idxw_o, // ????
  output wire [`TC_DEPTH_WARP-1:0]    ctrl_warpid_o    // ????
);

  localparam ELEM_CNT       = SHAPE_M*SHAPE_N; // 64
  localparam FP9_EXP_BIAS   = 15;
  localparam FP22_EXP_BIAS  = 127;

  // ????
  assign ctrl_c_o        = ctrl_c_i;
  assign ctrl_rm_o       = ctrl_rm_i;
  assign ctrl_reg_idxw_o = ctrl_reg_idxw_i;
  assign ctrl_warpid_o   = ctrl_warpid_i;

  // ??
  reg busy;
  reg [1:0] beat;
  reg signed [31:0] sum_latch [0:ELEM_CNT-1];

  wire start = (~busy) & in_valid_i & out_ready_i; // ????
  assign in_ready_o  = ~busy;
  assign out_valid_o = busy;

  // fp9 ? ??????? fp22 ????????
  function signed [31:0] fp9_to_fixed;
    input [FP_AB_WIDTH-1:0] din;
    reg sign;
    reg [4:0] exp;
    reg [2:0] frac;
    integer e_unbias;
    reg [31:0] mant;
    begin
      sign = din[FP_AB_WIDTH-1];
      exp  = din[FP_AB_WIDTH-2:FP_AB_WIDTH-6];
      frac = din[2:0];
      if (exp == 0) begin
        e_unbias = 1 - FP9_EXP_BIAS;
        mant = {1'b0, frac, 14'd0};
      end else begin
        e_unbias = exp - FP9_EXP_BIAS;
        mant = {1'b1, frac, 14'd0};
      end
      if (e_unbias >= 0)
        fp9_to_fixed = sign ? -$signed(mant <<< e_unbias) : $signed(mant <<< e_unbias);
      else begin
        integer sh; 
        reg [31:0] tmp; 
        sh = -e_unbias; 
        tmp = mant >> sh; 
        fp9_to_fixed = sign ? -$signed(tmp) : $signed(tmp);
      end
    end
  endfunction

  // fp22 ? ???EXP=8, FRAC=14?
  function signed [31:0] fp22_to_fixed;
    input [FP_C_MAX_WIDTH-1:0] din;
    reg sign;
    reg [7:0] exp;
    reg [13:0] frac;
    integer e_unbias;
    reg [31:0] mant;
    begin
      sign = din[FP_C_MAX_WIDTH-1];
      exp  = din[FP_C_MAX_WIDTH-2:14];
      frac = din[13:0];

      if (exp == 0) begin e_unbias = 1 - FP22_EXP_BIAS; mant = {1'b0, frac}; end
      else begin e_unbias = exp - FP22_EXP_BIAS; mant = {1'b1, frac}; end
      if (e_unbias >= 0)
        fp22_to_fixed = sign ? -$signed(mant <<< e_unbias) : $signed(mant <<< e_unbias);
      else 
      begin 
        integer sh;
        reg [31:0] tmp; 
        sh = -e_unbias; 
        tmp = mant >> sh; 
        fp22_to_fixed = sign ? -$signed(tmp) : $signed(tmp); 
      end
    end
  endfunction

  // ???????/????????fp8/fp16/fp32???? 32bit ????
  function [31:0] pack_to_mode;
    input signed [31:0] val;
    input [1:0] mode;
    reg signed [31:0] vmax, vmin, vclip;
    begin
      case (mode)
        2'b00: begin // fp8 E4M3???????? exp=0xE, frac=0x7 ? 0xEF7
          vmax = 32'sh00000EF7; vmin = -32'sh00000EF7;
          vclip = (val > vmax) ? vmax : (val < vmin ? vmin : val);
          pack_to_mode = { {24{vclip[11]}}, vclip[11:4] };
        end
        2'b01: begin // fp16 ????? 0x7BFF
          vmax = 32'sh00007BFF; vmin = -32'sh00007BFF;
          vclip = (val > vmax) ? vmax : (val < vmin ? vmin : val);
          pack_to_mode = { {16{vclip[15]}}, vclip[15:0] };
        end
        default: begin // fp32 ????? 0x7F7FFFFF
          vmax = 32'sh7F7FFFFF; vmin = -32'sh7F7FFFFF;
          vclip = (val > vmax) ? vmax : (val < vmin ? vmin : val);
          pack_to_mode = vclip;
        end
      endcase
    end
  endfunction

  // ??? beat ?????????4 ??? 64 ??
  integer ii;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy <= 1'b0;
      beat <= 2'd0;
      for (ii = 0; ii < ELEM_CNT; ii = ii + 1) begin
        sum_latch[ii] <= 32'sd0;
      end
    end else if (start) begin
      busy <= 1'b1;
      beat <= 2'd0;
      for (ii = 0; ii < ELEM_CNT; ii = ii + 1) begin
        sum_latch[ii] <= fp9_to_fixed(c_v_fp9_i[FP_AB_WIDTH*ii +: FP_AB_WIDTH]) +
                         fp22_to_fixed(c_v_fp22_i[FP_C_MAX_WIDTH*ii +: FP_C_MAX_WIDTH]);
      end
    end else if (busy && out_ready_i) begin
      if (beat == 2'd3) begin
        busy <= 1'b0;
        beat <= 2'd0;
      end else begin
        beat <= beat + 1'b1;
      end
    end
  end

  // ?????? beat ? 16 ?????????OF/NX ?????????
  reg [MATRIX_BUS_WIDTH-1:0] result_bus;
  reg [4:0] fflags_bus;
  reg signed [31:0] packed_val;
  integer j;
  always @(*) begin
    result_bus = {MATRIX_BUS_WIDTH{1'b0}};
    fflags_bus = 5'b0;
    for (j = 0; j < 16; j = j + 1) begin
      packed_val = pack_to_mode(sum_latch[beat*16 + j], OUTPUT_MODE);
      result_bus[32*j +: 32] = packed_val;
      if (packed_val != sum_latch[beat*16 + j]) begin
        fflags_bus[3] = 1'b1; // OF
        fflags_bus[0] = 1'b1; // NX
      end
    end
  end

  assign result_o = result_bus;
  assign fflags_o = fflags_bus;

endmodule

`default_nettype wire
