# I2C 主机（I2C Master）

本目录包含 I2C 主机 IP 块。它实现了一个标准的 I2C 主机，带有 TileLink-UL（TL-UL）接口。

## 寄存器

| 偏移 | 名称        | 描述                                       |
|--------|-------------|---------------------------------------------------|
| 0x000  | INTR_STATE  | 中断状态寄存器（W1C）。Bit 0 为 `tx_idle`|
| 0x004  | INTR_ENABLE | 中断使能寄存器。                        |
| 0x008  | CTRL        | 控制寄存器。Bit 0 使能 I2C 主机。   |
| 0x00C  | STATUS      | 状态寄存器。                                  |
| 0x010  | FDATA       | FIFO 数据与命令寄存器。                   |
| 0x014  | FIFO_CTRL   | FIFO 控制寄存器（当前保留）。       |
| 0x018  | CLK_DIV     | 时钟分频器。指定 I2C 时钟的半周期。  |

### STATUS 寄存器（0x00C）
* **Bit 0**：`busy` —— I2C 状态机非空闲。
* **Bit 1**：`!fifo_empty` —— TX FIFO 非空。
* **Bit 2**：`rx_fifo_valid` —— RX FIFO 有有效数据。

### FDATA 寄存器（0x010）
向该寄存器写入会把一条命令和数据压入 TX FIFO。
从该寄存器读取会从 RX FIFO 弹出数据。

**写入格式：**
* **Bits 7:0**：要发送的数据。
* **Bit 8**：`START` —— 在发送该字节之前发出一个 START（或重复 START）条件。
* **Bit 9**：`STOP` —— 在发送/接收该字节之后发出一个 STOP 条件。
* **Bit 10**：`READ` —— 执行 I2C 读而非写。

**读取格式：**
* **Bits 7:0**：接收到的数据。

## 编程模型

1. 配置 `CLK_DIV` 寄存器。
   I2C 位周期为 4 × `CLK_DIV` 个系统时钟周期。
2. 将 `CTRL` 寄存器的 Bit 0 置 1 以使能 I2C 主机。

### 示例：I2C 写
向地址为 `0x55` 的从机的寄存器 `0x02` 写入数据 `0xDE`：
1. 写 `FDATA`，`START`=1，`Data`=`(0x55 << 1) | 0`。
2. 写 `FDATA`，`START`=0，`Data`=`0x02`。
3. 写 `FDATA`，`STOP`=1，`Data`=`0xDE`。

### 示例：I2C 读
从地址为 `0x55` 的从机读取寄存器 `0x02`：
1. 写 `FDATA`，`START`=1，`Data`=`(0x55 << 1) | 0`。
2. 写 `FDATA`，`START`=0，`Data`=`0x02`。
3. 写 `FDATA`，`START`=1，`Data`=`(0x55 << 1) | 1`（重复 Start，读）。
4. 写 `FDATA`，`READ`=1，`STOP`=1。
5. 等待事务完成（检查 `STATUS` 的 busy/fifo_empty 位）。
6. 读 `FDATA` 以获取接收到的字节。
