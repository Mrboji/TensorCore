#include "verilated.h"
#include "verilated_fst_c.h"

#include "Vprecision_tran.h"

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

#define EXP_WIDTH_IN   4
#define FRAC_WIDTH_IN  3
#define EXP_WIDTH_OUT  5
#define FRAC_WIDTH_OUT 3

#define BIAS_IN   (1 << (EXP_WIDTH_IN  - 1)) - 1;
#define BIAS_OUT  (1 << (EXP_WIDTH_OUT - 1)) - 1;

double encoded_to_double(uint64_t encoded, int exp_width, int frac_width) {
    // 提取各个部分
    uint64_t sign = (encoded >> (exp_width + frac_width)) & 0x1;
    uint64_t exp = (encoded >> frac_width) & ((1 << exp_width) - 1);
    uint64_t frac = encoded & ((1 << frac_width) - 1);
    
    // 计算bias
    int bias = (1 << (exp_width - 1)) - 1;
    
    // 处理特殊值
    if (exp == 0) {
        // 零或次正规数
        if (frac == 0) {
            return (sign == 1) ? -0.0 : 0.0;
        } else {
            // 次正规数: (-1)^sign × 0.frac × 2^(1 - bias)
            double value = (double)frac / (1 << frac_width);  // 0.frac
            value *= pow(2.0, 1 - bias);                     // × 2^(1 - bias)
            return (sign == 1) ? -value : value;
        }
    } else if (exp == ((1 << exp_width) - 1)) {
        // 无穷大或NaN
        if (frac == 0) {
            // 无穷大
            return (sign == 1) ? -INFINITY : INFINITY;
        } else {
            // NaN
            return NAN;
        }
    }
    
    // 正规数: (-1)^sign × 1.frac × 2^(exp - bias)
    double mantissa = 1.0 + (double)frac / (1 << frac_width);  // 1.frac
    double exponent = (double)exp - bias;
    double value = mantissa * pow(2.0, exponent);
    
    return (sign == 1) ? -value : value;
}

// 编码浮点数（参数化版本）
uint64_t encode_float(uint64_t sign, uint64_t exponent, uint64_t fraction, 
                     int exp_width, int frac_width) {
    return (sign << (exp_width + frac_width)) | (exponent << frac_width) | (fraction & ((1 << frac_width) - 1));
}

// 解码浮点数
void decode_float(uint64_t encoded, uint64_t* sign, uint64_t* exponent, uint64_t* fraction,
                 int exp_width, int frac_width) {
    *sign = (encoded >> (exp_width + frac_width)) & 0x1;
    *exponent = (encoded >> frac_width) & ((1 << exp_width) - 1);
    *fraction = encoded & ((1 << frac_width) - 1);
}

// 检查测试结果
bool check_test(const char* test_name, uint64_t expected, uint64_t actual, 
                bool expected_invalid, bool expected_overflow, bool expected_underflow) {
    bool pass = (actual == expected) &&
                (top->invalid == expected_invalid) &&
                (top->overflow == expected_overflow) &&
                (top->underflow == expected_underflow);
    
    if (pass) {
        printf("%s: PASS\n", test_name);
    } else {
        printf("%s: FAIL\n", test_name);
    }
    return pass;
}

// 随机测试
void test_random_cases(int num_tests) {
    printf("\n=== Random Test Cases (%d tests) ===\n", num_tests);
    uint64_t sign_out, exp_out, frac_out;
    int passed = 0;
    double float_in, float_out;
    for (int i = 0; i < num_tests; i++) {
        // 生成随机输入
        uint64_t sign = rand() & 0x1;
        uint64_t exp = rand() & ((1 << EXP_WIDTH_IN) - 1);
        uint64_t frac = rand() & ((1 << FRAC_WIDTH_IN) - 1); 
        // if(exp ==  ((1 << EXP_WIDTH_IN) - 1) || exp == 0)
        //     continue;

        uint64_t input    = encode_float(sign, exp, frac, EXP_WIDTH_IN, FRAC_WIDTH_IN);
        float_in = encoded_to_double(input, EXP_WIDTH_IN, FRAC_WIDTH_IN);
        top->float_num_in = input;
        step_and_dump_wave();
        uint64_t output = top->float_num_out;
        float_out = encoded_to_double(output, EXP_WIDTH_OUT, FRAC_WIDTH_OUT);
        decode_float(output, &sign_out, &exp_out, &frac_out,EXP_WIDTH_OUT, FRAC_WIDTH_OUT);
        if(float_in != float_out){
            if(float_out == 0 || (exp_out == ((1 << EXP_WIDTH_OUT) - 1) && frac_out!=0)){
                ;
            }
            else{
               
                passed--;
            }
        }
        printf("Test %2d:", i);
        printf("Input:%10.6lf sign=%x,exp=%x,frac=%x", float_in, sign, exp, frac);
        printf("\tOutput:%10.6lf sign=%x,exp=%x,frac=%x\n",float_out, sign_out, exp_out, frac_out);
        passed++;
    }
    printf("Random tests passed: %d/%d\n", passed, num_tests);
}

int main() {
    sim_init();
    
    printf("========================================\n");
    printf("Precision Transformer Testbench\n");
    // printf("Config: EXP_IN=%d, FRAC_IN=%d -> EXP_OUT=%d, FRAC_OUT=%d\n", 
    //        top->EXP_WIDTH_IN, top->FRAC_WIDTH_IN, top->EXP_WIDTH_OUT, top->FRAC_WIDTH_OUT);
    printf("========================================\n");
    
    // 设置随机种子
    srand(123);
    
    test_random_cases(100);
    
    printf("\n========================================\n");
    printf("All tests completed\n");
    printf("Waveform saved to ./build/waveform.fst\n");
    printf("========================================\n");
    
    sim_exit();
    return 0;
}

