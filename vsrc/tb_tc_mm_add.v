`timescale 1ns/1ps
`default_nettype none

`include "tensor_core_params.svh"

// tc_mm_add ????? tb???? txt ????/???
module tb_tc_mm_add;
  // ????????????? icarus??? +DATA_DIR=... ??
  reg [1023:0] data_dir;
  reg [1023:0] file_fp9;
  reg [1023:0] file_fp22;
  reg [1023:0] file_expect;

  localparam SHAPE_M        = `TC_SHAPE_M;
  localparam SHAPE_N        = `TC_SHAPE_N;
  localparam FP_AB_WIDTH    = `TC_FP_AB_WIDTH;
  localparam FP_C_MAX_WIDTH = `TC_FP_C_MAX_WIDTH;
  localparam MAT_ELEM       = SHAPE_M*SHAPE_N;           // 64
  localparam FP9_BUS_W      = MAT_ELEM*FP_AB_WIDTH;
  localparam FP22_BUS_W     = MAT_ELEM*FP_C_MAX_WIDTH;
  localparam MATRIX_BUS_W   = `TC_MATRIX_BUS_WIDTH;      // 512
  localparam VEC_NUM        = 3;                         // ????????

  reg                       clk;
  reg                       rst_n;
  reg  [FP9_BUS_W-1:0]      c_v_fp9_i;
  reg  [FP22_BUS_W-1:0]     c_v_fp22_i;
  reg  [2:0]                rm_i;
  reg  [15:0]               ctrl_c_i;
  reg  [2:0]                ctrl_rm_i;
  reg  [7:0]                ctrl_reg_idxw_i;
  reg  [`TC_DEPTH_WARP-1:0] ctrl_warpid_i;
  reg                       in_valid_i;
  reg                       out_ready_i;
  wire                      in_ready_o;
  wire                      out_valid_o;
  wire [MATRIX_BUS_W-1:0]   result_o;
  wire [4:0]                fflags_o;
  wire [15:0]               ctrl_c_o;
  wire [2:0]                ctrl_rm_o;
  wire [7:0]                ctrl_reg_idxw_o;
  wire [`TC_DEPTH_WARP-1:0] ctrl_warpid_o;

  // DUT
  tc_mm_add #(
    .OUTPUT_MODE(2'b10) // fp32
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .c_v_fp9_i(c_v_fp9_i),
    .c_v_fp22_i(c_v_fp22_i),
    .rm_i(rm_i),
    .ctrl_c_i(ctrl_c_i),
    .ctrl_rm_i(ctrl_rm_i),
    .ctrl_reg_idxw_i(ctrl_reg_idxw_i),
    .ctrl_warpid_i(ctrl_warpid_i),
    .in_valid_i(in_valid_i),
    .out_ready_i(out_ready_i),
    .in_ready_o(in_ready_o),
    .out_valid_o(out_valid_o),
    .result_o(result_o),
    .fflags_o(fflags_o),
    .ctrl_c_o(ctrl_c_o),
    .ctrl_rm_o(ctrl_rm_o),
    .ctrl_reg_idxw_o(ctrl_reg_idxw_o),
    .ctrl_warpid_o(ctrl_warpid_o)
  );

  // ??
  initial clk = 1'b0;
  always #5 clk = ~clk; // 100MHz

  // ??????
  reg [FP_AB_WIDTH-1:0]    mem_fp9   [0:VEC_NUM*MAT_ELEM-1];
  reg [FP_C_MAX_WIDTH-1:0] mem_fp22  [0:VEC_NUM*MAT_ELEM-1];
  reg [31:0]               mem_expect[0:VEC_NUM*MAT_ELEM-1];

  integer txn;
  integer beat_cnt;
  integer j;
  integer err_cnt;

  task load_txn(input integer t);
    integer idx;
    begin
      for (idx = 0; idx < MAT_ELEM; idx = idx + 1) begin
        c_v_fp9_i[FP_AB_WIDTH*idx +: FP_AB_WIDTH]   = mem_fp9[t*MAT_ELEM + idx];
        c_v_fp22_i[FP_C_MAX_WIDTH*idx +: FP_C_MAX_WIDTH] = mem_fp22[t*MAT_ELEM + idx];
      end
    end
  endtask

  function [31:0] expect_word;
    input integer t;
    input integer elem;
    begin
      expect_word = mem_expect[t*MAT_ELEM + elem];
    end
  endfunction

  initial begin
    $dumpfile("tb_tc_mm_add_file.vcd");
    $dumpvars(0, tb_tc_mm_add);

    // ???? + ??????? +DATA_DIR=... ???
    data_dir    = "icarus";
    if ($value$plusargs("DATA_DIR=%s", data_dir)) begin
      $display("DATA_DIR override: %0s", data_dir);
    end
    file_fp9    = {data_dir, "/tc_mm_add_fp9.txt"};
    file_fp22   = {data_dir, "/tc_mm_add_fp22.txt"};
    file_expect = {data_dir, "/tc_mm_add_expect.txt"};

    if ($readmemh(file_fp9, mem_fp9) == 0) begin
      $display("ERROR: cannot read %0s", file_fp9); $finish;
    end
    if ($readmemh(file_fp22, mem_fp22) == 0) begin
      $display("ERROR: cannot read %0s", file_fp22); $finish;
    end
    if ($readmemh(file_expect, mem_expect) == 0) begin
      $display("ERROR: cannot read %0s", file_expect); $finish;
    end

    // init
    rst_n = 1'b0;
    in_valid_i = 1'b0;
    out_ready_i = 1'b0;
    c_v_fp9_i = {FP9_BUS_W{1'b0}};
    c_v_fp22_i = {FP22_BUS_W{1'b0}};
    rm_i = 3'd0;
    ctrl_c_i = 16'h0;
    ctrl_rm_i = 3'd0;
    ctrl_reg_idxw_i = 8'h0;
    ctrl_warpid_i = {`TC_DEPTH_WARP{1'b0}};
    err_cnt = 0;
    #30;
    rst_n = 1'b1;
    #20;

    out_ready_i = 1'b1;

    for (txn = 0; txn < VEC_NUM; txn = txn + 1) begin
      load_txn(txn);
      ctrl_c_i = txn;
      ctrl_reg_idxw_i = txn;
      ctrl_warpid_i = txn;

      @(posedge clk);
      while (!in_ready_o) @(posedge clk);
      in_valid_i = 1'b1;
      @(posedge clk);
      in_valid_i = 1'b0;

      beat_cnt = 0;
      while (beat_cnt < 4) begin
        @(posedge clk);
        if (out_valid_o && out_ready_i) begin
          // ???? beat ? 16 ???
          for (j = 0; j < 16; j = j + 1) begin
            if (result_o[32*j +: 32] !== expect_word(txn, beat_cnt*16 + j)) begin
              $display("[ERR][t=%0t] txn %0d beat %0d elem %0d exp=%h got=%h", $time, txn, beat_cnt, j,
                       expect_word(txn, beat_cnt*16 + j), result_o[32*j +: 32]);
              err_cnt = err_cnt + 1;
            end
          end
          $display("[OK ][t=%0t] txn %0d beat %0d fflags=%b", $time, txn, beat_cnt, fflags_o);
          beat_cnt = beat_cnt + 1;
        end
        if (beat_cnt == 2) begin
          out_ready_i = 1'b0; @(posedge clk); out_ready_i = 1'b1; // ???? backpressure
        end
      end
    end

    #50;
    $display("tb finished, err_cnt=%0d", err_cnt);
    $finish;
  end

endmodule

`default_nettype wire
