module naivemultiplier#(
parameter integer LEN = 4, 

)(
// ===== input =====
input wire              regenable,     //reg write en
input wire [LEN-1:0]    s_axis_tdata_a,//a_aive_input
input wire [LEN-1:0]    s_axis_tdata_b,//b_aive_input
output wire [LEN+LEN-1:0]    result   
)





endmodule