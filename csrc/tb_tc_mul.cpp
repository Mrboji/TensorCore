#include "verilated.h"
#include "verilated_fst_c.h"

#include "Vtc_mul.h"

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
  top->rst_n = 0;
  while (n -- > 0) single_cycle();
  top->rst_n = 1;
}

// 浮点数编码函数（5位指数，3位尾数）
uint16_t encode_float(uint8_t sign, uint8_t exponent, uint8_t fraction) {
    return (sign << 8) | (exponent << 3) | (fraction & 0x7);
  }
  
// 在测试函数中添加结果验证
void check_result(const char* test_name, uint16_t expected, uint16_t actual, uint8_t expected_fflags) {
  if (actual == expected && top->fflags_o == expected_fflags) {
      printf("%s: PASS (result=0x%03x, fflags=0x%02x)\n", test_name, actual, expected_fflags);
  } else {
      printf("%s: FAIL\n", test_name);
      printf("  Expected: result=0x%03x, fflags=0x%02x\n", expected, expected_fflags);
      printf("  Actual:   result=0x%03x, fflags=0x%02x\n", actual, top->fflags_o);
  }
}

// 修改测试用例，添加验证逻辑
void test_normal_multiplication() {
  printf("=== Test Normal Multiplication ===\n");
  
  // 测试 1.5 × 2.0 = 3.0
  // 1.5: sign=0, exp=15+1=16(10000), frac=100
  // 2.0: sign=0, exp=15+1=16(10000), frac=000  
  // 3.0: sign=0, exp=15+2=17(10001), frac=100
  top->a_i = encode_float(0, 16, 0b100);  // 1.5
  top->b_i = encode_float(0, 16, 0b000);  // 2.0
  uint16_t expected_result = encode_float(0, 17, 0b100); // 3.0
  
  top->in_valid_i = 1;
  top->out_ready_i = 1;
  top->rm_i = 0;
  
  // 等待ready信号拉高
  while (!top->in_ready_o) {
    single_cycle();
  }

  // ready拉高后，再过一个周期拉低valid
  single_cycle();
  top->in_valid_i = 0;
  
  // 等待流水线完成（3个周期）
  for (int i = 0; i < 5; i++) {
      single_cycle();
      if (top->out_valid_o) {
          check_result("1.5 × 2.0 = 3.0", expected_result, top->result_o, 0);
          break;
      }
  }
}

void test_zero_multiplication() {
  printf("=== Test Zero Multiplication ===\n");
  
  // 测试 0.0 × 5.0 = 0.0
  top->a_i = encode_float(0, 0, 0);      // 0.0
  top->b_i = encode_float(0, 17, 0b010); // 5.0
  uint16_t expected_result = encode_float(0, 0, 0); // 0.0
  
  top->in_valid_i = 1;
  // 等待ready信号拉高
  while (!top->in_ready_o) {
    single_cycle();
}

// ready拉高后，再过一个周期拉低valid
single_cycle();
top->in_valid_i = 0;
  
  for (int i = 0; i < 5; i++) {
      single_cycle();
      if (top->out_valid_o) {
          check_result("0.0 × 5.0 = 0.0", expected_result, top->result_o, 0);
          break;
      }
  }
}

void test_signed_multiplication() {
  printf("=== Test Signed Multiplication ===\n");
  
  // 测试 -1.5 × 2.0 = -3.0
  top->a_i = encode_float(1, 16, 0b100); // -1.5
  top->b_i = encode_float(0, 16, 0b000); // 2.0
  uint16_t expected_result = encode_float(1, 17, 0b100); // -3.0
  
  top->in_valid_i = 1;
  // 等待ready信号拉高
  while (!top->in_ready_o) {
    single_cycle();
  }

  // ready拉高后，再过一个周期拉低valid
  single_cycle();
  top->in_valid_i = 0;
  
  for (int i = 0; i < 5; i++) {
      single_cycle();
      if (top->out_valid_o) {
          check_result("-1.5 × 2.0 = -3.0", expected_result, top->result_o, 0);
          break;
      }
  }
}

void test_nan_multiplication() {
  printf("=== Test NaN Multiplication ===\n");
  
  // 测试 NaN × 2.0 = NaN
  top->a_i = encode_float(0, 31, 0b001); // NaN
  top->b_i = encode_float(0, 16, 0b000); // 2.0
  
  top->in_valid_i = 1;
  // 等待ready信号拉高
  while (!top->in_ready_o) {
      single_cycle();
  }

  // ready拉高后，再过一个周期拉低valid
  single_cycle();
  top->in_valid_i = 0;
  
  for (int i = 0; i < 5; i++) {
      single_cycle();
      if (top->out_valid_o) {
          // NaN 检查：指数全1，尾数非0
          bool is_nan = ((top->result_o >> 3) == 0x1F) && ((top->result_o & 0x7) != 0);
          bool has_invalid_flag = (top->fflags_o & 0x4) != 0; // invalid flag at bit 2
          
          if (is_nan && has_invalid_flag) {
              printf("NaN × 2.0 = NaN: PASS\n");
          } else {
              printf("NaN × 2.0 = NaN: FAIL\n");
              printf("  Result: 0x%03x, FFLAGS: 0x%02x\n", top->result_o, top->fflags_o);
          }
          break;
      }
  }
}

void test_infinity_multiplication() {
  printf("=== Test Infinity Multiplication ===\n");
  
  // 测试 Inf × 2.0 = Inf
  top->a_i = encode_float(0, 31, 0);     // Inf
  top->b_i = encode_float(0, 16, 0b000); // 2.0
  uint16_t expected_result = encode_float(0, 31, 0); // Inf
  
  top->in_valid_i = 1;
  // 等待ready信号拉高
  while (!top->in_ready_o) {
    single_cycle();
  }

  // ready拉高后，再过一个周期拉低valid
  single_cycle();
  top->in_valid_i = 0;
  
  for (int i = 0; i < 5; i++) {
      single_cycle();
      if (top->out_valid_o) {
          check_result("Inf × 2.0 = Inf", expected_result, top->result_o, 0);
          break;
      }
  }
}

// 在main函数中运行测试
int main() {
  sim_init();
  
  printf("Initializing simulation...\n");
  reset(5);
  
  test_normal_multiplication();
  test_zero_multiplication();
  test_signed_multiplication();
  test_nan_multiplication(); 
  test_infinity_multiplication();
  
  printf("\n=== Simulation Summary ===\n");
  printf("All tests completed.\n");
  
  sim_exit();
  return 0;
}