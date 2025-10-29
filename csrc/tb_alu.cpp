#include "verilated.h"
#include "verilated_fst_c.h"

#include "Valu.h"// need modify

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

int main() {
  sim_init();

  top->sel=0b000;top->A = 0; top->B = 0;step_and_dump_wave();
  top->A = -1; top->B = -3;step_and_dump_wave();
  top->sel=0b001;top->A = 0; top->B = 0;step_and_dump_wave();
  top->A = 4; top->B = 0;step_and_dump_wave();
  top->A = -2; top->B = 1;step_and_dump_wave();
  top->sel=0b010;top->A = 4; top->B = 0;step_and_dump_wave();
  top->sel=0b011;top->A = 7; top->B = 0;step_and_dump_wave();
  top->sel=0b100;top->A = 7; top->B = 0;step_and_dump_wave();
  top->sel=0b101;top->A = 3; top->B = 1;step_and_dump_wave();
  top->sel=0b110;top->A = -1; top->B = 1;step_and_dump_wave();
  top->sel=0b111;top->A = 4; top->B = 4;step_and_dump_wave();

  sim_exit();
}

