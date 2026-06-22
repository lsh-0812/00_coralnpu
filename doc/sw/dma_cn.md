# DMA 引擎软件指南

## 概述

CoralNPU DMA 引擎把大批量数据传输从 CPU 卸载下来。它使用内存中的描述符链支持内存到内存、内存到外设、外设到内存的传输。CPU 构建一个或多个描述符，对 DMA 编程，然后轮询完成。

## 寄存器映射

基地址：`0x40050000`

| 偏移 | 名称        | 访问 | 描述 |
|--------|-------------|--------|-------------|
| 0x00   | CTRL        | RW     | `[0]` enable（使能），`[1]` start（启动，写 1 置位，自清零），`[2]` abort（中止） |
| 0x04   | STATUS      | RO     | `[0]` busy（忙），`[1]` done（完成），`[2]` error（错误），`[7:4]` error_code（错误码） |
| 0x08   | DESC_ADDR   | RW     | 第一个描述符的地址 |
| 0x0C   | CUR_DESC    | RO     | 当前描述符的地址 |
| 0x10   | XFER_REMAIN | RO     | 当前传输中剩余的字节数 |

### STATUS 错误码

| 码 | 含义 |
|------|---------|
| 0    | 无错误 |
| 1    | 描述符取回错误 |
| 2    | 轮询读取错误 |
| 3    | 数据读取错误 |
| 4    | 数据写入错误 |
| 5    | 中止（Abort） |

## 描述符格式

描述符必须 **32 字节对齐**，并位于 DMA 可访问的内存中（SRAM 或 DDR）。每个描述符为 32 字节：

```
Offset  Field        Bits      Description
0x00    src_addr     [31:0]    Source address
0x04    dst_addr     [31:0]    Destination address
0x08    len_flags    [23:0]    Transfer length in bytes
                     [26:24]   Beat width: log2(bytes) — 0=1B, 1=2B, 2=4B
                     [27]      src_fixed: source address does not increment
                     [28]      dst_fixed: destination address does not increment
                     [29]      poll_en: enable flow-control polling
                     [31:30]   Reserved
0x0C    next_desc    [31:0]    Next descriptor address (0 = end of chain)
0x10    poll_addr    [31:0]    Address to poll before each beat
0x14    poll_mask    [31:0]    Bitmask for poll comparison
0x18    poll_value   [31:0]    Expected value after masking
0x1C    reserved     [31:0]    Must be 0
```

### C 描述符结构体

```c
struct __attribute__((packed, aligned(32))) dma_descriptor {
  uint32_t src_addr;
  uint32_t dst_addr;
  uint32_t len_flags;
  uint32_t next_desc;
  uint32_t poll_addr;
  uint32_t poll_mask;
  uint32_t poll_value;
  uint32_t reserved;
};
```

### 构造 len_flags

```c
static inline uint32_t make_len_flags(uint32_t len, uint32_t width_log2,
                                       int src_fixed, int dst_fixed,
                                       int poll_en) {
  return (len & 0xFFFFFF) | ((width_log2 & 0x7) << 24) |
         ((src_fixed ? 1u : 0u) << 27) | ((dst_fixed ? 1u : 0u) << 28) |
         ((poll_en ? 1u : 0u) << 29);
}
```

## 编程顺序

```c
#define REG32(addr) (*(volatile uint32_t*)(addr))
#define DMA_BASE       0x40050000
#define DMA_CTRL       (DMA_BASE + 0x00)
#define DMA_STATUS     (DMA_BASE + 0x04)
#define DMA_DESC_ADDR  (DMA_BASE + 0x08)

// 1. Build descriptor(s) in memory
desc->src_addr  = src;
desc->dst_addr  = dst;
desc->len_flags = make_len_flags(nbytes, 2 /* 4-byte beats */, 0, 0, 0);
desc->next_desc = 0;  // single descriptor

// 2. Program and start DMA
REG32(DMA_DESC_ADDR) = (uint32_t)desc;
REG32(DMA_CTRL) = 0x3;  // enable + start

// 3. Wait for completion
while (!(REG32(DMA_STATUS) & 0x2)) {}  // poll done bit

// 4. Check for errors
if (REG32(DMA_STATUS) & 0x4) {
  // error occurred, check error_code in bits [7:4]
}
```

## 传输模式

### 内存到内存（Memory-to-Memory）

标准的大批量拷贝。源地址和目标地址都递增。

```c
desc->len_flags = make_len_flags(nbytes, 2, 0, 0, 0);
```

### 内存到外设（固定目标）

源地址递增，目标地址保持固定。适用于写入外设的 FIFO 或数据寄存器。

```c
desc->src_addr  = (uint32_t)sram_buffer;
desc->dst_addr  = 0x40020008;  // e.g., SPI TXDATA register
desc->len_flags = make_len_flags(nbytes, 2, 0, 1, 0);  // dst_fixed=1
```

### 外设到内存（固定源）

源地址保持固定，目标地址递增。适用于将外设的接收寄存器排空到缓冲区。

```c
desc->src_addr  = 0x40040008;  // e.g., I2C RXDATA register
desc->dst_addr  = (uint32_t)sram_buffer;
desc->len_flags = make_len_flags(nbytes, 2, 1, 0, 0);  // src_fixed=1
```

## 描述符链接（Chaining）

多个描述符可通过 `next_desc` 链接。DMA 会自动按顺序取回并执行每个描述符。在最后一个描述符上设置 `next_desc = 0`。

```c
desc0->next_desc = (uint32_t)desc1;
desc1->next_desc = 0;  // end of chain

REG32(DMA_DESC_ADDR) = (uint32_t)desc0;
REG32(DMA_CTRL) = 0x3;
```

只有在整个链完成后，STATUS.done 才会被置位。

## 使用轮询的流控

对于外设传输，DMA 可以在每个数据拍之前轮询一个状态寄存器，以避免 FIFO 溢出。设置 `poll_en=1` 并配置轮询字段：

```c
// Wait until SPI TX FIFO is not full before each write
desc->len_flags = make_len_flags(nbytes, 0, 0, 1, 1);  // poll_en=1, dst_fixed=1
desc->poll_addr  = 0x40020000;  // SPI STATUS register
desc->poll_mask  = 0x00000004;  // bit 2 = TX Full
desc->poll_value = 0x00000000;  // proceed when TX not full
```

DMA 读取 `poll_addr` 并检查 `(read_data & poll_mask) == poll_value`。如果条件不满足，它会重试直到满足为止。这在不修改外设设计的前提下提供了硬件管理的流控。

## 中止一次传输

向 CTRL 的 bit 2 写入以中止一次进行中的传输：

```c
REG32(DMA_CTRL) = 0x4;  // abort
```

中止后，STATUS 将显示 `done=1, error=1, error_code=5`。

## 约束

- 描述符必须 32 字节对齐
- 每个描述符最大传输量：16 MB（24 位长度字段）
- 拍宽度（beat width）不得超过总线位宽（128 位 / 16 字节）
- DMA 一次只发出一个未完成事务（无突发流水）
- 不支持中断；请对 STATUS.done 使用轮询
