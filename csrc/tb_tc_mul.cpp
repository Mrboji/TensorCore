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

// ======================================================
// FP9 工具函数
// ======================================================
uint16_t encode_fp9(uint8_t s, uint8_t e, uint8_t f){
    return (s << 8) | ((e & 0x1F) << 3) | (f & 0x07);
}

// 拼装多个 lane
unsigned __int128 pack_lanes(uint16_t *arr, int k) {
    unsigned __int128 r = 0;
    for (int i = 0; i < k; i++) {
        r |= ( (unsigned __int128)(arr[i] & 0x1FF) ) << (i * 9);
    }
    return r;
}

void vlwide_set_u72(VlWide<3> &dest, unsigned __int128 value) {
    dest[0] = (uint32_t)(value & 0xFFFFFFFFu);        // 低 32bit
    dest[1] = (uint32_t)((value >> 32) & 0xFFFFFFFFu);// 高 32bit
    dest[2] = (uint32_t)((value >> 64) & 0xFFFFFFFFu);;
}

unsigned __int128 vlwide_get_u72(const VlWide<3> &src) {
    unsigned __int128 lo  = (unsigned __int128)src[0];
    unsigned __int128 me  = (unsigned __int128)src[1];
    unsigned __int128 hi  = (unsigned __int128)src[2];
    return lo | (me << 32) | (hi << 64);
}


// ======================================================
// 运行一次 8-lane 测试
// ======================================================
void run_tc_test(
    const char* name,
    uint16_t *A, uint16_t *B,
    uint16_t *E, uint8_t expected_fflags,
    int K
){
    printf("=== %s ===\n", name);

    unsigned __int128 a72 = pack_lanes(A, K);
    unsigned __int128 b72 = pack_lanes(B, K);

    vlwide_set_u72(top->a_i, a72);
    vlwide_set_u72(top->b_i, b72);

    top->rm_i = 0;
    top->out_ready_i = 1;

    top->in_valid_i = 1;

    while(!top->in_ready_o)
        single_cycle();

    single_cycle();
    top->in_valid_i = 0;

    bool got_output = false;

    for(int t=0;t<20;t++){
        single_cycle();
        if(top->out_valid_o){
            got_output = true;

            unsigned __int128 r = vlwide_get_u72(top->result_o);
            uint8_t f = top->fflags_o;

            bool pass = (f == expected_fflags);

            for(int i=0;i<K;i++){
                uint16_t res = (r >> (i*9)) & 0x1FF;
                if(res != E[i]) {
                    pass = false;
                }
            }

            if(pass){
                printf("PASS\n");
                printf("  fflags  got=%02x  exp=%02x\n", f, expected_fflags);
                for(int i=0;i<K;i++){
                    uint16_t res = (r >> (i*9)) & 0x1FF;
                    printf("  lane %d: got=0x%03x exp=0x%03x\n",
                           i, res, E[i]);
                }
            } else {
                printf("FAIL\n");
                printf("  fflags  got=%02x  exp=%02x\n", f, expected_fflags);
                for(int i=0;i<K;i++){
                    uint16_t res = (r >> (i*9)) & 0x1FF;
                    printf("  lane %d: got=0x%03x exp=0x%03x\n",
                           i, res, E[i]);
                }
            }
            break;
        }
    }

    if(!got_output){
        printf("FAIL: timeout waiting for out_valid_o\n");
    }
}

int main() {
  sim_init();
  reset(5);
  const int K = 8;

  uint16_t A[8], B[8], E[8];

  // lane 0 : 1.5 * 2.0 = 3.0
  A[0] = encode_fp9(0, 15, 0b100);
  B[0] = encode_fp9(0, 16, 0b000);
  E[0] = encode_fp9(0, 16, 0b100);

  // lane 1 : 3.0 * 3.0 = 9.0
  A[1] = encode_fp9(0, 16, 0b100);
  B[1] = encode_fp9(0, 16, 0b100);
  E[1] = encode_fp9(0, 18, 0b001);

  // lane 2 : -1.5 * 2.0 = -3.0
  A[2] = encode_fp9(1, 15, 0b100);
  B[2] = encode_fp9(0, 16, 0b000);
  E[2] = encode_fp9(1, 16, 0b100);

  // lane 3 : 0.0 * 5.0 = 0.0
  A[3] = encode_fp9(0, 0, 0);
  B[3] = encode_fp9(0, 17, 0b010);
  E[3] = encode_fp9(0, 0, 0);

  // lane 4 : Inf * 2.0 = Inf
  A[4] = encode_fp9(0, 31, 0);
  B[4] = encode_fp9(0, 16, 0);
  E[4] = encode_fp9(0, 31, 0);

  // lane 5 : NaN * 2.0 = NaN
  A[5] = encode_fp9(0, 31, 1);
  B[5] = encode_fp9(0, 16, 0);
  E[5] = encode_fp9(0, 31, 0b100);  // NaN 只需 frac!=0

  // lane 6 : 最小正规数 * 2.0
  A[6] = encode_fp9(0, 1, 0b000);   // 最小正规  exponent=1
  B[6] = encode_fp9(0, 16, 0);
  E[6] = encode_fp9(0, 2, 0);       // exponent 加 1

  // lane 7 : (-0.0) * 3.0 = -0.0
  A[7] = encode_fp9(1, 0, 0);  // -0.0
  B[7] = encode_fp9(0, 17, 0);
  E[7] = encode_fp9(1, 0, 0);  // -0.0

  // fflags
  uint8_t expected_fflags = 0x04;

  run_tc_test("TC MUL (K=8)", A, B, E, expected_fflags, K);
  single_cycle();
  single_cycle();
  single_cycle();
  single_cycle();
  single_cycle();

  sim_exit();
  return 0;
}




