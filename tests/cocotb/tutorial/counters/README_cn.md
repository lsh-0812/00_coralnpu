# RISC-V 性能监控：周期计数器与指令计数器

本文档讲解在 Coralnpu 中如何使用机器周期计数器 CSR（mcycle/mcycleh）和机器指令退休计数器（minstret/minstreth）进行性能监控与测量。

## 概述

周期计数器 CSR（mcycle/mcycleh）：跟踪处理器自复位以来执行的时钟周期数。

指令退休计数器（minstret/minstreth）：跟踪处理器退休（成功完成）的指令总数。

周期数和指令数通过汇编接口从寄存器读取，例如：
```
read cycles and store.

asm volatile(
      "1:"
      "  csrr %0, mcycleh;"  // Read `mcycleh`.
      "  csrr %1, mcycle;"   // Read `mcycle`.
      "  csrr %2, mcycleh;"  // Read `mcycleh` again.
      "  bne  %0, %2, 1b;"
      : "=r"(cycle_high), "=r"(cycle_low), "=r"(cycle_high_2)
      :);

```c

读取周期与重置的定义请参考 sw/utils/utils.h。读取周期数和指令数的伪代码如下。

```
cycle_counter_reset();
cycle_start = mcycle_read();
// define compute workload to be measured
cycle_end = mcycle_read();
uint64_t cycle_count = cycle_end - cycle_start;
// store cycle_count to a buffer.
// A similar steps above can used to read number of instructions using
// instrut_counter_reset() minstret_read()
```c

## 运行示例

```
$ bazel run -c opt tests/cocotb/tutorial/counters:cocotb_counter_test
```c
