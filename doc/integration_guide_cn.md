# CoralNPU 集成指南



本文档介绍如何将 CoralNPU 作为一个 AXI/TileLink 外设集成到更大的系统中。

## AXI

我们提供了一个仅标量（scalar-only）的 CoralNPU 配置，可与基于 AXI 的系统集成。其 SystemVerilog 可通过以下命令生成：

``` bash
bazel build //hdl/chisel/src/coralnpu:core_mini_axi_cc_library_emit_verilog
```

### 模块接口

![CoralNPU AXI](images/coralnpu_axi.svg)

CoralNPU 的接口定义如下：

|   信号束（Signal Bundle）  |                   描述                             |
| ---------------- | --------------------------------------------------------- |
|       clk        | AXI 总线 / CoralNPU 核的时钟。                     |
|      reset       | AXI 总线 / CoralNPU 核的低有效复位信号。  |
|      s_axi       | 一个 AXI4 从（slave）接口，可用于写入 TCM 或访问 CoralNPU 的 CSR。 |
|      m_axi       | 一个 AXI4 主（master）接口，CoralNPU 用它来读写内存/CSR。 |
|       irqn       | 送往 CoralNPU 核的低有效中断。可由外设或其他主处理器触发。 |
|       wfi        | 来自 CoralNPU 核的高有效信号，表示核正在等待中断。该信号有效时，CoralNPU 被时钟门控（clock-gated）。 |
|      debug       | 用于监视 CoralNPU 指令执行的调试接口。该接口通常仅用于仿真。 |
|      halted      | 输出接口，告知核是否在运行。可以忽略。 |
|      fault       | 输出接口，用于判断核是否发生故障。这些信号应连接到系统控制 CPU 的中断线或状态寄存器，以便在 CoralNPU 发生故障或停机时通知。 |

#### AXI 主（master）信号

AR / AW 通道

| 信号 | 行为 |
| ------ | --------- |
| addr   | CoralNPU 希望读/写的地址 |
| prot   | 始终为 2（非特权、不安全、数据） |
| id     | 始终为 0 |
| len    | （突发中的拍数）- 1 |
| size   | 每拍字节数（1、2 或 4） |
| burst  | 始终为 1（INCR） |
| lock   | 始终为 0（普通访问） |
| cache  | 始终为 0（设备，不可缓冲） |
| qos    | 始终为 0 |
| region | 始终为 0 |

R 通道

| 信号 | 行为 |
| ------ | --------- |
| data   | 来自从机的响应数据 |
| id     | 被忽略，但应为 0，因为 CoralNPU 只发出 id 为 0 的事务 |
| resp   | 响应码 |
| last   | 该拍是否为突发中的最后一拍 |

W 通道

| 信号 | 行为 |
| ------ | --------- |
| data   | CoralNPU 希望写入的数据 |
| last   | 该拍是否为突发中的最后一拍 |
| strb   | data 中哪些字节有效 |

B 通道

| 信号 | 行为 |
| ------ | --------- |
| id     | 被忽略，但应为 0，因为 CoralNPU 只发出 id 为 0 的事务（存在一条 RTL 断言对此进行检查） |
| resp   | 响应码 |

注意：所有通道均不支持 USER 信号。

#### AXI 从（slave）信号

AR / AW 通道

| 信号 | 行为 |
| ------ | --------- |
| addr   | 主机希望读/写的地址 |
| prot   | 被忽略 |
| id     | 事务 ID，应在响应拍中被原样返回 |
| len    | （突发中的拍数）- 1 |
| size   | 每拍字节数（1、2、4、8、16） |
| burst  | 0、1 或 2（FIXED、INCR、WRAP） |
| lock   | 被忽略 |
| cache  | 被忽略 |
| qos    | 被忽略 |
| region | 被忽略 |

R 通道

| 信号 | 行为 |
| ------ | --------- |
| data   | 来自 CoralNPU 的响应数据 |
| id     | 事务 ID，应与 AR 的 id 字段匹配 |
| resp   | 响应码（0/OKAY 或 2/SLVERR） |
| last   | 该拍是否为突发中的最后一拍 |

W 通道

| 信号 | 行为 |
| ------ | --------- |
| data   | 主机希望写入 CoralNPU 的数据 |
| last   | 该拍是否为突发中的最后一拍 |
| strb   | data 中哪些字节有效 |

B 通道

| 信号 | 行为 |
| ------ | --------- |
| id     | 事务 ID，应与 AW 的 id 字段匹配 |
| resp   | 响应码（0/OKAY 或 2/SLVERR）

注意：所有通道均不支持 USER 信号。

#### 调试（Debug）信号

| 信号   | 行为 |
| -------- | --------- |
| en       | 4 位值，表示哪些取指车道（fetch lane）处于活动状态 |
| addr     | 32 位值，包含每个取指车道的 PC |
| inst     | 32 位值，包含每个取指车道的指令 |
| cycles   | 周期计数器 |
| dbus     | 关于 LSU 内部事务的信息 |
| -> valid | 该事务是否有效 |
| -> bits  | addr：事务的 32 位地址 |
|          | write：该事务是否为写 |
|          | wdata：事务的 128 位写数据 |
| dispatch | 关于被分发去执行的指令的信息 |
| -> fire  | 本周期该槽位是否分发了一条指令 |
| -> addr  | 指令的 32 位地址 |
| -> inst  | 指令的 32 位值 |
| regfile  | 关于整数寄存器堆写入的信息 |
| -> writeAddr | 预期将要写入的寄存器地址 |
| ->-> valid | 本车道是否分发了一条将写寄存器堆的指令 |
| ->-> bits | 预期写入的 5 位寄存器地址 |
| -> writeData | 对于寄存器堆中的每个端口，关于写入的信息 |
| ->-> valid | 本周期该端口是否发生了写入 |
| ->-> bits_addr | 发生写入的 5 位寄存器地址 |
| ->-> bits_data | 写入寄存器的 32 位值 |
| float | 关于浮点寄存器堆写入的信息 |
| -> writeAddr | 预期将要写入的寄存器地址 |
| ->-> valid | 本周期是否向浮点单元分发了一条指令 |
| ->-> bits | 预期写入的寄存器地址 |
| -> writeData | 对于寄存器堆中的每个端口，关于写入的信息 |
| ->-> valid | 本周期该端口是否发生了写入 |
| ->-> bits_addr | 发生写入的 5 位寄存器地址 |
| ->-> bits_data | 写入寄存器的 32 位值 |


