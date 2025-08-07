FROM python:3.10-slim

WORKDIR /workspace

RUN mkdir -p /root/.pip && \
    echo "[global]\nindex-url = https://pypi.tuna.tsinghua.edu.cn/simple" > /root/.pip/pip.conf

# 使用阿里源替换 Debian 的源
RUN echo "deb http://mirrors.aliyun.com/debian bullseye main contrib non-free\n\
deb http://mirrors.aliyun.com/debian-security bullseye-security main contrib non-free\n\
deb http://mirrors.aliyun.com/debian bullseye-updates main contrib non-free" > /etc/apt/sources.list

# DNS 问题常导致卡死，确保 Docker DNS 配置了
# 然后再尝试更新和安装
RUN apt-get update && \
    apt-get install -y curl bash git  wget && \
    wget -O /usr/local/bin/yq 'https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64' && \
    chmod +x /usr/local/bin/yq && \
    rm -rf /var/lib/apt/lists/*



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
