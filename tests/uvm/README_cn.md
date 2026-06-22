# CoralNPU UVM 测试台

本文档描述用于验证 `RvvCoreMiniVerificationAxi` DUT 的 UVM 测试台的结构与用法。

## 概述

该测试台提供了一个基础的 UVM 环境，用于：
* 实例化 `RvvCoreMiniVerificationAxi` DUT。
* 将 AXI 主（Master）、AXI 从（Slave）和 IRQ 接口连接到 DUT。
* 通过 UVM 序列（sequences）提供基础的激励生成。
* 包含一个简单的反应式（reactive）AXI 从机模型。
* 使用后门（backdoor）访问将二进制文件加载到 DUT 的内存中。
* 通过初始的 AXI 写入启动 DUT 执行。
* 通过 DUT 的状态信号（`halted`、`fault`）或超时来检查基本的测试完成情况。

## 前置条件

* **Synopsys VCS：** 本测试台配置为使用 Synopsys VCS 运行。
* **UVM：** VCS 需要配置为启用 UVM 1.2 支持。
* **CoralNPU 硬件仓库：** 需要访问包含 `RvvCoreMiniVerificationAxi` 源代码的仓库，以生成 DUT 的 Verilog 和测试二进制。
* **Bazel：** 用于从 CoralNPU 硬件仓库的 Chisel 源生成 Verilog 的构建系统。
* **RISC-V 工具链：** 需要一个与 CoralNPU 项目兼容的 RISC-V 工具链来生成 `.elf` 文件。
* **CoralNPU MPACT 仓库：** 将 `CORALNPU_MPACT` 环境变量设置为 `coralnpu-mpact` 仓库的绝对路径。这是协同仿真（co-simulation）所必需的。

## 生成测试二进制（program.elf）

DUT 运行的测试程序需要被编译为 elf 格式。

1.  进入 CoralNPU 硬件仓库根目录：
    ```bash
    cd /path/to/your/coralnpu/hw/repo
    ```
2.  运行 Bazel 构建命令编译测试程序：
    ```bash
    bazel build //tests/cocotb/tutorial:coralnpu_v2_program
    ```
3.  `coralnpu_v2_program.elf` 文件会在 bazel 输出目录中生成。
4.  将该 `coralnpu_v2_program.elf` 文件复制到本 UVM 测试台结构的 `bin/` 目录（或更新 `Makefile` 或运行命令中的 `TEST_ELF` 路径）。

## 目录结构

测试台遵循标准的 UVM 目录结构：

```
.
├── common/                  # Common components
│   ├── coralnpu_axi_master/ # Files related to the TB acting as AXI Master
│   │   ├── coralnpu_axi_master_if.sv
│   │   └── coralnpu_axi_master_agent_pkg.sv
│   ├── coralnpu_axi_slave/  # Files related to the TB acting as AXI Slave
│   │   ├── coralnpu_axi_slave_if.sv
│   │   └── coralnpu_axi_slave_agent_pkg.sv
│   ├── coralnpu_irq/        # Files related to the IRQ/Control interface
│   │   ├── coralnpu_irq_if.sv
│   │   └── coralnpu_irq_agent_pkg.sv
│   └── transaction_item/    # Transaction item definitions
│       └── transaction_item_pkg.sv
├── env/                     # UVM Environment definition
│   └── coralnpu_env_pkg.sv
├── tb/                      # Top-level testbench module
│   └── coralnpu_tb_top.sv
├── tests/                   # UVM Tests and Sequences
│   └── coralnpu_test_pkg.sv
├── Makefile                 # Makefile for compilation and simulation
├── coralnpu_dv.f            # File list for compilation
└── bin/                     # Directory for test binaries
    └── program.elf          # (Needs to be generated and copied here)
```

## 使用 Makefile 运行测试台

所提供的 `Makefile` 简化了编译和仿真流程。

**1. 编译仿真器可执行文件：**

* **命令：** `make compile`
* **动作：**
    * 创建必要的目录（`sim_work`、`logs`、`waves`）。
    * 从 Chisel 源生成 DUT 的 Verilog。
    * 构建 MPACT 协同仿真 C++ 库。
    * 基于 `coralnpu_dv.f`，使用 VCS 编译 DUT 和测试台的 SystemVerilog 文件。
    * 创建 `sim_work/simv` 可执行文件。
