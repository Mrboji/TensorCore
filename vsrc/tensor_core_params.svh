`ifndef TENSOR_CORE_PARAMS_VH
`define TENSOR_CORE_PARAMS_VH

// TensorCore1 规格的全局默认参数。
`define TC_MATRIX_BUS_WIDTH 512
`define TC_SHAPE_M          8
`define TC_SHAPE_N          8
`define TC_SHAPE_K          8
`define TC_EXPWIDTH         5
`define TC_PRECISION        4
`define TC_OUTPC            4   // 远/近平路径尾数片段位宽
`define TC_OUTPC_ACC        14  // 累加器远/近平路径尾数片段
`define TC_FP_AB_WIDTH      (`TC_EXPWIDTH + `TC_PRECISION) // fp9 e5m3 → 9bit
`define TC_FP_C_MAX_WIDTH   22  // 累加（fp4-fp22）最大位宽
`define TC_NUM_THREAD       8
`define TC_DEPTH_WARP       5
`define TC_MAC_PER_THREAD   2
`define TC_VL               (`TC_NUM_THREAD) // 向量长度（rm/fflags）
`define TC_CTRL_C_WIDTH     16               // C 控制位宽占位
`define TC_FFLAGS_WIDTH     5

// SRAM 尺寸相关参数。
`define TC_SRAM_DEPTH      1024
`define TC_SRAM_ADDR_WIDTH 10

`define DEPTH_WARP          $clog2(`NUM_WARP) //the depth of warp
`define NUM_WARP            8      //the number of warp,CTA need

`endif // TENSOR_CORE_PARAMS_VH
