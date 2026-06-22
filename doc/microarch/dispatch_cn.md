# CoralNPU 分发规则（Dispatch Rules）

我们希望在 CoralNPU 核中尽可能多地分发指令。下面描述了我们用来判断哪些指令可以被分发的一般规则。

## 按序（In-order）

CoralNPU 是一个按序核。如果地址 n 处的指令无法分发，那么 n+4 处的指令也不会被纳入分发考虑。

## 冒险处理（Hazard Handling）

CoralNPU 使用记分牌（scoreboarding）来跟踪指令间的依赖关系。这可防止 RAW 和 WAW 数据冒险。所有执行单元都在指令分发后的下一个周期从寄存器堆读取操作数。因此，WAR 冒险永远不会发生。

## 执行单元约束（Execution Unit Constraints）

用于处理指令的执行单元数量有限。虽然有足够的 Alu 和 Bru 单元服务于每个车道（lane），但 CoralNPU 只包含 1 个 Mlu。因此，我们将每周期的乘法指令数量限制为单条指令。类似地，非流水化的执行单元（即 Dvu）可能会施加反压（backpressure），以在其忙碌时阻止指令被分发。

目前内存被限制为每周期分发一条指令。

## 控制流（Control Flow）

出于保守考虑，CoralNPU 不会越过以下跳转指令进行分发：
`jal`、`jalr`、`ebreak`、`ecall`、`mret`、`wfi`。

## 特殊指令（Special Instructions）

那些会影响 PC/寄存器堆之外核状态的指令，被限制只能在第一个槽位（slot）执行。它们通常也被当作跳转控制流指令处理，因此不应在与这些指令相同的周期内分发任何其他指令。这些指令包括：`csrrw`、`csrrs`、`csrrc`、`ebreak`、`ecall`、`mret`、`fence`、`fenci` 和 `wfi`。