*   当修改属于 DUT 或测试台的 SystemVerilog（`.sv`）、Chisel（`.scala`）或 C++（`.cpp`）源文件时，用户应运行 `make compile`。
* **预期输出：**
    ```
    --- Checking MPACT-Sim Co-sim Library dependencies ---
    --- Checking RTL source dependencies ---
    --- Compiling with VCS ---
    Chronologic VCS simulator copyright 1991-202X
    Contains Synopsys proprietary information.
    Compiler version ...
    ... (VCS compilation messages) ...
    Top Level Modules:
            coralnpu_tb_top
    TimeScale is 1ns / 1ps
    --- Compilation Finished ---
    ```
    查看 `sim_work/logs/compile.log` 获取详细的消息和错误。

**2. 运行仿真：**

* **命令（默认测试）：** `make run`
    * 运行 Makefile 中定义的默认测试（`coralnpu_base_test`）。
    * 使用默认程序（`bin/program.elf`）。
    * 使用 `UVM_MEDIUM` 详尽级别（verbosity）。
* **命令（指定测试与二进制）：**
    ```bash
    make run UVM_TESTNAME=<your_specific_test> \
             TEST_ELF=/path/to/another.elf \
             UVM_VERBOSITY=UVM_HIGH
    ```
    * 覆盖默认的测试名、二进制路径和详尽级别。
* **动作：**
  * 从指定的 `TEST_ELF` 生成内存初始化文件（`.mem`）和运行时选项（`elf_run_opts.f`）（此步骤总会执行）。
  * 用指定的 UVM 运行时选项执行 *已编译* 的 `simv` 可执行文件。
  * 用户应在 `make compile` 成功完成之后，或仅当 `TEST_ELF` 文件改变而无需重新编译时，运行 `make run`。
* **预期输出：**
    ```
    --- Running Simulation ---
    Test:      coralnpu_base_test
    ELF File:  ./bin/program.elf
    Verbosity: UVM_MEDIUM
    Timeout:   20000 ns
    Plusargs:  +UVM_TESTNAME=coralnpu_base_test +UVM_VERBOSITY=UVM_MEDIUM \
               +TEST_TIMEOUT=20000 +TEST_ELF=./bin/program.elf
    Log File:  ./sim_work/logs/coralnpu_base_test.log
    Wave File: ./sim_work/waves/coralnpu_base_test.fsdb
    Chronologic VCS simulator copyright 1991-202X
    Contains Synopsys proprietary information.
    Simulator version ... ; Runtime version ...
    UVM_INFO @ 0: reporter [RNTST] Running test coralnpu_base_test...
    ... (UVM simulation messages based on verbosity) ...
    UVM_INFO ./tests/coralnpu_test_pkg.sv(LINE#) @ TIME: uvm_test_top \
        [coralnpu_base_test] Run phase finishing
    UVM_INFO ./tests/coralnpu_test_pkg.sv(LINE#) @ TIME: uvm_test_top \
        [coralnpu_base_test] Test ended on DUT halt.
    --- UVM Report Summary ---
    ...
    UVM_INFO ./tests/coralnpu_test_pkg.sv(241) @ TIME: uvm_test_top \
        [coralnpu_base_test] ** UVM TEST PASSED **
    --- Simulation Finished ---
    ```
    * 在仿真日志（`sim_work/logs/<testname>.log`）末尾查找 `** UVM TEST PASSED **` 或 `** UVM TEST FAILED **` 消息。
    * 如果启用，将生成一个波形文件（`sim_work/waves/<testname>.fsdb`）。

**3. 编译并运行（合并）：**

* **命令：** `make all`（或直接 `make`）
* **动作：** 该命令首先运行 `make compile` 以确保仿真器可执行文件是最新的，然后运行 `make run`。这是执行完整构建和运行的便捷方式。

**4. 清理：**

* **命令：** `make clean`
* **动作：** 删除 `sim_work` 目录和其他仿真生成的文件（`simv`、`csrc`、日志、波形等）。它还会清理 MPACT 库和生成的 RTL 的 Bazel 缓存。
* **预期输出：**
    ```
    --- Cleaning Simulation Files ---
    rm -rf sim_work simv* csrc* *.log* *.key *.vpd *.fsdb ucli.key DVEfiles/ \
           verdiLog/ novas.*
    --- Cleaning MPACT-Sim Bazel cache ---
    ... (Bazel clean messages) ...
    ```

本 README 应能帮助你开始为 `RvvCoreMiniVerificationAxi` DUT 编译和运行基本测试。
