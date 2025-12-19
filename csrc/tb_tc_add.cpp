#include <cstdint>
#include "verilated.h"
#include "verilated_fst_c.h"
#include "Vtc_add.h"

VerilatedContext* contextp = NULL;
VerilatedFstC* tfp = NULL;
static TOP_MODULE* top;

void step_and_dump_wave() {
    top->eval();
    contextp->timeInc(1);
    tfp->dump(contextp->time());
}

void single_cycle() {
    top->clk = 0; step_and_dump_wave();
    top->clk = 1; step_and_dump_wave();
}


void sim_init() {
    contextp = new VerilatedContext;
    tfp      = new VerilatedFstC;
    top      = new Vtc_add;

    contextp->traceEverOn(true);
    top->trace(tfp, 0);
    tfp->open("./build/waveform.fst");
}

void reset(int n) {
    top->rst_n = 0;
    top->en_i  = 0;
    top->rm_i  = 0;
    top->a_i   = 0;
    top->b_i   = 0;

    while (n-- > 0)
        single_cycle();

    top->rst_n = 1;
    single_cycle();
}


void sim_exit() {
    top->final();
    tfp->close();
    delete top;
    delete tfp;
    delete contextp;
}

// 打包 FP 数：{sign, exp, frac}
uint32_t pack_fp(
    uint32_t sign,
    uint32_t exp,
    uint32_t frac
) {
    // 对应 a_i / b_i : [EXPWIDTH+PRECISION:0]
    return (sign << (5 + 8)) | (exp << 8) | frac;
}

// ======================================================
// pipeline-aware stimulus
// tc_add = 2-stage pipeline → 等 3 cycle
// ======================================================
void apply_input(uint32_t a, uint32_t b, uint32_t rm) {
    // drive phase（clk=0）
    top->clk  = 0;
    top->en_i = 1;
    top->rm_i = rm;
    top->a_i  = a;
    top->b_i  = b;
    step_and_dump_wave();
    top->clk = 1;
    step_and_dump_wave();
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    sim_init();
    reset(5);

    // ==================================================
    // TC1: far path 正常加法 1.5 + 0.5
    // ==================================================
    apply_input(pack_fp(0,15,0x80), pack_fp(0,14,0x00), 0);
    single_cycle();        // 拍1：Stage1
    single_cycle();        // 拍2：Stage2（out_result_o 有效）
    top->en_i = 0;
    single_cycle();        // 拍3：平台

    // ==================================================
    // TC2: near path 完全抵消 +1.0 + (-1.0)
    // ==================================================
    apply_input(pack_fp(0,15,0x00), pack_fp(1,15,0x00), 0);
    single_cycle();
    single_cycle();
    top->en_i = 0;
    single_cycle();

    // ==================================================
    // TC3: 舍入模式覆盖
    // ==================================================
    uint32_t a = pack_fp(0,15,0x01);
    uint32_t b = pack_fp(0,10,0x01);

    // RNE
    apply_input(a, b, 0);
    single_cycle();
    single_cycle();
    top->en_i = 0;
    single_cycle();

    // RTZ
    //apply_input(a, b, 1);
    //single_cycle();
    //single_cycle();
    //top->en_i = 0;
    //single_cycle();

    // RUP
    //apply_input(a, b, 2);
    //single_cycle();
    //single_cycle();
    //top->en_i = 0;
    //single_cycle();

    // RDN
    //apply_input(a, b, 3);
    //single_cycle();
    //single_cycle();
    //top->en_i = 0;
    //single_cycle();

    // ==================================================
    // TC4: near path 溢出
    // ==================================================
    apply_input(pack_fp(0,30,0xFF), pack_fp(0,30,0xFF), 0);
    single_cycle();
    single_cycle();
    top->en_i = 0;
    single_cycle();

    // ==================================================
    // TC5: NaN + normal
    // ==================================================
    apply_input(pack_fp(0,31,0x80), pack_fp(0,15,0x00), 0);
    single_cycle();
    single_cycle();
    top->en_i = 0;
    single_cycle();

    // ==================================================
    // TC6: +Inf - Inf → Invalid
    // ==================================================
    apply_input(pack_fp(0,31,0x00), pack_fp(1,31,0x00), 0);
    single_cycle();
    single_cycle();
    top->en_i = 0;
    single_cycle();

    sim_exit();
    return 0;
}