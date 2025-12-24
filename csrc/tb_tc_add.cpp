#include "verilated.h"
#include "verilated_fst_c.h"

#include "Vtc_add.h"

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
// 576位数据处理工具函数（修正版）
// ======================================================
#define SHAPE_N 8
#define SHAPE_K 8
#define ELEMENT_WIDTH 9
#define TOTAL_BITS (SHAPE_N * SHAPE_K * ELEMENT_WIDTH)  // 576

// FP9编码函数
uint16_t encode_fp9(uint8_t s, uint8_t e, uint8_t f) {
    return (s << 8) | ((e & 0x1F) << 3) | (f & 0x07);
}

// 方法1：正确操作 VlWide 类型
void set_576bit_input(uint16_t data[SHAPE_N][SHAPE_K]) {
    // 首先将 r_v_i 清零
    for (int i = 0; i < 18; i++) {
        top->r_v_i[i] = 0;
    }
    
    // 将8x8 FP9数据打包到576位中
    for (int n = 0; n < SHAPE_N; n++) {
        for (int k = 0; k < SHAPE_K; k++) {
            uint16_t value = data[n][k] & 0x1FF;
            int bit_pos = (n * SHAPE_K + k) * ELEMENT_WIDTH;
            
            // 计算在 VlWide 数组中的位置
            int word_idx = bit_pos / 32;      // 32位字索引
            int bit_offset = bit_pos % 32;    // 在字中的位偏移
            
            // 设置对应的位
            top->r_v_i[word_idx] |= ((uint32_t)value << bit_offset);
            
            // 处理跨32位边界的情况
            if (bit_offset + ELEMENT_WIDTH > 32) {
                int remaining_bits = 32 - bit_offset;
                int overflow_bits = ELEMENT_WIDTH - remaining_bits;
                top->r_v_i[word_idx + 1] |= (value >> remaining_bits);
            }
        }
    }
}

// 方法2：使用内存拷贝（更简单）
void set_576bit_input_simple(uint16_t data[SHAPE_N][SHAPE_K]) {
    // 创建一个72字节的缓冲区（576位 = 72字节）
    uint8_t buffer[72] = {0};
    
    // 将数据打包到缓冲区
    for (int n = 0; n < SHAPE_N; n++) {
        for (int k = 0; k < SHAPE_K; k++) {
            uint16_t value = data[n][k] & 0x1FF;
            int bit_pos = (n * SHAPE_K + k) * ELEMENT_WIDTH;
            
            int byte_idx = bit_pos / 8;
            int bit_offset = bit_pos % 8;
            
            // 将9位值写入缓冲区
            uint32_t temp = ((uint32_t)value << bit_offset);
            buffer[byte_idx] |= (temp & 0xFF);
            buffer[byte_idx + 1] |= ((temp >> 8) & 0xFF);
            
            if (bit_offset + 9 > 16) {
                buffer[byte_idx + 2] |= ((temp >> 16) & 0xFF);
            }
        }
    }
    
    // 将缓冲区数据拷贝到 r_v_i
    // VlWide<18> 是 18个uint32_t，即72字节
    memcpy(&top->r_v_i, buffer, 72);
}

// 打印 VlWide 数组的内容（调试用）
void print_vlwide(const char* name, const uint32_t* wide, int size) {
    printf("%s: ", name);
    for (int i = size-1; i >= 0; i--) {
        printf("%08x ", wide[i]);
    }
    printf("\n");
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
void run_tc_add_test() {
    printf("\n=========================================\n");
    printf("  Testing tc_add Module\n");
    printf("=========================================\n");
    
    // 创建测试数据
    uint16_t input_data[SHAPE_N][SHAPE_K];
    
    // 测试用例：每行的8个元素都是1.0
    for (int n = 0; n < SHAPE_N; n++) {
        for (int k = 0; k < SHAPE_K; k=k+4) {
            // 1.0 = 符号0，指数15，尾数0
            input_data[n][k]   = encode_fp9(0, 15, 0b100);//1.5
            input_data[n][k+1] = encode_fp9(0, 16, 0b000);//2.0
            input_data[n][k+2] = encode_fp9(1, 15, 0b000);//-1.0
            input_data[n][k+3] = encode_fp9(0, 15, 0b010);//1.25
        }
    }
    
    // 设置输入数据
    printf("Setting input data...\n");
    set_576bit_input(input_data);
    
    // 打印输入数据（前几个字）
    printf("Input data (first few words):\n");
    for (int i = 0; i < 4; i++) {
        printf("  r_v_i[%d] = 0x%08x\n", i, top->r_v_i[i]);
    }
    
    // 设置控制信号
    top->rm_i = 0;
    top->ctrl_c_i = 0x1234;
    top->ctrl_rm_i = 0;
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
                
                // 期望结果：每行8个1.0相加 = 8.0
                // 8.0 = 符号0，指数18，尾数0 (0x240)
                uint16_t expected = encode_fp9(0, 17, 0b111);
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

// 查看信号结构的辅助函数
void inspect_signals() {
    printf("\nSignal inspection:\n");
    printf("Size of r_v_i: %lu bytes\n", sizeof(top->r_v_i));
    printf("Size of result_o: %lu bytes\n", sizeof(top->result_o));
    
    // 检查是否包含子信号
    printf("\nControl signals:\n");
    printf("ctrl_c_o: 0x%04x\n", top->ctrl_c_o);
    printf("ctrl_rm_o: %d\n", top->ctrl_rm_o);
    printf("ctrl_reg_idxw_o: %d\n", top->ctrl_reg_idxw_o);
    printf("ctrl_warpid_o: %d\n", top->ctrl_warpid_o);
}

// 主函数
int main() {
    sim_init();
    
    printf("Initializing simulation...\n");
    reset(10);
    
    // 检查信号
    inspect_signals();
    
    // 运行测试
    run_tc_add_test();
    
    // 添加空闲周期
    printf("\nAdding idle cycles...\n");
    for (int i = 0; i < 10; i++) {
        single_cycle();
    }
    
    sim_exit();
    printf("\nSimulation completed\n");
    return 0;
}

