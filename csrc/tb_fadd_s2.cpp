#include "verilated.h"
#include "verilated_fst_c.h"
#include "Vfadd_s2.h"

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
    top      = new TOP_MODULE;

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

int main() {
    sim_init();
    reset(5);

    // 复位后：一直允许输出更新
    top->en_i = 1;

    // 清一次输入
    top->in_far_sign_i = 0;
    top->in_far_exp_i  = 0;
    top->in_far_sig_i  = 0;

    top->in_near_sign_i = 0;
    top->in_near_exp_i  = 0;
    top->in_near_sig_i  = 0;

    top->in_sel_far_path_i = 0;
    top->rm_i = 0;

    top->in_far_mul_of_i       = 0;
    top->in_near_sig_is_zero_i = 0;

    top->in_special_case_valid_i = 0;
    top->in_special_case_iv_i   = 0;
    top->in_special_case_nan_i   = 0;

    single_cycle();

    // ========================================================
    // Testcase 1: FAR + RN-even
    // pre_sig_far = 45 = 7'b0101101
    // mant_trunc=0101, guard=1, sticky=1 → 舍入，无溢出
    // ========================================================
    top->in_sel_far_path_i       = 1; // far
    top->rm_i                    = 0; // round-to-nearest-even

    top->in_far_sign_i           = 0;
    top->in_far_exp_i            = 10;
    top->in_far_sig_i            = 45;

    top->in_near_sign_i          = 0;
    top->in_near_exp_i           = 8;
    top->in_near_sig_i           = 24;

    top->in_far_mul_of_i         = 0;
    top->in_near_sig_is_zero_i   = 0;

    top->in_special_case_valid_i = 0;
    top->in_special_case_iv_i   = 0;
    top->in_special_case_nan_i   = 0;

    single_cycle();  // 期望：out_result_o = 0x0A6, fflags = 0x01


    // ========================================================
    // Testcase 2: NEAR + toward +infinity
    // pre_sig_near = 28 = 7'b0011100
    // mant_trunc=0011, guard=1, sticky=0 → 向上舍入
    // ========================================================
    top->in_sel_far_path_i       = 0; // near
    top->rm_i                    = 2; // toward +inf

    top->in_near_sign_i          = 0;
    top->in_near_exp_i           = 12;
    top->in_near_sig_i           = 28;

    top->in_far_sign_i           = 0;
    top->in_far_exp_i            = 9;
    top->in_far_sig_i            = 32;

    top->in_far_mul_of_i         = 0;
    top->in_near_sig_is_zero_i   = 0;

    top->in_special_case_valid_i = 0;
    top->in_special_case_iv_i   = 0;
    top->in_special_case_nan_i   = 0;

    single_cycle();  // 期望：out_result_o = 0x0C4, fflags = 0x01


    // ========================================================
    // Testcase 3: FAR mantissa overflow → +Inf
    // pre_sig_far = 127 = 7'b1111111
    // mant_trunc=1111, guard=1, sticky=1 → mant_ext=1_0000 → 尾数进位溢出
    // pre_exp=30=EXP_MAX-1 → exponent+1 打到 EXP_MAX → Inf
    // ========================================================
    top->in_sel_far_path_i       = 1;
    top->rm_i                    = 0;

    top->in_far_sign_i           = 0;
    top->in_far_exp_i            = 30;
    top->in_far_sig_i            = 127;

    top->in_far_mul_of_i         = 0;  // 这里专门只测试“尾数进位”导致的 OF
    top->in_near_sig_is_zero_i   = 0;

    top->in_special_case_valid_i = 0;
    top->in_special_case_iv_i   = 0;
    top->in_special_case_nan_i   = 0;

    single_cycle();  // 期望：out_result_o = 0x1F0, fflags = 0x09

    // =============================================
    // Testcase 4: far path underflow → out_far_uf_o = 1
    // =============================================
    top->in_sel_far_path_i = 1;        // far path
    top->rm_i = 0;

    top->in_far_sign_i = 0;
    top->in_far_exp_i  = 0;
    top->in_far_sig_i  = 3;    // mant_trunc=0, sticky=1 → underflow

    top->in_special_case_valid_i = 0;
    top->in_special_case_iv_i   = 0;
    top->in_special_case_nan_i   = 0;

    top->in_far_mul_of_i = 0;
    top->in_near_sig_is_zero_i = 0;

    single_cycle();  //期望：out_result_o	= 0x000, out_fflags_o = 0x05, out_far_uf_o = 1


    // ========================================================
    // Testcase 5: NEAR underflow
    // pre_sig_near = 3 = 7'b0000011
    // mant_trunc=0000, guard=0, sticky=1; exp=0 → UF+NX
    // ========================================================
    top->in_sel_far_path_i       = 0;
    top->rm_i                    = 0;

    top->in_near_sign_i          = 1;
    top->in_near_exp_i           = 0;
    top->in_near_sig_i           = 3;

    top->in_far_sign_i           = 0;
    top->in_far_exp_i            = 0;
    top->in_far_sig_i            = 0;

    top->in_far_mul_of_i         = 0;
    top->in_near_sig_is_zero_i   = 0;

    top->in_special_case_valid_i = 0;
    top->in_special_case_iv_i   = 0;
    top->in_special_case_nan_i   = 0;

    single_cycle();  // 期望：out_result_o = 0x200, fflags = 0x05

    // =============================================
    // Testcase 6: near path overflow → out_near_of_o = 1
    // =============================================
    top->in_sel_far_path_i = 0;    // near path
    top->rm_i = 0;

    top->in_near_sign_i = 0;
    top->in_near_exp_i  = 30;      // EXP_MAX - 1
    top->in_near_sig_i  = 127;     // 7'b1111111 → mantissa overflow

    top->in_special_case_valid_i = 0;
    top->in_special_case_iv_i   = 0;
    top->in_special_case_nan_i   = 0;

    top->in_far_mul_of_i = 0;
    top->in_near_sig_is_zero_i = 0;

    single_cycle();  //期望：out_result_o = 0x1F0, out_fflags_o	= 0x09, out_near_of_o = 1


    // ========================================================
    // Testcase 7: Special NaN
    // valid=1, nan=1 → 输出 NaN 模板 {0, EXP_MAX, 1<<3}
    // ========================================================
    top->in_sel_far_path_i       = 1;
    top->rm_i                    = 0;

    top->in_far_sign_i           = 0;
    top->in_far_exp_i            = 15;
    top->in_far_sig_i            = 16;

    top->in_far_mul_of_i         = 0;
    top->in_near_sig_is_zero_i   = 0;

    top->in_special_case_valid_i = 1;
    top->in_special_case_iv_i   = 0;
    top->in_special_case_nan_i   = 1;

    single_cycle();  // 期望：out_result_o = 0x1F8, fflags = 0x00


    // ========================================================
    // Testcase 8: Special Invalid
    // valid=1, invalid=1 → 同 NaN 模板，但 NV=1
    // ========================================================
    top->in_special_case_valid_i = 1;
    top->in_special_case_iv_i   = 1;
    top->in_special_case_nan_i   = 0;

    single_cycle();  // 期望：out_result_o = 0x1F8, fflags = 0x10
    single_cycle();
    single_cycle();
    sim_exit();
    return 0;
}
