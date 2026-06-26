# Coral NPU

Coral NPU 是一款用于机器学习推理的硬件加速器。它是由 Google Research 设计的开源 IP，可免费集成到面向可穿戴设备（如耳戴式设备、增强现实（AR）眼镜和智能手表）的超低功耗片上系统（SoC）中。

Coral NPU 是一个神经处理单元（NPU），也称为 AI 加速器或深度学习处理器。Coral NPU 基于 32 位 RISC-V 指令集架构（ISA）。

Coral NPU 包含三个协同工作的独立处理器组件：矩阵（matrix）、向量（vector，SIMD）和标量（scalar）。

![Coral NPU Archicture](doc/images/arch_data_flow.png)
[Coral NPU 架构数据手册](https://developers.google.com/coral/guides/hardware/datasheet)

## Coral NPU 特性
Coral NPU 提供以下顶层特性集：

* RV32IMF_Zve32x RISC-V 指令集（具体为 `rv32imf_zve32x_zicsr_zifencei_zbb`）

* 面向应用程序和操作系统内核的 32 位地址空间

* 四级处理器流水线，按序分发（in-order dispatch），乱序退休（out-of-order Retirement ，**乱序引退”** 或 **“乱序提交**）

  > **乱序引退（Out-of-order Retirement）** 打破了上述限制。它允许指令在执行完成后，**不按照程序原本的先后顺序，谁先做好谁就直接引退并释放资源**，不需要在 ROB（ROB, Reorder Buffer） 中排队死等前面的慢速指令。

* 四路标量、两路向量分发

* 128 位 SIMD，256 位（未来）流水线

* 8 KB ITCM 内存（用于指令的紧耦合内存）

* 32 KB DTCM 内存（用于数据的紧耦合内存）

* 两种内存均为单周期延迟 SRAM，比缓存内存更高效

* AXI4 总线接口，同时充当主机（manager）和从机（subordinate），用于与外部内存交互，并允许外部 CPU 配置 Coral NPU

## 系统要求

* Bazel 7.4.1
* Python 3.9-3.12（3.13 支持正在开发中）
* [SRecord](https://srecord.sourceforge.net/)

## 快速开始

```bash
# 确保测试套件通过
bazel run //tests/cocotb:core_mini_axi_sim_cocotb

# 构建一个二进制程序
bazel build //examples:coralnpu_v2_hello_world_add_floats

# 构建仿真器（非 RVV 版本，构建时间更短）：
bazel build //tests/verilator_sim:core_mini_axi_sim

# 在仿真器上运行该二进制程序：
bazel-bin/tests/verilator_sim/core_mini_axi_sim --binary bazel-out/k8-fastbuild-ST-dd8dc713f32d/bin/examples/coralnpu_v2_hello_world_add_floats.elf
```


![](doc/images/Coral_Logo_200px-2x.png)
