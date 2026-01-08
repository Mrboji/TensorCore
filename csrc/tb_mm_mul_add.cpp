#include "verilated.h"
#include "verilated_fst_c.h"

#include "Vmm_mul_add.h"

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

// ======================================================
// 数据打包/解包函数
// ======================================================

#define SHAPE_M 8
#define SHAPE_N 8
#define SHAPE_K 8
#define ELEMENT_WIDTH 9
#define CTRL_C_WIDTH 16

// ======================================================
// 数据编码/解码辅助函数
// ======================================================

// 编码FP9格式 (E4M3)
uint16_t encode_fp9(bool sign, uint8_t exp, uint8_t frac) {
    // FP9: 1位符号 + 5位指数 + 3位尾数
    exp = exp & 0x1F;      // 4位指数
    frac = frac & 0x07;    // 3位尾数
    return ((sign ? 1 : 0) << 8) | ((exp & 0x1F) << 3) | (frac & 0x07);
}

// 编码FP22格式 (E8M13)
uint32_t encode_fp22(bool sign, uint8_t exp, uint16_t frac) {
    // FP22: 1位符号 + 8位指数 + 13位尾数
    exp = exp & 0xFF;      // 8位指数
    frac = frac & 0x1FFF;  // 13位尾数
    return ((sign ? 1 : 0) << 21) | ((exp & 0xFF) << 13) | (frac & 0x1FFF);
}

// 编码FP8格式 (E4M3)
uint8_t encode_fp8(bool sign, uint8_t exp, uint8_t frac) {
    // FP8: 1位符号 + 4位指数 + 3位尾数
    exp = exp & 0x0F;      // 4位指数
    frac = frac & 0x07;    // 3位尾数
    return ((sign ? 1 : 0) << 7) | ((exp & 0x0F) << 3) | (frac & 0x07);
}

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

// ======================================================
// 数据打包函数（针对模块的宽接口）
// ======================================================

// 设置FP9矩阵输入 (64个FP9元素，每个9位，共576位)
void set_matrix_a(uint16_t data[8][8]) {
    const int ELEMENT_WIDTH_MID = 9;
    const int TOTAL_BITS = SHAPE_M * SHAPE_N * ELEMENT_WIDTH_MID;  // 576位
    
    // 清空输入
    for (int i = 0; i < 18; i++) {  // 576/32 = 18个32位字
        top->a_i[i] = 0;
    }
    
    // 将8x8矩阵数据打包到576位中
    for (int m = 0; m < SHAPE_M; m++) {
        for (int n = 0; n < SHAPE_N; n++) {
            uint16_t value = data[m][n] & 0x1FF;  // 确保9位
            int bit_pos = (m * SHAPE_N + n) * ELEMENT_WIDTH_MID;
            
            int word_idx = bit_pos / 32;
            int bit_offset = bit_pos % 32;
            
            // 设置对应的位
            top->a_i[word_idx] |= ((uint32_t)value << bit_offset);
            
            // 处理跨32位边界的情况
            if (bit_offset + ELEMENT_WIDTH_MID > 32) {
                int remaining_bits = 32 - bit_offset;
                int overflow_bits = ELEMENT_WIDTH_MID - remaining_bits;
                top->a_i[word_idx + 1] |= (value >> remaining_bits);
            }
        }
    }
}

// 设置FP9矩阵输入 (64个FP9元素，每个9位，共576位)
void set_matrix_b(uint16_t data[8][8]) {
    const int ELEMENT_WIDTH_MID = 9;
    const int TOTAL_BITS = SHAPE_M * SHAPE_N * ELEMENT_WIDTH_MID;  // 576位
    
    // 清空输入
    for (int i = 0; i < 18; i++) {  // 576/32 = 18个32位字
        top->b_i[i] = 0;
    }
    
    // 将8x8矩阵数据打包到576位中
    for (int m = 0; m < SHAPE_M; m++) {
        for (int n = 0; n < SHAPE_N; n++) {
            uint16_t value = data[m][n] & 0x1FF;  // 确保9位
            int bit_pos = (m * SHAPE_N + n) * ELEMENT_WIDTH_MID;
            
            int word_idx = bit_pos / 32;
            int bit_offset = bit_pos % 32;
            
            // 设置对应的位
            top->b_i[word_idx] |= ((uint32_t)value << bit_offset);
            
            // 处理跨32位边界的情况
            if (bit_offset + ELEMENT_WIDTH_MID > 32) {
                int remaining_bits = 32 - bit_offset;
                int overflow_bits = ELEMENT_WIDTH_MID - remaining_bits;
                top->b_i[word_idx + 1] |= (value >> remaining_bits);
            }
        }
    }
}

