////////////////////
//尾数相乘：
//naivemultiplier 用 4 位乘法直接输出，对应 LEN=4 的要求。
/////////////////////////////////
`timescale 1ns/1ps
`default_nettype none

module naivemultiplier #(
  parameter LEN = 4
) (
  input  wire             regenable,       // 寄存器使能
  input  wire [LEN-1:0]   s_axis_tdata_a,  // 操作数 A 尾数
  input  wire [LEN-1:0]   s_axis_tdata_b,  // 操作数 B 尾数
  output wire [LEN*2-1:0] result           // 乘积
);

  assign result = s_axis_tdata_a * s_axis_tdata_b;

endmodule

`default_nettype wire
