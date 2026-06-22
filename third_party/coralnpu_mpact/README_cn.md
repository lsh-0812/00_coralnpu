# coralnpu_mpact Workspace 覆盖（Override）

本目录包含一些变通（workaround）文件，用于覆盖外部仓库 `@coralnpu_mpact` 的 workspace 配置。

## 为何存在

在传统的 Bazel `WORKSPACE` 体系中，外部仓库的传递依赖（transitive dependencies）不会被自动解析。通常它们必须满足以下之一：
1. 在根项目的 `WORKSPACE` 中声明（或通过宏加载），从而污染根项目的依赖列表。
2. 如果外部仓库自身有一个非空的 `WORKSPACE` 文件，则由该外部仓库自己解析。然而，被拉取的仓库（尤其是那些设计为以子模块或通过 copybara 方式使用的仓库）在被拉取的上下文中，其 `WORKSPACE` 文件可能为空或缺失。

`@coralnpu_mpact` 拥有一组复杂的传递依赖（例如 `@com_google_mpact-riscv`、`@rules_python` 等）。为避免用这些依赖污染我们主 `WORKSPACE`（或 `repos.bzl`），我们利用 `http_archive` 中的 Bazel `workspace_file` 属性（在 `rules/repos.bzl` 中），将本目录中的自定义 `WORKSPACE` 模板（`third_party/coralnpu_mpact/WORKSPACE`）注入到被拉取的仓库中。

这使得 `@coralnpu_mpact` 能够在其自身的外部 workspace 上下文中，密闭地（hermetically）解析和编译它自己的依赖。

## Bzlmod 迁移与移除计划

Bzlmod（Bazel 的模块化依赖系统）从原生层面解决了传递依赖问题。在 Bzlmod 下：
1. `@coralnpu_mpact` 将被定义为一个 Bazel 模块，拥有自己的 `MODULE.bazel` 文件来指定其依赖（`mpact-riscv`、`rules_python` 等）。
2. 根项目只需将 `coralnpu_mpact` 作为一个模块来依赖。
3. Bazel 将根据 `coralnpu_mpact` 的 `MODULE.bazel` 自动解析传递依赖，无需任何覆盖或在根层面声明传递依赖。

### 移除步骤：
1. 在项目中启用 Bzlmod（通过 `.bazelrc` 或命令行标志）。
2. 将 `@coralnpu_mpact` 转换为一个 Bazel 模块（在其仓库中添加 `MODULE.bazel`）。
3. 更新我们的 `MODULE.bazel` 以依赖 `coralnpu_mpact`。
4. 完全移除 `third_party/coralnpu_mpact/` 目录，因为不再需要这个覆盖。
5. 移除 `rules/repos.bzl` 中指向本目录的 `workspace_file` 覆盖。
