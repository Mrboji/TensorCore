# AXI总线学习

#### 学习连接

[https://www.bilibili.com/video/BV1gj411s7ah/?spm_id_from=333.138...](https://www.bilibili.com/video/BV1gj411s7ah/?spm_id_from=333.1387.collection.video_card.click&amp;vd_source=be27d681d708f544e86d720eb2e9477d "总线学习视频")

[ysyx.oscc.cc/docs/2306/basic/1.7.html](https://ysyx.oscc.cc/docs/2306/basic/1.7.html)

这是ysyx项目关于总线相关的学习视频以及资料，会讲解总线的本质以及AXI总线为什么要这么设计。

#### AXI协议

最规范的学习资料是官方手册，最好还是看手册看到A4章节，如果觉得有些晦涩可以到网上找一些资料看，之后再看手册。

#### 源码

如果时间充足，可以根据手册要求自己手写一个AXI总线，自己写以及调试的过程会对AXI总线的理解深刻一些。

可以参考一下Vivado自定义IP生成的从接口AXI总线协议，也上传了一个可以学习，也可以在网上找些开源的总线实现学习，在阅读源码的时候可以对照着手册理解每段代码对应手册里的哪一句话。

这是我的ysyx代码实现，里面实现了一个AXI-full总线，主从接口以及总线互联都有，ifu部分支持突发传输，lsu部分支持非对齐访存，你们也可以参考一下。

git@github.com:Mrboji/ysyx_cpu.git   

‍
