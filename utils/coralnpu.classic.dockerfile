FROM debian:bookworm
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
ENV PATH=/usr/lib/llvm-16/bin:$PATH
ARG _UID=1000
ARG _GID=1000
ARG _USERNAME=builder
ENV HOME=/home/builder

RUN set -eux; \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime; echo $TZ > /etc/timezone; \
    echo 'APT::Get::Assume-Yes "true";' > /etc/apt/apt.conf.d/90assumeyes; \
    echo 'Acquire::Retries "10";' > /etc/apt/apt.conf.d/80retries; \
    sed -i 's|deb.debian.org|mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list /etc/apt/sources.list.d/debian.sources 2>/dev/null || true; \
    apt-get update; \
    apt-get install -y -qq \
        apt-transport-https autoconf build-essential ca-certificates ccache \
        curl fuse3 gawk git gnupg libelf-dev libftdi1-dev libmpfr-dev \
        libusb-1.0-0-dev lsb-release openjdk-17-jdk-headless openjdk-17-jre-headless \
        python-is-python3 python3 python3-pip python3-setuptools python3-venv \
        srecord sudo tzdata unzip xxd zip flex bison \
        clang-16 lld-16 llvm-16; \
    update-ca-certificates; \
    echo "deb [trusted=yes] https://storage.googleapis.com/bazel-apt stable jdk1.8" > /etc/apt/sources.list.d/bazel.list; \
    apt-get update; \
    apt-get install -y -qq bazel-8.6.0; \
    ln -sf /usr/bin/bazel-8.6.0 /usr/bin/bazel; \
    groupadd -g $_GID $_USERNAME || true; \
    useradd -m -u $_UID -g $_GID -d $HOME -s /bin/bash $_USERNAME; \
    echo "$_USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$_USERNAME; \
    chown $_USERNAME:$_USERNAME $HOME; \
    ln -sf /usr/lib/x86_64-linux-gnu/libmpfr.so.6 /usr/lib/x86_64-linux-gnu/libmpfr.so.4

USER builder
WORKDIR /home/builder
