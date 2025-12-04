#include "verilated.h"
#include "verilated_fst_c.h"

#include "Vfadd_s1.h"  // Verilator生成的顶层模块头文件

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
  top->trace(tfp, 99);  // 深层trace，捕获内部信号
  tfp->open("./build/waveform.fst");
      
  // 初始化输入信号
  top->clk = 0;
  top->rst = 0;
  top->en_i = 0;
  top->a_i = 0;
  top->b_i = 0;
  top->b_inter_valid_i = 0;
  top->b_inter_flags_is_nan_i = 0;
  top->b_inter_flags_is_inf_i = 0;
  top->b_inter_flags_is_inv_i = 0;
  top->b_inter_flags_overflow_i = 0;
  top->rm_i = 0;
}

void sim_exit(){
  top->final();
  delete top;
  delete contextp;
  tfp->close();
  delete tfp;
}

// 单个时钟周期（包含高低电平）
void single_cycle() {
    top->clk = 0; step_and_dump_wave();
    top->clk = 1; step_and_dump_wave();
}

// 复位操作（低有效）
void reset(int n) {
    top->rst = 0;
    while (n-- > 0) single_cycle();
    top->rst = 1;
    single_cycle();  // 复位释放后再走一个周期
}
uint64_t float_encode(int sign, int exp, uint64_t frac, int exp_width, int prec) {
    return ((uint64_t)sign << (exp_width + prec)) | 
           ((uint64_t)exp << prec) | 
           (frac & ((1ULL << prec) - 1));
}


int main() {
    sim_init();

    // 复位阶段
    reset(5);
    top->en_i = 1;  // 使能模块

    // 测试用例1：正常加法（a=1.0, b=2.0，EXPWIDTH=5, PRECISION=8配置）
    top->a_i = float_encode(0, 16, 0x00, 5, 8);  // 1.0 = 0 10000 00000000
    top->b_i = float_encode(0, 17, 0x00, 5, 8);  // 2.0 = 0 10001 00000000
    top->rm_i = 0;  // 就近舍入
    top->b_inter_valid_i = 1;  // 中间结果有效
    single_cycle();

    // 测试用例2：NaN输入测试
    top->a_i = float_encode(1, 31, 0xFF, 5, 8);  // NaN格式
    top->b_inter_flags_is_nan_i = 1;
    single_cycle();

    // 测试用例3：无穷大输入
    top->a_i = float_encode(0, 31, 0x00, 5, 8);  // 正无穷
    top->b_inter_flags_is_inf_i = 1;
    single_cycle();

    // 测试用例4：小加法（非规格数）
    top->a_i = float_encode(0, 0, 0x10, 5, 8);   // 非规格数
    top->b_i = float_encode(0, 0, 0x08, 5, 8);
    single_cycle();

    // 测试用例5：不同舍入模式
    top->rm_i = 3;  // 朝正无穷舍入
    single_cycle();
    top->rm_i = 4;  // 朝负无穷舍入
    single_cycle();

    // 关闭使能
    top->en_i = 0;
    single_cycle();

    sim_exit();
    return 0;
}