### CoralNPU 内存映射

对 CoralNPU 的内存访问定义如下：

| 区域 |      范围        |  大小  | 对齐 |                 描述                   |
| ------ | ----------------  | ------ | --------- | --------------------------------------------- |
|  ITCM  | 0x0000 -  0x1FFF  |   8kB  |  4 字节  | 存放 CoralNPU 所执行代码的 ITCM 存储。     |
|  DTCM  | 0x10000 - 0x17FFF |  32kB  |  1 字节   | 存放 CoralNPU 所用数据的 DTCM 存储。         |
|  CSR   | 0x30000 - 待定（TBD）     |   待定（TBD）  |  4 字节  | 用于查询/控制 CoralNPU 的 CSR 接口。   |

### 复位注意事项
CoralNPU 采用同步复位策略——为确保正确的复位行为，请在使能内部时钟门控（通过 CSR）或外部门控之前，让时钟在复位有效的情况下运行一个周期。

## 启动 CoralNPU
首先说明一点——在这些示例中，CoralNPU 在整个系统内存映射中位于地址 0x70000000。

1. 必须先初始化 CoralNPU 的指令内存。
```c
volatile uint8_t* coralnpu_itcm = (uint8_t*)0x00000000L;
for (int i = 0; i < coralnpu_binary_len; ++i) {
    coralnpu_itcm[i] = coralnpu_binary[i];
}
```

如果你的系统中存在 DMA 引擎之类的东西，那它可能是初始化 ITCM 的更好选择。

2. 设置起始 PC
如果你的程序链接后起始地址为 0，则可跳过此步。

```c
volatile uint32_t* coralnpu_pc_csr = (uint32_t*)0x00030004L;
*coralnpu_pc_csr = start_addr;
```

3. 释放时钟门控
```c
volatile uint32_t* coralnpu_reset_csr = (uint32_t*)0x00030000L;
*coralnpu_reset_csr = 1;
```

之后，请确保等待一个周期，让 CoralNPU 完成复位。
如果你想配置诸如连接到 CoralNPU 的 fault 或 halted 输出的中断，现在是个好时机。

4. 释放复位
```c
volatile uint32_t* coralnpu_reset_csr = (uint32_t*)0x00030000L;
*coralnpu_reset_csr = 0;
```

此时，CoralNPU 将从第 2 步设定的 PC 开始执行。

5. 监视 `io_halted`
可以通过读取状态 CSR 来检查 CoralNPU 的执行状态：
```c
volatile uint32_t* coralnpu_status_csr = (uint32_t*)0x00030008L;
uint32_t status = *coralnpu_status_csr;
bool halted = status & 1;
bool fault = status & 2;
```

# CoralNPU CSR
注意：这些 CSR 是供 CoralNPU 外部读写的（例如系统中的主处理器）。
它们与通过 Zicsr ISA 扩展访问的 RISC-V CSR 不是一回事。

### 寄存器：`RESET_CONTROL`
*   **偏移（Offset）**：`0x0`
*   **描述**：控制 CoralNPU 核的复位和时钟门控。上电时，核处于复位状态且时钟被门控。要启动核，应先释放时钟门控，再解除复位。

| 位（Bits）  | 名称         | 描述                                                                                             | 访问（Access） | 复位值 |
| :---- | :----------- | :------------------------------------------------------------------------------------------------------ | :----- | :---------- |
| 0     | `RESET`      | 为 1 时核保持复位。为 0 时核不处于复位。                                    | R/W    | 1           |
| 1     | `CLOCK_GATE` | 为 1 时核的时钟被门控。为 0 时核的时钟运行。                                 | R/W    | 1           |
| 31:2  | `RESERVED`   | 保留，写入被忽略，读取返回 0。                                                               | R      | 0           |

### 寄存器：`PC_START`
*   **偏移（Offset）**：`0x4`
*   **描述**：设置 CoralNPU 核的程序计数器。应在解除核复位之前对其编程。

| 位（Bits）  | 名称            | 描述                                         | 访问（Access） | 复位值 |
| :---- | :-------------- | :-------------------------------------------------- | :----- | :---------- |
| 31:0  | `START_ADDRESS` | 核将开始执行的地址。    | R/W    | 0           |

### 寄存器：`STATUS`
*   **偏移（Offset）**：`0x8`
*   **描述**：提供 CoralNPU 核的状态。这是一个只读寄存器。

| 位（Bits）  | 名称       | 描述                                                              | 访问（Access） | 复位值 |
| :---- | :--------- | :----------------------------------------------------------------------- | :----- | :---------- |
| 0     | `HALTED`   | 为 1 时核已停机（例如在执行 `mpause` 指令之后）。        | R      | 0           |
| 1     | `FAULT`    | 为 1 时核遇到了故障。                                | R      | 0           |
| 31:2  | `RESERVED` | 保留，读取返回 0。                                                | R      | 0           |
