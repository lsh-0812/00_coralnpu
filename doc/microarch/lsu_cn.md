# 加载存储单元（Load Store Unit）

![image](../images/lsu.svg)

加载存储单元（LSU）处理核发出的内存操作。从功能上讲，它的作用是将内存指令翻译成对应子系统上的事务。

## 槽位（Slots）

CoralNPU 的 LSU 使用一个称为 _槽位（slots）_ 的概念来处理内存事务。一个槽位是一种数据结构，管理单条已分发 LSU 操作的状态，并决定应执行什么内存事务。在其核心，每个槽位中都存在一张表，用于跟踪内存操作的哪一部分已经完成。

例如，下面是一次向地址 0xDEADBEEF 进行字存储（word-store）的槽位表：

| 索引（Index） | 活动（Active） |   地址（Address）  | 数据（Data） |
| ----- | ------ | ---------- | ---- |
|   0   |    1   | 0xDEADBEEF | 0x01 |
|   1   |    1   | 0xDEADBEF0 | 0x23 |
|   2   |    1   | 0xDEADBEF1 | 0x45 |
|   3   |    1   | 0xDEADBEF2 | 0x67 |
|   4   |    0   | 0xDEADBEF3 | 0x00 |
...
|   n   |    0   | 0xDEADBEF3 | 0x00 |

通过 TCM 或 AXI 总线进行的内存事务会读/写槽位表中的数据，并在事务发出时将活动位（active bit）翻转为 0。

一个槽位的典型生命周期如下：

1) **Idle（空闲）**：空闲槽位会从命令队列中取出一个 LsuOperation。标量操作会直接进入 **Transfer Memory**，而向量操作会进入 **Vector Update** 状态。
2) **Vector Update（向量更新）**：对于向量操作，需要从 RvvCore 接收掩码（mask）、地址（用于索引型操作）和数据（用于存储操作）。标量操作会跳过此阶段。
3) **Transfer Memory（传输内存）**：只要槽位表中仍有活动条目，就会选择"索引"最低的活动条目进行一次内存事务。然后散布/聚集单元（scatter/gather unit）会选出所有其他可与该事务捆绑的活动条目（不一定连续）。接着选择合适的内存总线（ibus、dbus、ebus）并执行内存事务。当没有活动条目时，槽位进入下一状态（**Writeback**）。
4) **Writeback（写回）**：所有内存事务完成后，结果必须写回寄存器堆。此外，向量存储会被"确认"（acknowledged）回 RvvCore。标量和浮点操作会跳过此阶段。写回完成后，对于 LMUL > 1 的情况槽位回到 **Vector Update** 状态，否则回到 **Idle** 状态。

CoralNPU 目前在 LSU 中使用一个"槽位"。未来可能会增加多个槽位，以允许多个操作参与同一个事务。

## 接口

### LSU 命令接口

LSU 有一个来自分发单元和寄存器堆的命令接口。

| 信号名称   | 类型          | 描述                                                   |
| ------------- | ------------- | ------------------------------------------------------------- |
| req.valid     | Bool          | LSU 命令是否有效。                                  |
| req.op        |               | 要执行的 LSU 操作。                                 |
| req.addr      | UInt(5)       | 对于加载，写入结果的 RegFile 地址。         |
| req.pc        | UInt(32)      | LSU 指令的 PC。用于故障报告。       |
| req.elemWidth | UInt(32)      | 仅在 RVV 中使用。跨步加载（strided load）的 EEW。              |
| req.ready     | Bool（输出）  | 命令是否被接受。用于 ready-valid 握手。 |

### 总线接口

| 信号名称 | 类型              | 描述                                                       |
| ----------- | ----------------- | ----------------------------------------------------------------- |
| ibus.valid  | Bool              | ibus 事务是否有效。                                 |
| ibus.addr   | UInt(32)          | ibus 事务的地址。                              |
| ibus.rdata  | UInt(128)（输入） | 从 ibus 读取的数据。在握手后一个周期到达。  |
| ibus.ready  | Bool（输入）      | 事务是否被接受。用于 ready-valid 握手。 |

