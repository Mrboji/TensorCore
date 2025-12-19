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
    while (n-- > 0) single_cycle();
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

int main() {
    sim_init();
    reset(5);

    top->en_i = 1;

    // 清空输入
    top->rm_i = 0;
    top->a_i  = 0;
    top->b_i  = 0;
    single_cycle();

    // ========================================================
    // Testcase 1: 正常加法（far path）
    // a = +1.5 , b = +0.5
    // ========================================================
    top->rm_i = 0; // RNE

    top->a_i = pack_fp(0, 15, 0x80); // 1.5
    top->b_i = pack_fp(0, 14, 0x00); // 0.5

    single_cycle();
    // 期望：out_result_o ≈ +2.0
    // 无异常标志

    // ========================================================
    // Testcase 2: 符号相反（near path）
    // a = +1.0 , b = -1.0 → 0
    // ========================================================
    top->rm_i = 0;

    top->a_i = pack_fp(0, 15, 0x00); // +1.0
    top->b_i = pack_fp(1, 15, 0x00); // -1.0

    single_cycle();
    // 期望：+0
    // NX=0, UF=0

    // ========================================================
    // Testcase 3: 舍入测试（RNE）
    // ========================================================
    top->rm_i = 0;

    top->a_i = pack_fp(0, 15, 0xFF);
    top->b_i = pack_fp(0, 10, 0x01);

    single_cycle();
    // 期望：发生 NX

    // ========================================================
    // Testcase 4: far path 下溢
    // ========================================================
    top->rm_i = 0;

    top->a_i = pack_fp(0, 0, 0x01);  // 极小数
    top->b_i = pack_fp(0, 0, 0x01);

    single_cycle();
    // 期望：
    // out_result_o = 0
    // out_fflags_o[UF]=1
    // out_far_uf_o = 1

    // ========================================================
    // Testcase 5: near path 溢出
    // ========================================================
    top->rm_i = 0;

    top->a_i = pack_fp(0, 30, 0xFF);
    top->b_i = pack_fp(0, 30, 0xFF);

    single_cycle();
    // 期望：
    // +Inf
    // out_fflags_o[OF]=1
    // out_near_of_o = 1

    // ========================================================
    // Testcase 6: NaN + normal
    // ========================================================
    top->rm_i = 0;

    top->a_i = pack_fp(0, 31, 0x80); // NaN
    top->b_i = pack_fp(0, 15, 0x00);

    single_cycle();
    // 期望：NaN，NV=0

    // ========================================================
    // Testcase 7: Inf - Inf → Invalid
    // ========================================================
    top->rm_i = 0;

    top->a_i = pack_fp(0, 31, 0x00); // +Inf
    top->b_i = pack_fp(1, 31, 0x00); // -Inf

    single_cycle();
    // 期望：
    // NaN
    // out_fflags_o[NV]=1

    single_cycle();
    single_cycle();

    sim_exit();
    return 0;
}
