module alu (
  input [3:0]A, B,
  input [2:0]sel,
  output [3:0] result,
  output overflow,
  output carry,
  output zero
);

wire [3:0] result_temp;
wire overflow_temp;
wire carry_temp;
wire zero_temp;

add4 u_add4(
  .a(A),
  .b(B),
  .sub_add((sel == 3'b001) || (sel == 3'b110) || (sel == 3'b111)),
  .result(result_temp),
  .overflow(overflow_temp),
  .carry(carry_temp),
  .zero(zero_temp)
);

assign result= {4{sel == 3'b000}} & result_temp |
              //  {4{sel == 3'b001}} & result_temp |
               {4{sel == 3'b001}} & (A - B)|
               {4{sel == 3'b010}} & (~A)   |
               {4{sel == 3'b011}} & (A & B)|
               {4{sel == 3'b100}} & (A | B)|
               {4{sel == 3'b101}} & (A ^ B)|
              //  {4{sel == 3'b110}} & {3'b0,result_temp[3] ^ overflow_temp}|
               {4{sel == 3'b110}} & {3'b0,A<B}|
               {4{sel == 3'b111}} & {3'b0,zero_temp};

assign overflow = (sel == 3'b000) || (sel == 3'b001) ? overflow_temp : 1'b0;
assign carry = (sel == 3'b000) || (sel == 3'b001) ? carry_temp : 1'b0;
assign zero = (sel == 3'b000) || (sel == 3'b001) ? zero_temp : 1'b0;

endmodule