// 设置FP22矩阵输入 (64个FP22元素，每个22位，共1408位)
void set_matrix_c(uint32_t data[8][8]) {
    const int ELEMENT_WIDTH_C = 22;
    const int TOTAL_BITS = SHAPE_M * SHAPE_N * ELEMENT_WIDTH_C;  // 1408位
    
    // 清空输入
    for (int i = 0; i < 44; i++) {  // 1408/32 = 44个32位字
        top->c_i[i] = 0;
    }
    
    // 将8x8矩阵数据打包到1408位中
    for (int m = 0; m < SHAPE_M; m++) {
        for (int n = 0; n < SHAPE_N; n++) {
            uint32_t value = data[m][n] & 0x3FFFFF;  // 确保22位
            int bit_pos = (m * SHAPE_N + n) * ELEMENT_WIDTH_C;
            
            int word_idx = bit_pos / 32;
            int bit_offset = bit_pos % 32;
            
            // 设置对应的位
            top->c_i[word_idx] |= ((uint32_t)value << bit_offset);
            
            // 处理跨32位边界的情况
            if (bit_offset + ELEMENT_WIDTH_C > 32) {
                int remaining_bits = 32 - bit_offset;
                int overflow_bits = ELEMENT_WIDTH_C - remaining_bits;
                top->c_i[word_idx + 1] |= (value >> remaining_bits);
            }
        }
    }
}

// 从结果中提取FP8矩阵 (64个FP8元素，每个8位，共512位)
void extract_fp8_results(uint32_t* result_wide, uint16_t results[8][8]) {
    const int ELEMENT_WIDTH_OUT = 8;
    
    for (int m = 0; m < SHAPE_M; m++) {
        for (int n = 0; n < SHAPE_N; n++) {
            int bit_pos = (m * SHAPE_N + n) * ELEMENT_WIDTH_OUT;
            int word_idx = bit_pos / 32;
            int bit_offset = bit_pos % 32;
            
            uint32_t value = result_wide[word_idx] >> bit_offset;
            
            // 检查是否需要从下一个字中获取位
            if (bit_offset + ELEMENT_WIDTH_OUT > 32) {
                int remaining_bits = 32 - bit_offset;
                uint32_t next_word = result_wide[word_idx + 1];
                value |= (next_word << remaining_bits);
            }
            
            results[m][n] = value & 0xFF;  // 8位结果
        }
    }
}


