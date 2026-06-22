# DMA 引擎（DMA Engine）

DMA 引擎是一个单通道、链表描述符（linked-list descriptor）式的 DMA 控制器，用于把大批量数据搬移从 CPU 卸载下来。它同时作为主机（master，用于读/写事务）和设备（slave，用于 CPU 通过 CSR 编程）连接到现有的 TileLink-UL 交叉开关（crossbar）。

如果没有 DMA 引擎，所有的内存传输（将模型权重从 SRAM/DDR 加载到 TCM、流式传输外设数据）都必须由 CPU 执行，从而阻塞执行。

## 架构

DMA 引擎有两个 TileLink-UL 端口：

- **主机端口（Host port）**（128 位）：在交叉开关上发出 Get/PutFullData 事务，以从源地址读取并向目标地址写入。
- **设备端口（Device port）**（32 位）：接受来自 CPU 的 CSR 读/写事务，以对 DMA 进行编程和监控。

引擎处理存储在内存中的一个描述符链表。每个描述符定义一次传输：源地址、目标地址、长度、拍大小（beat size）以及可选的外设流控参数。描述符通过 `next_desc` 指针串接；值为 0 表示链结束。

### 传输模式

| 模式 | 源地址 | 目标地址 | 用例 |
|------|-----------|----------|----------|
| Mem→Mem | 递增 | 递增 | SRAM↔DDR、SRAM→ITCM/DTCM |
| Mem→Periph | 递增 | 固定 | SRAM→SPI TX FIFO |
| Periph→Mem | 固定 | 递增 | I2C RX→SRAM |

### 关键参数

- **主机端口位宽**：128 位（与交叉开关公共位宽匹配）
- **设备端口位宽**：32 位（CSR 访问，类似 GPIO/SPI）
- **每个描述符最大传输量**：16 MB（24 位长度字段）
- **未完成事务数（Outstanding transactions）**：1（单一 source ID，读一写一）
- **中断**：v1 无中断（CPU 轮询 STATUS 寄存器）

## 寄存器映射

基地址：`0x40050000`（4 KB 区域，位于 `0x40040000` 的 I2C 之后）

| 偏移 | 名称 | 访问 | 位（Bits） | 描述 |
|--------|------|--------|------|-------------|
| `0x00` | CTRL | RW | [0] enable, [1] start (W1S, self-clearing), [2] abort | 控制 |
| `0x04` | STATUS | RO | [0] busy, [1] done, [2] error, [7:4] error_code | 状态 |
| `0x08` | DESC_ADDR | RW | [31:0] | 内存中第一个描述符的地址 |
| `0x0C` | CUR_DESC | RO | [31:0] | 当前正在执行的描述符的地址 |
| `0x10` | XFER_REMAIN | RO | [23:0] | 当前传输中剩余的字节数 |

### 编程顺序

```
1. Build descriptor chain in memory (SRAM or DDR)
2. Write DESC_ADDR with address of first descriptor
3. Write CTRL with enable=1, start=1
4. Poll STATUS.done until set
5. Check STATUS.error
```

## 描述符格式

描述符为 32 字节（两个 128 位 TL-UL 拍），且在内存中必须 32 字节对齐。DMA 通过其主机端口取回它们。

```
Offset  Field         Bits     Description
0x00    src_addr      [31:0]   Source address
0x04    dst_addr      [31:0]   Destination address
0x08    xfer_len      [23:0]   Transfer length in bytes
        xfer_width    [26:24]  Beat size: log2(bytes). 0=1B, 1=2B, 2=4B, 3=8B, 4=16B
        flags         [31:27]  [27] src_fixed, [28] dst_fixed, [29] poll_en, [30:31] reserved
0x0C    next_desc     [31:0]   Address of next descriptor (0 = end of chain)
0x10    poll_addr     [31:0]   Status register address to poll (0 = no polling)
0x14    poll_mask     [31:0]   Bitmask applied to polled value
0x18    poll_value    [31:0]   Expected value after masking
0x1C    reserved      [31:0]
```

