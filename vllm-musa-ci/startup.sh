#!/bin/bash

# startup.sh - VLLM 服务启动脚本
# 该脚本用于在容器内启动 VLLM 服务

set -e

# 获取环境变量
LOG_NAME=${LOG_NAME:-"default_$(date +%Y%m%d_%H%M%S)"}
HOME_PATH="/mnt/vllm/yuyongzhong"

# 日志目录
SERVICE_LOG_DIR="$HOME_PATH/llm-infer/vllm-musa-ci/logs/service-logs"
mkdir -p "$SERVICE_LOG_DIR"

echo "=== VLLM 服务启动脚本 ==="
echo "日志名称: $LOG_NAME"
echo "日志目录: $SERVICE_LOG_DIR"
echo "开始时间: $(date)"

# 启动 DeepSeek 服务
echo "=== 启动 DeepSeek 服务 ==="
cd "$HOME_PATH/llm-infer/vllm-server"

# DeepSeek 服务 (端口 8000)
nohup bash run.sh \
    --tp 2 \
    --pp 1 \
    --model-path /mnt/models/DeepSeek-V2-Lite \
    --model-name deepseek \
    --port 8000 \
    --max-model-len 12000 \
    --gpu-memory-utilization 0.7 \
    --block-size 16 \
    > "$SERVICE_LOG_DIR/deepseek-${LOG_NAME}.log" 2>&1 &

DEEPSEEK_PID=$!
echo "DeepSeek 服务已启动，PID: $DEEPSEEK_PID"

# 等待服务启动
echo "等待 DeepSeek 服务启动..."
sleep 30

# 启动 Qwen 服务 (端口 8001)
echo "=== 启动 Qwen 服务 ==="
nohup bash run.sh \
    --tp 4 \
    --pp 1 \
    --model-path /mnt/models/Qwen2.5-7B-Instruct \
    --model-name deepseek \
    --port 8001 \
    --max-model-len 8000 \
    --gpu-memory-utilization 0.8 \
    --block-size 32 \
    > "$SERVICE_LOG_DIR/qwen-${LOG_NAME}.log" 2>&1 &

QWEN_PID=$!
echo "Qwen 服务已启动，PID: $QWEN_PID"

# 等待服务启动
echo "等待 Qwen 服务启动..."
sleep 30

# 启动监控脚本
echo "=== 启动服务监控 ==="
{
    while true; do
        echo "====== DeepSeek log head ======"
        head -n 5 "$SERVICE_LOG_DIR/deepseek-${LOG_NAME}.log" 2>/dev/null || echo "无日志"
        echo "====== Qwen log head ======"
        head -n 5 "$SERVICE_LOG_DIR/qwen-${LOG_NAME}.log" 2>/dev/null || echo "无日志"
        sleep 60
    done
} > "$SERVICE_LOG_DIR/monitor-${LOG_NAME}.log" 2>&1 &

MONITOR_PID=$!
echo "监控脚本已启动，PID: $MONITOR_PID"

echo "=== 所有服务启动完成 ==="
echo "DeepSeek PID: $DEEPSEEK_PID"
echo "Qwen PID: $QWEN_PID"
echo "Monitor PID: $MONITOR_PID"
echo "完成时间: $(date)"

# 保存 PID 信息
echo "$DEEPSEEK_PID" > "$SERVICE_LOG_DIR/deepseek.pid"
echo "$QWEN_PID" > "$SERVICE_LOG_DIR/qwen.pid"
echo "$MONITOR_PID" > "$SERVICE_LOG_DIR/monitor.pid"

echo "服务启动完成，日志将写入 $SERVICE_LOG_DIR/"
