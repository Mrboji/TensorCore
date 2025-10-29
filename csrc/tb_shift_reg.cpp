#include "verilated.h"
#include "verilated_fst_c.h"

#include "Vshift_reg.h"

VerilatedContext* contextp = NULL;
VerilatedFstC* tfp = NULL;

static TOP_MODULE* top;

void step_and_dump_wave(){
  top->eval();
  contextp->timeInc(1);
  tfp->dump(contextp->time());
}

void sim_init(){
  contextp = new VerilatedContext;
  tfp = new VerilatedFstC;
  top = new TOP_MODULE;
  contextp->traceEverOn(true);
  top->trace(tfp, 0);
  tfp->open("./build/waveform.fst");
}

void sim_exit(){
  top->final();
  delete top;
  delete contextp;
  tfp->close();
  delete tfp;
}

void single_cycle() {
  top->clk = 0; step_and_dump_wave();
  top->clk = 1; step_and_dump_wave();
}

void reset(int n) {
  top->rst = 0;
  while (n -- > 0) single_cycle();
  top->rst = 1;
}

int main() {
  sim_init();

  reset(5);

  top->sel = 0b001; single_cycle(); //set
  top->sel = 0b000; single_cycle(); //reset
  top->sel = 0b101; top->val = 0b1; single_cycle(); //serial to paralel 00111000
  single_cycle(); 
  single_cycle(); 
  top->val = 0b0; single_cycle(); 
  single_cycle(); 

  top->sel = 0b010; single_cycle(); //shift right logical
  top->sel = 0b011; single_cycle(); //shift left logical
  single_cycle(); 
  single_cycle(); 

  top->sel = 0b100; single_cycle(); //shift right alg
  single_cycle(); 

  top->sel = 0b110; single_cycle(); 
  top->sel = 0b111; single_cycle(); 
  single_cycle(); 


  sim_exit();
}