// ======================================================
// 运行测试（修正版）
// ======================================================
void run_tc_mm_add_test() {
    printf("\n=========================================\n");
    printf("  Testing mm_mul_add Module\n");
    printf("=========================================\n");
    
    // 创建测试数据
    uint16_t matrix_a [SHAPE_M][SHAPE_N];
    uint16_t matrix_b [SHAPE_N][SHAPE_K];
    uint32_t matrix_c [SHAPE_M][SHAPE_K];
    
    // 测试用例：每行的8个元素都是1.0
    for (int n = 0; n < SHAPE_M; n++) {
        for (int k = 0; k < SHAPE_N; k=k+4) {
            // 1.0 = 符号0，指数15，尾数0
            matrix_a[n][k]   = encode_fp9(0, 15, 0b000);//1.0
            matrix_a[n][k+1] = encode_fp9(0, 15, 0b100);//1.5
            matrix_a[n][k+2] = encode_fp9(1, 15, 0b000);//-1.0
            matrix_a[n][k+3] = encode_fp9(0, 15, 0b100);//1.5

            matrix_b[n][k]   = encode_fp9(0, 15, 0b100);//1.5
            matrix_b[n][k+1] = encode_fp9(1, 15, 0b100);//-1.5
            matrix_b[n][k+2] = encode_fp9(1, 14, 0b000);//-0.5
            matrix_b[n][k+3] = encode_fp9(0, 15, 0b100);//1.5

            matrix_c[n][k]   = encode_fp22(0, 128, 0b0100000000000);//2.5
            matrix_c[n][k+1] = encode_fp22(0, 128, 0b0000000000000);//2.0
            matrix_c[n][k+2] = encode_fp22(1, 127, 0b0000000000000);//-1.0
            matrix_c[n][k+3] = encode_fp22(0, 128, 0b0000000000000);//2.0
        }
    }
    
    // 设置输入数据
    printf("Setting input data...\n");
    set_matrix_a(matrix_a);
    set_matrix_b(matrix_b);
    set_matrix_c(matrix_c);
    
    // 设置控制信号
    top->rm_i = 0;
    top->ctrl_reg_idxw_i = 1;
    top->ctrl_warpid_i = 0;
    top->out_ready_i = 1;
    
    // 启动测试
    printf("\nStarting test...\n");
    top->in_valid_i = 1;
    
    // 等待输入就绪
    int cycle = 0;
    while (!top->in_ready_o && cycle < 10) {
        printf("Cycle %d: in_ready_o = %d\n", cycle, top->in_ready_o);
        single_cycle();
        cycle++;
    }
    
    if (cycle >= 10) {
        printf("ERROR: Timeout waiting for in_ready_o\n");
        return;
    }
    
    printf("Input accepted at cycle %d\n", cycle);
    
    // 输入完成
    single_cycle();
    top->in_valid_i = 0;
    
    // 等待输出
    printf("\nWaiting for output...\n");
    bool got_output = false;
    
    for (int t = 0; t < 100; t++) {
        single_cycle();
        
        if (top->out_valid_o) {
            got_output = true;
            printf("Output received at cycle %d\n", t);
            
            // 打印FFLAGS
            printf("FFLAGS: 0x%02x\n", top->fflags_o);
            
            // 提取结果
            uint16_t results[8][8];
            double   results_dou[8][8];
            uint64_t sign_out, exp_out, frac_out;


            extract_fp8_results(top->result_o, results);
            
            // 解码浮点数
            for (int i = 0; i < 8; i++) {
                for(int j = 0; j < 8; j++){
                    results_dou[i][j] = encoded_to_double(results[i][j], 4, 3);
                }
            }
            // 打印结果
            printf("\nResults (64 FP9 values):\n");
            for (int i = 0; i < 8; i++) {
                for(int j = 0; j<8; j++){
                    uint16_t val = results[i][j];
                    double   val_dou = results_dou[i][j];
                    printf("  Result[%d][%d]: 0x%03x %f (s=%d, e=%d, f=%d)\n",
                        i, j, val, val_dou,
                        (val >> 7) & 1,
                        (val >> 3) & 0xF,
                        val & 0x07);
                    
                    // uint16_t expected = encode_fp9(0, 19, 0b010);
                    // if (val == expected) {
                    //     printf("    ✓ Correct\n");
                    // } else {
                    //     printf("    ✗ Expected: 0x%03x\n", expected);
                    // }
                }
            }
            
            break;
        }
    }
    
    if (!got_output) {
        printf("ERROR: Timeout waiting for output\n");
    }
}

int main() {

    // 初始化仿真
    sim_init();
    
    printf("Matrix-Vector Multiplication Testbench\n");
    printf("=====================================\n");
    
    // 复位
    printf("\nResetting module...\n");
    reset(10);
    

    run_tc_mm_add_test();
    
    // 结束仿真
    printf("\nSimulation completed.\n");
    sim_exit();
    
    return 0;
}