## 外设流控（Peripheral Flow Control）

像 SPI 主机这样的外设会暴露状态寄存器（TX Full、RX Empty 标志）。DMA 使用 **描述符级状态轮询（descriptor-level status polling）** 来调节传输节奏，而无需对外设做任何修改。

每个描述符包含一个可选的 `poll_addr` / `poll_mask` / `poll_value` 三元组。当配置好后（`poll_en` 置位且 `poll_addr != 0`），DMA 在每个数据拍之前读取 `poll_addr`，并等待直到 `(read_data & poll_mask) == poll_value`。

### 示例：DMA → SPI TX

```
Descriptor:
  src_addr   = 0x20000000  (SRAM buffer)
  dst_addr   = 0x40020008  (SPI TXDATA register)
  dst_fixed  = 1
  poll_addr  = 0x40020000  (SPI STATUS register)
  poll_mask  = 0x00000004  (bit 2 = TX Full)
  poll_value = 0x00000000  (wait until TX not full)
```

DMA 读取 SPI STATUS，检查 `(status & 0x4) == 0`，只有满足时才读取下一个源字节并写入 TXDATA。这自然地把 DMA 的节奏调节到 SPI 的时钟速率。

### 示例：I2C RX → DMA

```
Descriptor:
  src_addr   = 0x40040008  (I2C RXDATA register)
  dst_addr   = 0x20001000  (SRAM buffer)
  src_fixed  = 1
  poll_addr  = 0x40040000  (I2C STATUS register)
  poll_mask  = 0x00000002  (bit 1 = RX available)
  poll_value = 0x00000002  (wait until RX data ready)
```

## 状态机

```
IDLE ──[start]──► FETCH_DESC_0 ──[d.fire]──► FETCH_DESC_1 ──[d.fire]──► POLL_CHECK
  ▲                                                                          │
  │                                                          [no poll or match]
  │                                                                          ▼
  │                                                                   XFER_READ_REQ
  │                                                                          │
  │                  [poll_en &&                                         [a.fire]
  │                   mismatch]                                              ▼
  │                       │                                          XFER_READ_RESP
  │                  POLL_REQ ◄── POLL_RESP                                  │
  │                       │          ▲  │                                [d.fire]
  │                  [a.fire]        │  │                                     ▼
  │                       ▼          │  [match]                       XFER_WRITE_REQ
  │                  POLL_RESP ──────┘     │                                 │
  │                                        ▼                            [a.fire]
  │                                  XFER_READ_REQ                           ▼
  │                                                                   XFER_WRITE_RESP
  │                                                                          │
  │                                                               [d.fire, remaining>0]
  │                                                                     ──► POLL_CHECK
  │                                                               [d.fire, remaining==0,
  │                                                                next!=0]
  │                                                                     ──► FETCH_DESC_0
  │                                                               [d.fire, remaining==0,
  │                                                                next==0]
  │                                                                          │
  └────────────────────────── DONE ◄─────────────────────────────────────────┘
```

### 状态描述

- **IDLE**：等待 `CTRL.start`。锁存 `DESC_ADDR`。
- **FETCH_DESC_0**：为描述符字节 0–15（src_addr、dst_addr、len/flags、next_desc）发出 TL-UL Get（128 位）。
- **FETCH_DESC_1**：为描述符字节 16–31（poll_addr、poll_mask、poll_value）发出 TL-UL Get（128 位）。
- **POLL_CHECK**：如果 `poll_en` 置位且 `poll_addr != 0`，则进入 POLL_REQ。否则跳到 XFER_READ_REQ。
- **POLL_REQ**：在 `poll_addr` 处发出 TL-UL Get（32 位）。
- **POLL_RESP**：捕获 D 通道数据。如果 `(data & poll_mask) == poll_value`，则进入 XFER_READ_REQ。否则循环回到 POLL_REQ。
- **XFER_READ_REQ**：在当前源地址处以配置的拍大小发出 TL-UL Get。
- **XFER_READ_RESP**：将 D 通道数据捕获到缓冲寄存器中。
- **XFER_WRITE_REQ**：用缓冲的数据向目标地址发出 TL-UL PutFullData。
- **XFER_WRITE_RESP**：在 D 应答（ack）时，更新地址（除非为固定）和剩余长度。如果剩余 > 0，循环到 POLL_CHECK。如果剩余 == 0 且 `next_desc != 0`，进入 FETCH_DESC_0。否则进入 DONE。
- **DONE**：置位 `STATUS.done`，返回 IDLE。

