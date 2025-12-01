module add4 (
  input [3:0] a,b,
  input sub_add,
  output [3:0] result,
  output overflow,
  output carry,
  output zero
);

wire [3:0] b_in = b ^ {4{sub_add}};
wire [3:0] g = a & b_in;
wire [3:0] p = a ^ b_in; 

wire [3:0] c;
assign c[0] = sub_add;

lca_4 u_lca(
	.g(g),
  .p(p),
  .ci(sub_add),
 	.G(),
  .P(),
	.co(c[3:1])
);

assign carry = g[3] | p[3] & c[3];
assign result = a ^ b_in ^ c;
assign zero = ~(| result);
assign overflow = (result[3] & ~a[3] & ~b_in[3]) | (~result[3] & a[3] & b_in[3]);
  
endmodule

module lca_4(
	input [3:0] g,p,
  input ci,
 	output G,P,
	output [2:0] co
);

assign co[0] = g[0] | (p[0] & ci);
assign co[1] = g[1] | p[1]&g[0] | (p[1]&p[0] & ci);
assign co[2] = g[2] | p[2]&g[1] | p[2]&p[1]&g[0] | (p[2]&p[1]&p[0] & ci);
assign G = g[3] | p[3]&g[2] | p[3]&p[2]&g[1] | p[3]&p[2]&p[1]&g[0];
assign P = p[3]&p[2]&p[1]&p[0];

endmodule



