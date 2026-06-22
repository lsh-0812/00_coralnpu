# 在 Rocky Linux 中构建 coralnpu_v2 工具链

以下说明描述了如何为 coralnpu_v2 构建并导出工具链。

## 构建并运行 docker 镜像

```sh
$ docker build --no-cache -t toolchain_test -f toolchain_rockylinux_image.dockerfile .
```
以交互模式打开 toolchain_test 容器并挂载当前目录
```sh
$ docker run -v `pwd`:/toolchain/build_scripts -w /toolchain/build_scripts toolchain_test bash coralnpu_v2_toolchain_build.sh
```

输出的工具链产物将被导出到 rv32_out