从任意状态中止（Abort）都会转入 IDLE 并置位错误标志。
TL-UL D 通道错误会转入 DONE 并带上错误码。

## TileLink 主机接口

单个 128 位 TL-UL 主机端口。生成：

- **Get**（读）：opcode=4，size=`xfer_width`，address=`src_addr`，mask=对应 size 的全 1
- **PutFullData**（写）：opcode=0，size=`xfer_width`，address=`dst_addr`，data=缓冲区
- **Poll Get**：opcode=4，size=2（32 位），address=`poll_addr`
- **Descriptor Get**：opcode=4，size=4（16 字节），address=`desc_addr` / `desc_addr+16`

Source ID 始终为 0（单一未完成事务）。

主机 A 通道在描述符取回、轮询读取、数据读取和数据写入之间共享。FSM 驱动一个多路选择器，根据当前状态选择合适的 opcode/address/data/size。

## TileLink 设备接口

遵循 GPIO 的模式（`hdl/chisel/src/bus/GPIO.scala`）：

- `tl_a.ready := !tl_d_valid`
- 在 `tl_a.fire` 时：解码 `address[11:0]`，读/写 CSR
- start 位触发状态机启动

## 交叉开关集成

### 地址映射

DMA 占用 `0x40050000–0x40050FFF`（4 KB），位于 `0x40040000` 的 I2C 之后。

### 主机连通性

DMA 主机端口连接到它可能需要访问的所有内存和外设设备：

```
"dma" -> Seq("sram", "coralnpu_device", "rom", "ddr_ctrl", "ddr_mem",
             "spi_master", "gpio", "i2c_master", "uart0", "uart1")
```

CPU 也必须能够对 DMA 编程：

```
"coralnpu_core" -> Seq(...existing..., "dma")
```

## 实现

单个新文件：`hdl/chisel/src/bus/DmaEngine.scala`

配置改动位于：
- `hdl/chisel/src/soc/CrossbarConfig.scala` —— 主机、设备、地址范围、连接
- `hdl/chisel/src/soc/SoCChiselConfig.scala` —— `DmaParameters`、模块配置
- `hdl/chisel/src/soc/CoralNPUChiselSubsystem.scala` —— 实例化分支（case）

### 模块 IO

```scala
class DmaEngine(hostParams: Parameters, deviceParams: Parameters) extends Module {
  val hostTlulP = new TLULParameters(hostParams)
  val deviceTlulP = new TLULParameters(deviceParams)
  val io = IO(new Bundle {
    val tl_host   = new OpenTitanTileLink.Host2Device(hostTlulP)
    val tl_device = Flipped(new OpenTitanTileLink.Host2Device(deviceTlulP))
  })
}
```

### 内部结构

- **CSR 寄存器堆**：CTRL、STATUS、DESC_ADDR 的寄存器，遵循 GPIO 模式
- **描述符锁存（Descriptor latch）**：所有描述符字段的寄存器，在 FETCH 状态期间加载
- **数据缓冲区**：用于"先读后写"流水线的 128 位寄存器
- **地址计数器**：当前 src/dst 地址、剩余字节计数
- **FSM**：使用上面列出的状态的 ChiselEnum
- **完整性（Integrity）**：主机 A 通道使用 `RequestIntegrityGen`，设备 D 通道使用 `ResponseIntegrityGen`
