module fadd_s1#(
    parameter  EXPWIDTH     =   5,
    parameter  PRECISION    =   8,
    parameter  OUTPC        =   4
    //当作为加法树时，EXPWIDTH=5, PRECISION=8, OUTPC=4
    //当作为累加器时，EXPWIDTH=8, PRECISION=28, OUTPC=14
)(
    input                                   clk,//时钟信号
    input                                   rst,//复位信号，低有效
    input                                   en_i, //控制信号 
      //输入数据信号
    input [EXPWIDTH + PRECISION:0]          a_i,//操作数 a
    input [EXPWIDTH + PRECISION:0]          b_i,//操作数 b
      //用于 fma 指令的标志信号，根据需要选择性保留
    input                                   b_inter_valid_i,       //中间结果是否有效
    input                                   b_inter_flags_is_nan_i, //中间结果为 NaN 标志   
    input                                   b_inter_flags_is_inf_i, //中间结果为无穷标志
    input                                   b_inter_flags_is_inv_i, //无效操作标志
    input                                   b_inter_flags_overflow_i, //溢出标志
      //舍入模式控制信号
    input [2:0]                             rm_i,//舍入模式（IEEE 754）
    output [2:0]                            out_rm_o, //传递的舍入模式    
      //输出给下一级的数据信号
    output reg                              out_far_sign_o,//far path 符号位
    output reg[EXPWIDTH - 1:0]              out_far_exp_o,//far path 指数位
    output reg[OUTPC + 3 - 1:0]             out_far_frac_o,//far path 尾数（带保护位）

    output reg                              out_near_sign_o,//near path 符号位
    output reg[EXPWIDTH - 1:0]              out_near_exp_o,//near path 指数位
    output reg[OUTPC + 3 - 1:0]             out_near_frac_o,//near path 尾数（带保护位）
      //特殊情况与异常输出
    output reg                              out_special_case_nan_o,//结果为 NaN 标志
    output reg                              out_special_case_inf_sign_o,//无穷结果的符号位   
    output reg                              out_small_add_o,//小加法标志（表示非规格数加法）
    output reg                              out_far_mul_of_o,//far path 乘法溢出标志
    output reg                              out_near_sig_is_zero_o,//near path 尾数为零标志
      //路径选择信号
    output reg                              out_sel_far_path_o//路径选择信号（1 表示选择far path）
);
    wire [EXPWIDTH + PRECISION:0] result;
    wire [EXPWIDTH + PRECISION:0] result_1,result_2,result_3,result_4;

    wire a_sign, b_sign;
    wire [EXPWIDTH - 1:0] E_a, E_b;
    wire [EXPWIDTH - 1:0] a_exp, b_exp; 
    wire hidden_a,hidden_b;
    wire [PRECISION + 2 :0] a_frac, b_frac;//PRECISION位有效位+2位保护位+1位隐藏位
 
    wire [($clog2(PRECISION + 5) - 1):0] k;
  //wire [($clog2(PRECISION + 5) - 1):0] k_temp[0:PRECISION + 4];
    wire carry;
    wire [EXPWIDTH - 1:0] subtraction;
    wire [EXPWIDTH - 1:0] shift;

    wire [PRECISION + 2:0] lostBits;
    wire [PRECISION + 5:0] sticky;

    wire sign_small, sign_large;
    wire [EXPWIDTH - 1:0] exp_small, exp_large;
    wire [PRECISION + 2:0] frac_small, frac_large;
    wire [PRECISION + 5:0] FRAC_SMALL,FRAC_LARGE;

    wire [PRECISION + 3:0] shifted_fraction_small;

    wire [PRECISION + 5:0] sum,SUM;
    wire [PRECISION + 5:0] normalizedSum;
    wire [PRECISION + 5:0] NorSum;
    wire [PRECISION + 5:0] NorSumm;
    wire [PRECISION + 5:0] Sum;
    wire [PRECISION + 5:0] SUMFINAL;

    wire [EXPWIDTH - 1:0] Exponent,EXPONENT;
    wire [EXPWIDTH - 1:0] EpreFinal;
    wire [EXPWIDTH - 1:0] EFinal;
    wire [EXPWIDTH - 1:0] EFINAL;

    wire out_sel_far_path_o_buffer;

    reg [EXPWIDTH + PRECISION:0] a_reg,b_reg;
    reg [PRECISION + 5:0] FRACTION_SMALL_stage2;
    reg [PRECISION + 5:0] FRACTION_LARGE_stage2;
    reg [EXPWIDTH - 1:0] Exponent_stage2;
    reg [EXPWIDTH + PRECISION:0] a_stage2,b_stage2;
    reg [PRECISION + 5:0] sum_stage2;

    
    

    always@(posedge clk or negedge rst) begin
        if (!rst) begin
            a_reg <= {(EXPWIDTH + PRECISION + 1){1'b0}};
            b_reg <= {(EXPWIDTH + PRECISION + 1){1'b0}};
        end else begin
            a_reg <= a_i;
            b_reg <= b_i;
        end
    end


// 阶段1：解包、对齐
    assign a_sign = a_i[EXPWIDTH + PRECISION];  //符号位
    assign b_sign = b_i[EXPWIDTH + PRECISION];
    assign E_a = a_i[EXPWIDTH + PRECISION -1:PRECISION]; //指数位
    assign E_b = b_i[EXPWIDTH + PRECISION -1:PRECISION];
    assign hidden_a = |E_a ? 1'b1 : 1'b0;//隐藏位 hidden_a = E_a > 0 ? 1'b1 : 1'b0;
    assign hidden_b = |E_b ? 1'b1 : 1'b0;

    assign a_exp = |E_a ? E_a : {{(EXPWIDTH-1){1'b0}}, 1'b1}; //指数位
    assign b_exp = |E_b ? E_b : {{(EXPWIDTH-1){1'b0}}, 1'b1};

    assign a_frac = {hidden_a , a_i[PRECISION - 1:0] , 2'b00};//尾数位 + 有效位 + 2位保护位
    assign b_frac = {hidden_b , b_i[PRECISION - 1:0] , 2'b00};

// 阶码比较与移位计算
    assign {carry,subtraction} = a_exp - b_exp;

    assign sign_small = !carry ? b_sign : a_sign;//sign_small = (carry == 0) ? b_sign : a_sign;
    assign sign_large = !carry ? a_sign : b_sign;//sign_large = (carry == 0) ? a_sign : b_sign;

    assign exp_small = !carry ? b_exp : a_exp;
    assign exp_large = !carry ? a_exp : b_exp;

    assign Exponent = exp_large;

    assign frac_small = !carry ? b_frac : a_frac;
    assign frac_large = !carry ? a_frac : b_frac;

    assign shift = (carry == 0) ? subtraction : (~subtraction + 1'b1);

    assign lostBits = shift <= (PRECISION + 3) ? frac_small<<(PRECISION + 3 - shift) : frac_small;

    assign shifted_fraction_small = {frac_small >> shift, |lostBits};

    // 尾数对齐
    assign FRAC_SMALL = sign_small ? {sign_small,sign_small,(~shifted_fraction_small + 1'b1)} : {sign_small,sign_small,shifted_fraction_small};
    assign FRAC_LARGE = sign_large ? {sign_large,sign_large,(~frac_large + 1'b1),1'b0} : {sign_large,sign_large,frac_large,1'b0};
    assign sum = FRAC_LARGE + FRAC_SMALL;

// 阶段1 -> 阶段2流水线寄存器
    always @(posedge clk or negedge rst) begin
        if(!rst)begin
          FRACTION_LARGE_stage2 <= {(PRECISION + 6){1'b0}};
          FRACTION_SMALL_stage2 <= {(PRECISION + 6){1'b0}};
          Exponent_stage2 <= {(EXPWIDTH){1'b0}};
          a_stage2 <= {(EXPWIDTH + PRECISION + 1){1'b0}};
          b_stage2 <= {(EXPWIDTH + PRECISION + 1){1'b0}};
          sum_stage2 <= {(PRECISION + 6){1'b0}};
        end
        else begin
          FRACTION_LARGE_stage2 <= FRAC_LARGE;
          FRACTION_SMALL_stage2 <= FRAC_SMALL;
          Exponent_stage2 <= Exponent;
          a_stage2 <= a_reg;
          b_stage2 <= b_reg;
          sum_stage2 <= sum;
        end
    end

// 阶段2：加法

assign SUM = sum_stage2[PRECISION + 5] ? (~sum_stage2 + 1'b1) : sum_stage2;

//assign k_temp[0] = {($clog2(PRECISION + 5)){1'b0}};
/*
generate
  for(genvar i = 1;i <= PRECISION + 4; i = i + 1)begin
    assign k_temp[i] = SUM[i] ? i :k_temp[i - 1];
  end
endgenerate
*/
/*
generate
  for(genvar i = PRECISION + 4;i >= 1; i = i - 1)begin
    assign k_temp[i] = SUM[i] ? i[$clog2(PRECISION + 5)-1:0] :k_temp[i - 1];
  end
endgenerate
assign k = k_temp[PRECISION + 4];
*/

//向量前导1检测
    // 内部信号定义

    // 分层检测是否有1存在
generate    //目前仅支持PRECISION=8和PRECISION=28两种情况
  if (PRECISION == 8) begin     
    wire [3:0]  data_chk;           // 5位标志编码
    wire [15:0] expand_SUM_16bit;   // 将 SUM 扩展到16位以适应前导1检测  
    wire [7:0]  Part_1;             // 第一级16位选择 PRECISION=28时需要32位 
    wire [3:0]  Part_2;             // 第二级8位选择
    wire [1:0]  Part_3;             // 第三级4位选择
  //wire [1:0]  Part_4;             // 第四级2位选择

    assign expand_SUM_16bit = {3'b000, SUM[12:0]};
    assign data_chk[3] = |expand_SUM_16bit[15:8];       // 高8位是否有1
    assign data_chk[2] = |Part_1[7:4];                  // 选中的8位中的高4位
    assign data_chk[1] = |Part_2[3:2];                  // 选中的4位中的高2位
    assign data_chk[0] = |Part_3[1];                    // 选中的2位中的高1位
  //assign data_chk[0] = |Part_4[1];                    // 选中的1位中的高0位
  // 逐级选择包含前导1的数据段
    assign Part_1 = (data_chk[3]) ? expand_SUM_16bit[15:8]  : expand_SUM_16bit[7:0];
    assign Part_2 = (data_chk[2]) ? Part_1[7:4]    : Part_1[3:0];
    assign Part_3 = (data_chk[1]) ? Part_2[3:2]    : Part_2[1:0];
  //assign Part_4 = (data_chk[1]) ? Part_3[3:2]    : Part_3[1:0];

    assign k = data_chk;
  end
  else if (PRECISION == 28) begin
    wire [4:0]  data_chk;       // 5位标志编码
    wire [15:0] Part_1;         // 第一级16位选择 PRECISION=28时需要32位 
    wire [7:0]  Part_2;         // 第二级8位选择
    wire [3:0]  Part_3;         // 第三级4位选择
    wire [1:0]  Part_4;         // 第四级2位选择

    assign data_chk[4] = |SUM[31:16];       // 高16位是否有1
    assign data_chk[3] = |Part_1[15:8];    // 选中的16位中的高8位
    assign data_chk[2] = |Part_2[7:4];     // 选中的8位中的高4位
    assign data_chk[1] = |Part_3[3:2];     // 选中的4位中的高2位
    assign data_chk[0] = |Part_4[1];       // 选中的2位中的高1位
  // 逐级选择包含前导1的数据段
    assign Part_1 = (data_chk[4]) ? SUM[31:16]     : SUM[15:0];
    assign Part_2 = (data_chk[3]) ? Part_1[15:8]   : Part_1[7:0];
    assign Part_3 = (data_chk[2]) ? Part_2[7:4]    : Part_2[3:0];
    assign Part_4 = (data_chk[1]) ? Part_3[3:2]    : Part_3[1:0];

    assign k = SUM[32]?{{(($clog2(PRECISION + 5) - 1)-6){1'b0}},6'b100000}:data_chk;
  end
  else begin
        // 非法参数时强制报错，且不生成任何assign
        initial begin
            $fatal(1, "ERROR: PRECISION must be 8 or 28! Current: %0d", PRECISION);
        end
    end
endgenerate
  // 生成最终位置输出
    

/*assign k = SUM[12] ? 12 :
           SUM[11] ? 11 :
           SUM[10] ? 10 :
           SUM[9] ? 9 :
           SUM[8] ? 8 :
           SUM[7] ? 7 :
           SUM[6] ? 6 :
           SUM[5] ? 5 :
           SUM[4] ? 4 :
           SUM[3] ? 3 :
           SUM[2] ? 2 :
           SUM[1] ? 1 : 0;*/


assign normalizedSum = (k > (PRECISION + 2)) ? SUM >> (k - (PRECISION + 3)) : SUM << ((PRECISION + 3) - k);                     //归一化尾数
assign EXPONENT = (k > (PRECISION + 2)) ? Exponent_stage2 + (k - (PRECISION + 3)) : (Exponent_stage2 - ((PRECISION + 3) - k));  //归一化指数 

assign EpreFinal = ((Exponent_stage2 + k) > (PRECISION + 3)) ? EXPONENT : {(EXPWIDTH){1'b0}};
assign NorSum = ((Exponent_stage2 + k) > (PRECISION + 3)) ? normalizedSum : (SUM << (Exponent_stage2 - 1));

// 阶段3：舍入（就近舍入到偶数）
assign sticky = k > (PRECISION + 2) ? SUM << (2*(PRECISION + 4) - k) : SUM << (PRECISION + 5);// 2*(PRECISION + 4) (类似FP32的54=2*27)
assign NorSumm = {NorSum[PRECISION + 5:1], |sticky};
// 4. 舍入逻辑（与FP32完全相同，位宽自适应）,.
/*assign Sum = rm_i == 3'b000 ? NorSumm + 1'b1 : //向正无穷舍入
             rm_i == 3'b001 ? (NorSumm[0] ? NorSumm + 1'b1 : NorSumm) : //向负无穷舍入
             rm_i == 3'b010 ? (NorSumm[PRECISION + 1] ? NorSumm + 1'b1 : NorSumm) : //向零舍入
             rm_i == 3'b011 ? (NorSumm[PRECISION + 1] ? (NorSumm + 1'b1) : NorSumm) : //向最近舍入（就近舍入到偶数）
             rm_i == 3'b100 ? (NorSumm[PRECISION + 1] ? (NorSumm + 1'b1) : NorSumm) : //向最近舍入（就近舍入到偶数）
             rm_i == 3'b101 ? (NorSumm[PRECISION + 1] ? (NorSumm + 1'b1) : NorSumm) : //向最近舍入（就近舍入到偶数）
             rm_i == 3'b110 ? (NorSumm[PRECISION + 1] ? (NorSumm + 1'b1) : NorSumm) : //向最近舍入（就近舍入到偶数）
             rm_i == 3'b111 ? (NorSumm[PRECISION + 1] ? (NorSumm + 1'b1) : NorSumm) : //向最近舍入（就近舍入到偶数）
             NorSumm; //默认不舍入*/
/*assign Sum =  (rm_i == 3'b000) ? (NorSumm + 1'b1) : //向+∞舍入
              (rm_i == 3'b001) ? (NorSumm[0] ? NorSumm + 1'b1 : NorSumm) : //向-∞舍入
              (rm_i == 3'b010) ? (NorSumm[PRECISION + 1] ? NorSumm + 1'b1 : NorSumm) : //向0舍入（截断）
              (rm_i == 3'b011) ? (NorSumm[PRECISION + 1] ? NorSumm + 1'b1 : NorSumm) : //就近舍入到偶数
              NorSumm; //默认就近舍入*/
assign Sum =  NorSumm[2] == 0 ? NorSumm :
              NorSumm[1] == 1 ? (NorSumm + 4'b1000) :
              NorSumm[0] == 1 ? (NorSumm + 4'b1000) :
              NorSumm[3] == 0 ? NorSumm : (NorSumm + 4'b1000);
/*    assign Sum = NorSumm[2] == 0 ? NorSumm :
                 NorSumm[1] == 1 ? (NorSumm + 4'b1000) :
                 NorSumm[0] == 1 ? (NorSumm + 4'b1000) :
                 NorSumm[3] == 0 ? NorSumm : (NorSumm + 4'b1000);*/ //??????
assign EFinal = |SUM ? EpreFinal : {(EXPWIDTH){1'b0}};
//if there is no 1 the exponent and the number are both 0 (denormalized)

assign SUMFINAL = Sum[PRECISION + 4] ? Sum >> 1: Sum;          // 进位则右移一位
assign EFINAL =  Sum[PRECISION + 4] ? EFinal + 1'b1 : EFinal;     // 进位则指数加一
//renormalize in case of special situations after rounding 
/*assign result = (a_i[EXPWIDTH + PRECISION - 1:0] == 0) ? b_i :
                (b_i[EXPWIDTH + PRECISION - 1:0] == 0) ? a_i :
                (a_i[EXPWIDTH + PRECISION - 1:PRECISION]) ? {1'b0 , {EXPWIDTH{1'b1}}, {PRECISION{1'b0}}} : //a is NaN
                (b_i[EXPWIDTH + PRECISION - 1:PRECISION]) ? {1'b0 , {EXPWIDTH{1'b1}}, {PRECISION{1'b0}}}  : //b is NaN
                {sum_stage2[PRECISION + 5], EFINAL, SUMFINAL[PRECISION + 2:3]};
                */
assign result = (|a_reg[EXPWIDTH + PRECISION - 1:0] == 0) ? b_reg : result_1;
assign result_1 = (|b_reg[EXPWIDTH + PRECISION - 1:0] == 0) ? a_reg : result_2;
assign result_2 = (&a_reg[EXPWIDTH + PRECISION - 1:PRECISION]) ? {1'b0 , {EXPWIDTH{1'b1}}, {PRECISION{1'b0}}} : result_3; //a is NaN
assign result_3 = (&b_reg[EXPWIDTH + PRECISION - 1:PRECISION]) ? {1'b0 , {EXPWIDTH{1'b1}}, {PRECISION{1'b0}}}  : result_4; //b is NaN
assign result_4 = {sum_stage2[PRECISION + 5], EFINAL, SUMFINAL[PRECISION + 2:3]};

assign out_sel_far_path_o_buffer = (shift > OUTPC) ? 1'b1 : 1'b0;//路径选择信号（1 表示选择far path）
//assign out_sel_far_path_o = (shift > OUTPC) ? 1'b1 : 1'b0;//路径选择信号（1 表示选择far path）
//阶段5 结果输出

always @(posedge clk or negedge rst) begin
  if(!rst)begin
    out_far_sign_o <= 1'b0;
    out_far_exp_o <= {(EXPWIDTH){1'b0}};
    out_far_frac_o <= {(OUTPC + 3){1'b0}};

    out_near_sign_o <= 1'b0;
    out_near_exp_o <= {(EXPWIDTH){1'b0}};
    out_near_frac_o <= {(OUTPC + 3){1'b0}};

    out_special_case_nan_o <= 1'b0;
    out_special_case_inf_sign_o <= 1'b0;
    out_small_add_o <= 1'b0;
    out_far_mul_of_o <= 1'b0;
    out_near_sig_is_zero_o <= 1'b0;

    out_sel_far_path_o <= 1'b0;
  end
  else begin
    out_far_sign_o <= out_sel_far_path_o_buffer?result[EXPWIDTH + PRECISION] : 1'b0;//far path 符号位
    out_far_exp_o  <= out_sel_far_path_o_buffer?result[EXPWIDTH + PRECISION -1:PRECISION] : {EXPWIDTH{1'b0}};//far path 指数位
  //out_far_frac_o <= out_sel_far_path_o_buffer?result[PRECISION + 2: PRECISION - OUTPC] : {(OUTPC + 3){1'b0}};//far path 尾数（带保护位）
    out_far_frac_o <= out_sel_far_path_o_buffer ? result[(PRECISION - 1) : (PRECISION - 1) - (OUTPC + 3 - 1)] : {(OUTPC + 3){1'b0}};// 截取：隐藏位后1位开始（剥离隐藏位） + OUTPC位有效位 + 3位保护/舍入位

    out_near_sign_o <= !out_sel_far_path_o_buffer?result[EXPWIDTH + PRECISION] : 1'b0;//near path 符号位
    out_near_exp_o  <= !out_sel_far_path_o_buffer?result[EXPWIDTH + PRECISION -1:PRECISION] : {EXPWIDTH{1'b0}};//near path 指数位
  //out_near_frac_o <= !out_sel_far_path_o_buffer?result[PRECISION + 2: PRECISION - OUTPC] : {(OUTPC + 3){1'b0}};//near path 尾数（带保护位）
    out_near_frac_o <= !out_sel_far_path_o_buffer ? result[(PRECISION - 1) : (PRECISION - 1)  - (OUTPC + 3 - 1)] : {(OUTPC + 3){1'b0}};

    out_special_case_nan_o <= (&result[EXPWIDTH + PRECISION -1:PRECISION]) & (|result[PRECISION -1:0]);//结果为 NaN 标志
    out_special_case_inf_sign_o <= result[EXPWIDTH + PRECISION] & (&result[EXPWIDTH + PRECISION -1:PRECISION]) & (!(|result[PRECISION -1:0]));//无穷结果的符号位
    //out_small_add_o <= (shift != 0) & (shift <= OUTPC);//小加法标志（表示非规格数加法）
    out_small_add_o <=  ((hidden_a == 0) || (hidden_b == 0)) & (shift != 0) & (shift <= OUTPC);    // 小移位加法
    out_far_mul_of_o <= out_sel_far_path_o_buffer & (&result[EXPWIDTH + PRECISION -1:PRECISION]);//far path 乘法溢出标志
    out_near_sig_is_zero_o <= !out_sel_far_path_o_buffer & (!(|result[PRECISION-1:0]) );//near path 尾数为零标志

    out_sel_far_path_o <= out_sel_far_path_o_buffer;
  end
end
assign out_rm_o = rm_i; //传递的舍入模式



//assign out_far_sign_o = out_sel_far_path_o?result[EXPWIDTH + PRECISION] : 1'b0;//far path 符号位
//assign out_far_exp_o  = out_sel_far_path_o?result[EXPWIDTH + PRECISION -1:PRECISION] : {EXPWIDTH{1'b0}};//far path 指数位
//assign out_far_frac_o = out_sel_far_path_o?result[PRECISION + 2: PRECISION - OUTPC] : {(OUTPC + 3){1'b0}};//far path 尾数（带保护位）  

//assign out_near_sign_o = !out_sel_far_path_o?result[EXPWIDTH + PRECISION] : 1'b0;//near path 符号位
//assign out_near_exp_o  = !out_sel_far_path_o?result[EXPWIDTH + PRECISION -1:PRECISION] : {EXPWIDTH{1'b0}};//near path 指数位
//assign out_near_frac_o = !out_sel_far_path_o?result[PRECISION + 2: PRECISION - OUTPC] : {(OUTPC + 3){1'b0}};//near path 尾数（带保护位）

//assign out_special_case_nan_o = (|result[EXPWIDTH + PRECISION -1:PRECISION]) & (&result[PRECISION -1:0]);//结果为 NaN 标志
//assign out_special_case_inf_sign_o = result[EXPWIDTH + PRECISION];//无穷结果的符号位
//assign out_small_add_o = (shift != 0) & (shift <= OUTPC);//小加法标志（表示非规格数加法）
//assign out_far_mul_of_o = out_sel_far_path_o & (&result[EXPWIDTH + PRECISION -1:PRECISION]);//far path 乘法溢出标志

//assign out_near_sig_is_zero_o = !out_sel_far_path_o & ( &result[PRECISION + 2:0] );//near path 尾数为零标志
endmodule