| 信号名称 | 类型              | 描述                                                       |
| ----------- | ----------------- | ----------------------------------------------------------------- |
| dbus.valid  | Bool              | dbus 事务是否有效。                                 |
| dbus.addr   | UInt(32)          | dbus 事务的地址。                              |
| dbus.size   | UInt(5)           | 本事务的大小（字节）。                            |
| dbus.pc     | UInt(32)          | LSU 指令的 PC。用于故障报告。           |
| dbus.rdata  | UInt(128)（输入） | 从 dbus 读取的数据。在握手后一个周期到达。  |
| dbus.wdata  | UInt(128)         | 要从 dbus 写出的数据。                                  |
| dbus.wmask  | UInt(16)          | 本事务的字节写掩码。                           |
| dbus.ready  | Bool（输入）      | 事务是否被接受。用于 ready-valid 握手。 |

| 信号名称      | 类型              | 描述                                                       |
| ---------------- | ----------------- | ----------------------------------------------------------------- |
| ebus.valid       | Bool              | ebus 事务是否有效。                                 |
| ebus.addr        | UInt(32)          | ebus 事务的地址。                              |
| ebus.size        | UInt(5)           | 本事务的大小（字节）。                            |
| ebus.pc          | UInt(32)          | LSU 指令的 PC。用于故障报告。           |
| ebus.rdata       | UInt(128)（输入） | 从 ebus 读取的数据。在握手后一个周期到达。  |
| ebus.wdata       | UInt(128)         | 要从 ebus 写出的数据。                                  |
| ebus.wmask       | UInt(16)          | 本事务的字节写掩码。                           |
| ebus.ready       | Bool（输入）      | 事务是否被接受。用于 ready-valid 握手。 |
| ebus.fault.valid | Bool（输入）      | 当外部总线上发生故障时置位。                     |
| ebus.fault.write | Bool（输入）      | 故障是否发生在写操作上。                        |
| ebus.fault.addr  | Bool（输入）      | 故障发生时内存事务的地址。    |
| ebus.fault.epc   | Bool（输入）      | 触发故障的指令的 PC。               |
| ebus.internal    | Bool              | 未使用。                                                         |

### 写回接口

| 信号名称 | 类型     | 描述                                              |
| ----------- | -------- | -------------------------------------------------------- |
| rd.valid    | Bool     | 写回标量寄存器堆是否有效。         |
| rd.addr     | UInt(5)  | 要写回的标量寄存器堆地址。 |
| rd.data     | UInt(32) | 要写入标量寄存器堆的数据。           |

| 信号名称     | 类型     | 描述                                                      |
| --------------- | -------- | ---------------------------------------------------------------- |
| rd_flt.valid    | Bool     | 写回浮点寄存器堆是否有效。         |
| rd_flt.addr     | UInt(5)  | 要写回的浮点寄存器堆地址。 |
| rd_flt.data     | UInt(32) | 要写入浮点寄存器堆的数据。           |

### RVV 接口

对于 RVVCore，LSU 包含以下接口：

| 信号名称            | 类型              | 描述                                                       |
| ---------------------- | ----------------- | ----------------------------------------------------------------- |
| rvv2lsu.valid          | Bool              | rvv2lsu 事务是否有效。                              |
| rvv2lsu.idx.valid      | Bool              | 是否有来自向量寄存器堆的有效索引数据。       |
| rvv2lsu.idx.addr       | UInt(5)           | 来自向量寄存器堆的索引的地址。         |
| rvv2lsu.idx.data       | UInt(128)         | 来自向量寄存器堆索引的索引值。                  |
| rvv2lsu.vregfile.valid | UInt(128)         | 是否有来自向量寄存器堆的有效数据。             |
| rvv2lsu.vregfile.addr  | UInt(5)           | 来自向量寄存器堆的数据的地址。            |
| rvv2lsu.vregfile.data  | UInt(128)         | 本操作要写回的向量数据。                 |
| rvv2lsu.mask           | UInt(16)          | 本事务的字节活动掩码。                        |
| rvv2lsu.ready          | Bool（输入）      | 事务是否被接受。用于 ready-valid 握手。 |

| 信号名称    | 类型              | 描述                                                       |
| -------------- | ----------------- | ----------------------------------------------------------------- |
| lsu2rvv.valid  | Bool              | lsu2rvv 事务是否有效。                              |
| lsu2rvv.addr   | UInt(5)           | 目标向量寄存器堆索引。                       |
| lsu2rvv.data   | UInt(128)         | 加载操作要写回的向量数据。                |
| lsu2rvv.last   | Bool              | 本事务是否为存储。                            |
| lsu2rvv.ready  | Bool（输入）      | 事务是否被接受。用于 ready-valid 握手。 |
