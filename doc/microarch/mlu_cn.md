# 乘法单元（Multiplication Unit）

乘法单元（MLU）执行乘法运算：MUL、MULH、MULHSU 和 MULHU。

## 接口

MLU 的输入是来自分发单元（Dispatch Unit）的指令，或来自寄存器堆（Register File）的数据读取。CoralNPU 核中唯一的 MLU 可以服务来自四条指令车道中任意一条的指令，但任何一个周期内只分发一条命令。

MLU 的输出是对寄存器堆的写入。

图 1 展示了 MLU 的输入与输出。

![image](../images/mlu_interfaces.png)

图 1：Mlu 接口

### MLU 输入

注意：以下每个信号都有 4 个实例（每条指令车道一个）。

| 信号名称  | 类型          | 描述                                                        |
| ------------ | ------------- | ------------------------------------------------------------------ |
| req.valid    | Bool          | 命令是否有效。                                           |
| req.op       |               | 要执行的功能。                                           |
| req.addr     | UInt(5)       | 写入结果的 RegFile 地址。                        |
| req.ready    | Bool（输出）  | 命令是否被接受。用于 ready-valid 握手。      |
| rs1.valid    | Bool          | 本周期是否有有效的 rs1 读取。仅用于断言。 |
| rs1.data     | UInt(32)      | 从 RegFile 读取的 rs1 数据。                                |
| rs2.valid    | Bool          | 本周期是否有有效的 rs1 读取。仅用于断言。 |
| rs2.data     | UInt(32)      | 从 RegFile 读取的 rs2 数据。                                |

### MLU 输出

| 信号名称 | 类型     | 描述                                                                       |
| ----------- | -------- | --------------------------------------------------------------------------------- |
| rd.valid    | Bool     | 命令是否有效。                                                          |
| rd.addr     | UInt(5)  | 写入结果的 RegFile 地址。                                       |
| rd.data     | UInt(32) | 要写入 RegFile 的计算结果。                                       |
| rd.ready    | Bool     | 写结果是否被 RegFile 接受。用于 ready-valid 握手。 |

### 时序/流水线

MLU 是一条三级流水线，各级如下：

1. **分发（Dispatch）：** 分发单元判断 MLU 操作是否可以执行。在四条车道中，MLU 接受第一条有效的 MLU 指令。该请求将在下一周期被处理。
2. **计算（Compute）：** 第二级使用从 rs1 和 rs2 读取的寄存器数据执行乘法计算。
2. **写回（Writeback）：** 乘法结果被存回寄存器堆。

图 2 展示了与该波形的一次典型交互：

![image](../images/mlu_waveform.png)

图 2：Mlu 波形。
