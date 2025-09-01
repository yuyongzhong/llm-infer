FROM python:3.10-slim-bookworm

WORKDIR /workspace

RUN mkdir -p /root/.pip && \
    echo "[global]\nindex-url = https://pypi.tuna.tsinghua.edu.cn/simple" > /root/.pip/pip.conf

# 完全替换为阿里源，避免与基础镜像源冲突
RUN rm -f /etc/apt/sources.list.d/* && \
    echo "deb http://mirrors.aliyun.com/debian bookworm main contrib non-free non-free-firmware\n\
deb http://mirrors.aliyun.com/debian-security bookworm-security main contrib non-free non-free-firmware\n\
deb http://mirrors.aliyun.com/debian bookworm-updates main contrib non-free non-free-firmware" > /etc/apt/sources.list

# DNS 问题常导致卡死，确保 Docker DNS 配置了
# 然后再尝试更新和安装
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl bash git wget libgl1-mesa-glx libglib2.0-0 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 复制本地的yq二进制文件，避免网络下载
COPY depens/yq_linux_amd64 /usr/local/bin/yq
RUN chmod +x /usr/local/bin/yq



# 复制依赖并安装
COPY requirements.txt ./
RUN pip install --upgrade pip 

RUN pip install --no-deps -r requirements.txt


# # 设置 git 加速（可选）
# RUN git config --global url."https://hgithub.xyz".insteadOf "https://github.com"

# 仅复制必要代码目录，避免覆盖系统路径
COPY test ./test

# 默认保持 bash 运行
CMD ["bash", "-c", "tail -f /dev/null"]
