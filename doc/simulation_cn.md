# 仿真

## VCS 支持

CoralNPU 支持使用 VCS 仿真器。要启用 VCS 支持，需要设置以下环境变量：

```
export VCS_HOME=${PATH_TO_YOUR_VCS_HOME}
export LM_LICENSE_FILE=${YOUR_LICENSE_FILE}
```

此外还应更新 `LD_LIBRARY_PATH` 和 `PATH`。

```
export LD_LIBRARY_PATH="${VCS_HOME}"/linux64/lib
export PATH=$PATH:${VCS_HOME}/bin/
```

VCS 仿真可以用 `vcs_testbench_test` 规则来定义。在 BUILD 文件中的用法示例如下：

```
load("//rules:vcs.bzl", "vcs_testbench_test")

vcs_testbench_test(
    name = "foobar_tb",
    srcs = ["Foobar_tb.sv"],
    module = "Foobar_tb",
    deps = ":foobar",
)
```

默认情况下，我们在 bazel 中禁用 VCS。调用
`bazel {build,run,test} --config=vcs` 即可启用 VCS 支持。

### 故障排查

#### CCACHE 与 VCS（只读文件系统错误）
如果在 VCS 仿真过程中遇到类似 `ccache: error: Failed to create temporary file ... Read-only file system` 的错误，是因为 `ccache` 试图从 Bazel 沙箱内部向你的主目录写入。

**修复方法：** 在命令前加上 `CCACHE_DISABLE=1`：
```bash
bazel --action_env=CCACHE_DISABLE=1 test --config=vcs //...
```
