# CoralNPU 微架构

![image](../images/microarch.png)

## 流水线

CoralNPU 基础处理器是一条按序（in-order）的三级流水线，每周期最多可分发 4 条指令。各指令阶段如下：

* **取指（Instruction fetch）：** 指令从内存取出，送入指令缓冲区。
* **译码/分发（Decode/Dispatch）：** 对指令缓冲区中前 4 条指令进行译码。互锁（interlock）与记分牌（scoreboard）逻辑决定本周期可以分发其中哪些指令。指令被转发到各自的执行单元。
* **执行/写回（Execute/Writeback）：** 已分发指令的执行单元从寄存器堆读取操作数并进行计算。结果也可以在同一周期写回寄存器堆。

某些执行单元的执行可能需要多个周期。各类指令的延迟见下表：

| 指令类型 | 延迟（周期） | 描述                   |
| ---------------- | ---------------- | ---------------------- |
| Alu              | 1                | 加、减、异或……         |
| Csr              | 1                | CSR 指令               |
| Bru              | 1                | bge、jal、ebreak……     |
| Mlu              | 2                | mul、mulh……            |
| Dvu              | 可变             | div、rem……             |
| Lsu              | 2+               | lw、sw……               |
