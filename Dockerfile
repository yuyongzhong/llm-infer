FROM python:3.10-slim

# 设置工作目录
WORKDIR /workspace

# 设置 pip 的清华源
RUN mkdir -p /root/.pip && \
    echo "[global]\nindex-url = https://pypi.tuna.tsinghua.edu.cn/simple" > /root/.pip/pip.conf


# 安装 bash 和基础工具
RUN echo "deb http://mirrors.tuna.tsinghua.edu.cn/debian bullseye main contrib non-free" > /etc/apt/sources.list && \
    echo "deb http://mirrors.tuna.tsinghua.edu.cn/debian bullseye-updates main contrib non-free" >> /etc/apt/sources.list && \
    echo "deb http://mirrors.tuna.tsinghua.edu.cn/debian bullseye-backports main contrib non-free" >> /etc/apt/sources.list && \
    echo "deb http://mirrors.tuna.tsinghua.edu.cn/debian-security bullseye-security main contrib non-free" >> /etc/apt/sources.list
RUN apt-get update && apt-get install -y curl bash git




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
