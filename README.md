
```
project
├── build
├── csrc               \\testbench
├── Makefile           
├── README.md
└── vsrc               \\RTL
```
vsrc文件夹下存放RTL代码，csrc文件夹下存放testbench，每一个模块对应一个testbench。

对一个模块的仿真需要在Makefile中修改TOPNAME变量指定顶层模块，相应的testbench文件名需要写成tb_+顶层模块名的形式。

testbench中包含的顶层模块相关头文件需要修改成对应模块，之后在main函数中实现仿真激励的输入。

