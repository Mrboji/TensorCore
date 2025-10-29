module shift_reg (
  input clk,
  input rst,
  input val,
  input [2:0] sel,
  output [7:0] reg_out
);

reg [7:0] out;

always @(posedge clk ,negedge rst) begin
  if(!rst)
    out <= 8'b0;
  else begin
    case(sel)
      3'b000: out <= 8'b0;
      3'b001: out <= 8'hff;
      3'b010: out <= {1'b0,out[7:1]};
      3'b011: out <= {out[6:0],1'b0};

      3'b100: out <= {out[7],out[7:1]};
      3'b101: out <= {val,out[7:1]};
      3'b110: out <= {out[0],out[7:1]};
      3'b111: out <= {out[6:0],out[7]};
      default: out <= 8'b0;
    endcase
  end
  
end

assign reg_out = out;


  
endmodule


