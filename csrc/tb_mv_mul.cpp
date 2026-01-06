#include "verilated.h"
#include "verilated_fst_c.h"

#include "Vmv_mul.h"

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
#define ELEMENT_WIDTH 9
#define CTRL_C_WIDTH 16

// A矩阵：8x8 FP9 (576 bits)
// B向量：8x1 FP9 (72 bits)
// 结果：8x1 FP9 (72 bits)

// FP9编码函数
uint16_t encode_fp9(uint8_t s, uint8_t e, uint8_t f) {
    return (s << 8) | ((e & 0x1F) << 3) | (f & 0x07);
}

// 打印FP9值
void print_fp9(uint16_t val, const char* name = "") {
    printf("%s0x%03x (s=%d, e=%d, f=%d)", name, val,
           (val >> 8) & 1,
           (val >> 3) & 0x1F,
           val & 0x07);
}

// 设置A矩阵输入（8x8矩阵，576位）
void set_matrix_a(uint16_t data[SHAPE_M][SHAPE_N]) {
    // A矩阵需要18个32位字（576位）
    // 首先清空所有字
    for (int i = 0; i < 18; i++) {
        top->a_i[i] = 0;
    }
    
    // 将数据打包到576位中
    for (int m = 0; m < SHAPE_M; m++) {
        for (int n = 0; n < SHAPE_N; n++) {
            uint16_t value = data[m][n] & 0x1FF;
            int bit_pos = (m * SHAPE_N + n) * ELEMENT_WIDTH;
            
            int word_idx = bit_pos / 32;
            int bit_offset = bit_pos % 32;
            
            // 设置对应的位
            top->a_i[word_idx] |= ((uint32_t)value << bit_offset);
            
            // 处理跨32位边界的情况
            if (bit_offset + ELEMENT_WIDTH > 32) {
                int remaining_bits = 32 - bit_offset;
                int overflow_bits = ELEMENT_WIDTH - remaining_bits;
                top->a_i[word_idx + 1] |= (value >> remaining_bits);
            }
        }
    }
}

// 设置B向量输入（8元素向量，72位）
void set_vector_b(uint16_t data[SHAPE_N]) {
    // B向量需要3个32位字（72位）
    // 首先清空所有字
    for (int i = 0; i < 3; i++) {
        top->b_i[i] = 0;
    }
    
    // 将数据打包到72位中
    for (int n = 0; n < SHAPE_N; n++) {
        uint16_t value = data[n] & 0x1FF;
        int bit_pos = n * ELEMENT_WIDTH;
        
        int word_idx = bit_pos / 32;
        int bit_offset = bit_pos % 32;
        
        // 设置对应的位
        top->b_i[word_idx] |= ((uint32_t)value << bit_offset);
        
        // 处理跨32位边界的情况
        if (bit_offset + ELEMENT_WIDTH > 32) {
            int remaining_bits = 32 - bit_offset;
            int overflow_bits = ELEMENT_WIDTH - remaining_bits;
            top->b_i[word_idx + 1] |= (value >> remaining_bits);
        }
    }
}


// 从结果中提取8个FP9值
void extract_fp9_results(uint32_t* result_wide, uint16_t results[8]) {
    // result_o 是72位，对应 VlWide<3> (3个uint32_t = 96位，只用前72位)
    
    for (int i = 0; i < 8; i++) {
        int bit_pos = i * ELEMENT_WIDTH;
        int word_idx = bit_pos / 32;
        int bit_offset = bit_pos % 32;
        
        uint32_t value = result_wide[word_idx] >> bit_offset;
        
        // 检查是否需要从下一个字中获取位
        if (bit_offset + ELEMENT_WIDTH > 32) {
            int remaining_bits = 32 - bit_offset;
            uint32_t next_word = result_wide[word_idx + 1];
            value |= (next_word << remaining_bits);
        }
        
        results[i] = value & 0x1FF;
    }
}

// ======================================================
// 运行测试（修正版）
// ======================================================
void run_mv_mul_test() {
    printf("\n=========================================\n");
    printf("  Testing mv_mul Module\n");
    printf("=========================================\n");
    
    // 创建测试数据
    uint16_t input_data[SHAPE_M][SHAPE_N];
    uint16_t vector_b  [SHAPE_N];
    
    // 测试用例：每行的8个元素都是1.0
    for (int n = 0; n < SHAPE_M; n++) {
        for (int k = 0; k < SHAPE_N; k=k+4) {
            // 1.0 = 符号0，指数15，尾数0
            input_data[n][k]   = encode_fp9(0, 16, 0b000);//2.0
            input_data[n][k+1] = encode_fp9(0, 15, 0b100);//1.5
            input_data[n][k+2] = encode_fp9(1, 15, 0b000);//-1.0
            input_data[n][k+3] = encode_fp9(0, 15, 0b100);//1.5

            vector_b[k]   = encode_fp9(0, 15, 0b100);//1.5
            vector_b[k+1] = encode_fp9(0, 16, 0b000);//2.0
            vector_b[k+2] = encode_fp9(1, 15, 0b000);//-1.0
            vector_b[k+3] = encode_fp9(0, 16, 0b000);//2.0
        }
    }
    
    // 设置输入数据
    printf("Setting input data...\n");
    set_matrix_a(input_data);
    set_vector_b(vector_b);
    
    // 打印输入数据（前几个字）
    printf("Input data (first few words):\n");
    for (int i = 0; i < 4; i++) {
        printf("  r_v_i[%d] = 0x%08x\n", i, top->a_i[i]);
    }
    
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
            uint16_t results[8];
            extract_fp9_results(top->result_o, results);
            
            // 打印结果
            printf("\nResults (8 FP9 values):\n");
            for (int i = 0; i < 8; i++) {
                uint16_t val = results[i];
                printf("  Result[%d]: 0x%03x (s=%d, e=%d, f=%d)\n",
                       i, val,
                       (val >> 8) & 1,
                       (val >> 3) & 0x1F,
                       val & 0x07);
                
                uint16_t expected = encode_fp9(0, 19, 0b010);
                if (val == expected) {
                    printf("    ✓ Correct\n");
                } else {
                    printf("    ✗ Expected: 0x%03x\n", expected);
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
    

    run_mv_mul_test();
    
    // 结束仿真
    printf("\nSimulation completed.\n");
    sim_exit();
    
    return 0;
}

