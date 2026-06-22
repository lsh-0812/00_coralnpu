
#!/bin/bash

# 用法:先 cd 到仓库根目录,再运行 bash  ./coralnpu-enter.sh

P=http://127.0.0.1:10080

sudo docker run -it --rm --network=host \
  -e HTTP_PROXY=$P -e HTTPS_PROXY=$P -e ALL_PROXY=$P \
  -e http_proxy=$P -e https_proxy=$P -e all_proxy=$P \
  -e NO_PROXY=localhost,127.0.0.1 -e no_proxy=localhost,127.0.0.1 \
  -v "$PWD":/home/builder/00_coralnpu \
  -v "$HOME/.coralnpu-cache":/home/builder/.cache \
  -w /home/builder/00_coralnpu \
  coralnpu bash

