#!/bin/bash

# startup.sh - VLLM 服务启动脚本
# 该脚本用于在容器内启动 VLLM 服务

set -e

# 获取环境变量
LOG_NAME=${LOG_NAME:-"default_$(date +%Y%m%d_%H%M%S)"}
HOME_PATH="/mnt/vllm/yuyongzhong"
VERBOSE=${VERBOSE:-false}

# 调试输出函数
debug_echo() {
    if [ "$VERBOSE" = "true" ]; then
        echo "🐛 [DEBUG] $*"
    fi
}

# 日志目录
SERVICE_LOG_DIR="$HOME_PATH/llm-infer/vllm-musa-ci/logs/service-logs"
mkdir -p "$SERVICE_LOG_DIR"

debug_echo "VERBOSE模式已启用"
debug_echo "LOG_NAME=$LOG_NAME"
debug_echo "HOME_PATH=$HOME_PATH"
debug_echo "SERVICE_LOG_DIR=$SERVICE_LOG_DIR"

echo "╔════════════════════════════════════════════════════════════════════════════════╗"
echo "║                           🚀 VLLM 服务启动脚本                               ║"
echo "╠════════════════════════════════════════════════════════════════════════════════╣"
printf "║ 📝 日志名称: %-63s ║\n" "$LOG_NAME"
printf "║ 📁 日志目录: %-63s ║\n" "$SERVICE_LOG_DIR"
printf "║ 🕐 开始时间: %-63s ║\n" "$(date '+%Y-%m-%d %H:%M:%S')"
echo "╚════════════════════════════════════════════════════════════════════════════════╝"
echo ""

# 启动 DeepSeek 服务
echo "🤖 [$(date '+%H:%M:%S')] 启动 DeepSeek 服务 (端口8000, GPU 0,1)..."
cd "$HOME_PATH/llm-infer/vllm-server"

# DeepSeek 服务 (端口 8000, GPU 0,1)
nohup bash run.sh \
    --tp 2 \
    --pp 1 \
    --model-path /mnt/models/DeepSeek-V2-Lite \
    --model-name deepseek \
    --port 8000 \
    --max-model-len 12000 \
    --gpu-memory-utilization 0.7 \
    --block-size 16 \
    --enable-chunked-prefill true \
    --max-num-batched-tokens 4096 \
    --musa-visible-devices '0,1' \
    > "$SERVICE_LOG_DIR/deepseek-${LOG_NAME}.log" 2>&1 &

DEEPSEEK_PID=$!
echo "✅ DeepSeek 服务已启动 (PID: $DEEPSEEK_PID)"
echo "   📄 日志文件: $SERVICE_LOG_DIR/deepseek-${LOG_NAME}.log"
echo "   🔌 监听端口: 8000"
echo "   🎯 使用GPU: 0,1"
echo ""

# 等待服务启动
echo "⏳ 等待 DeepSeek 服务启动..."
sleep 30

# 启动 Qwen 服务 (端口 8001, GPU 2,3,4,5)
echo "🤖 [$(date '+%H:%M:%S')] 启动 Qwen 服务 (端口8001, GPU 2,3,4,5)..."
nohup bash run.sh \
    --tp 4 \
    --pp 1 \
    --model-path /mnt/models/Qwen2.5-7B-Instruct \
    --model-name qwen \
    --port 8001 \
    --max-model-len 8000 \
    --gpu-memory-utilization 0.8 \
    --block-size 32 \
    --max-num-seqs 30 \
    --enable-chunked-prefill true \
    --max-num-batched-tokens 8192 \
    --enable-prefix-caching true \
    --musa-visible-devices '2,3,4,5' \
    --compilation-config '{"cudagraph_capture_sizes": [1,2,3,4,5,6,7,8,10,12,14,16,18,20,24,28,30], "simple_cuda_graph": true}' \
    > "$SERVICE_LOG_DIR/qwen-${LOG_NAME}.log" 2>&1 &

QWEN_PID=$!
echo "✅ Qwen 服务已启动 (PID: $QWEN_PID)"
echo "   📄 日志文件: $SERVICE_LOG_DIR/qwen-${LOG_NAME}.log"
echo "   🔌 监听端口: 8001"
echo "   🎯 使用GPU: 2,3,4,5"
echo ""

# 等待服务启动
echo "⏳ 等待 Qwen 服务启动..."
sleep 30

# 启动监控脚本
echo "🔍 [$(date '+%H:%M:%S')] 启动服务监控..."
{
    echo "🚀 服务监控启动于: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "📊 监控的服务:"
    echo "   • DeepSeek 服务 (PID: $DEEPSEEK_PID) - 端口8000 - GPU 0,1"
    echo "   • Qwen 服务 (PID: $QWEN_PID) - 端口8001 - GPU 2,3,4,5"
    echo ""
    
    while true; do
        echo "╔════════════════════════════════════════════════════════════════════════════════╗"
        printf "║ 📅 监控时间: %-64s ║\n" "$(date '+%Y-%m-%d %H:%M:%S')"
        echo "╠════════════════════════════════════════════════════════════════════════════════╣"
        
        # DeepSeek 服务状态
        printf "║ 🤖 [DeepSeek] 端口8000 - GPU 0,1 %-42s ║\n" ""
        if kill -0 $DEEPSEEK_PID 2>/dev/null; then
            printf "║ ├─ 状态: %-66s ║\n" "🟢 运行中 (PID: $DEEPSEEK_PID)"
            # 获取端口状态
            if netstat -tlnp 2>/dev/null | grep -q ":8000.*LISTEN"; then
                printf "║ ├─ 端口: %-66s ║\n" "✅ 8000端口正常监听"
            else
                printf "║ ├─ 端口: %-66s ║\n" "⚠️  8000端口未监听"
            fi
            # 显示最新日志（去掉时间戳等冗余信息）
            last_lines=$(tail -n 3 "$SERVICE_LOG_DIR/deepseek-${LOG_NAME}.log" 2>/dev/null | grep -v "^$" | tail -2 | sed 's/^.*INFO: //' | sed 's/^.*] //' | head -2)
            if [ -n "$last_lines" ]; then
                echo "$last_lines" | while IFS= read -r line; do
                    printf "║ ├─ 日志: %-66.60s ║\n" "$line"
                done
            else
                printf "║ ├─ 日志: %-66s ║\n" "暂无输出"
            fi
            # 检查错误
            recent_errors=$(tail -n 20 "$SERVICE_LOG_DIR/deepseek-${LOG_NAME}.log" 2>/dev/null | grep -E "(ERROR|Exception|Failed|ValueError|RuntimeError)" | tail -1)
            if [ -n "$recent_errors" ]; then
                printf "║ ├─ 警告: %-66.60s ║\n" "❌ 检测到错误，请检查日志"
            fi
        else
            printf "║ ├─ 状态: %-66s ║\n" "❌ 进程已停止"
            printf "║ ├─ 建议: %-66s ║\n" "请检查日志并重启服务"
        fi
        
        echo "║                                                                                ║"
        
        # Qwen 服务状态
        printf "║ 🤖 [Qwen] 端口8001 - GPU 2,3,4,5 %-45s ║\n" ""
        if kill -0 $QWEN_PID 2>/dev/null; then
            printf "║ ├─ 状态: %-66s ║\n" "🟢 运行中 (PID: $QWEN_PID)"
            # 获取端口状态
            if netstat -tlnp 2>/dev/null | grep -q ":8001.*LISTEN"; then
                printf "║ ├─ 端口: %-66s ║\n" "✅ 8001端口正常监听"
            else
                printf "║ ├─ 端口: %-66s ║\n" "⚠️  8001端口未监听"
            fi
            # 显示最新日志（去掉时间戳等冗余信息）
            last_lines=$(tail -n 3 "$SERVICE_LOG_DIR/qwen-${LOG_NAME}.log" 2>/dev/null | grep -v "^$" | tail -2 | sed 's/^.*INFO: //' | sed 's/^.*] //' | head -2)
            if [ -n "$last_lines" ]; then
                echo "$last_lines" | while IFS= read -r line; do
                    printf "║ ├─ 日志: %-66.60s ║\n" "$line"
                done
            else
                printf "║ ├─ 日志: %-66s ║\n" "暂无输出"
            fi
            # 检查错误
            recent_errors=$(tail -n 20 "$SERVICE_LOG_DIR/qwen-${LOG_NAME}.log" 2>/dev/null | grep -E "(ERROR|Exception|Failed|ValueError|RuntimeError)" | tail -1)
            if [ -n "$recent_errors" ]; then
                printf "║ ├─ 警告: %-66.60s ║\n" "❌ 检测到错误，请检查日志"
            fi
        else
            printf "║ ├─ 状态: %-66s ║\n" "❌ 进程已停止"
            printf "║ ├─ 建议: %-66s ║\n" "请检查日志并重启服务"
        fi
        
        echo "║                                                                                ║"
        
        # 服务总体状态
        printf "║ 📊 [总体状态] %-61s ║\n" ""
        running_services=$(ps aux | grep -v grep | grep python | grep -E "800[01]" | wc -l)
        printf "║ ├─ 服务数量: %-63s ║\n" "运行中 $running_services/2 个服务"
        
        # GPU 使用情况
        if command -v musa-smi >/dev/null 2>&1; then
            gpu_info=$(musa-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -6 | tr '\n' ',' | sed 's/,$//')
            if [ -n "$gpu_info" ]; then
                printf "║ ├─ GPU使用率: %-60s ║\n" "$gpu_info%"
            fi
        fi
        
        echo "╚════════════════════════════════════════════════════════════════════════════════╝"
        echo ""
        
        sleep 60
    done
} > "$SERVICE_LOG_DIR/monitor-${LOG_NAME}.log" 2>&1 &

MONITOR_PID=$!
echo "✅ 服务监控已启动 (PID: $MONITOR_PID)"
echo "   📄 监控日志: $SERVICE_LOG_DIR/monitor-${LOG_NAME}.log"
echo ""

echo "╔════════════════════════════════════════════════════════════════════════════════╗"
echo "║                           ✅ 所有服务启动完成                                 ║"
echo "╠════════════════════════════════════════════════════════════════════════════════╣"
printf "║ 🤖 DeepSeek 服务: %-59s ║\n" "PID $DEEPSEEK_PID (端口8000, GPU 0,1)"
printf "║ 🤖 Qwen 服务: %-63s ║\n" "PID $QWEN_PID (端口8001, GPU 2,3,4,5)"
printf "║ 🔍 Monitor 服务: %-61s ║\n" "PID $MONITOR_PID"
printf "║ 🕐 完成时间: %-64s ║\n" "$(date '+%Y-%m-%d %H:%M:%S')"
echo "╚════════════════════════════════════════════════════════════════════════════════╝"
echo ""

# 保存 PID 信息
echo "$DEEPSEEK_PID" > "$SERVICE_LOG_DIR/deepseek.pid"
echo "$QWEN_PID" > "$SERVICE_LOG_DIR/qwen.pid"
echo "$MONITOR_PID" > "$SERVICE_LOG_DIR/monitor.pid"

echo "📋 服务启动完成！日志将写入: $SERVICE_LOG_DIR/"
echo ""
echo "📊 实时查看服务状态命令:"
echo "├─ DeepSeek 服务: tail -f $SERVICE_LOG_DIR/deepseek-${LOG_NAME}.log"
echo "├─ Qwen 服务:     tail -f $SERVICE_LOG_DIR/qwen-${LOG_NAME}.log"
echo "└─ 监控总览:       tail -f $SERVICE_LOG_DIR/monitor-${LOG_NAME}.log"
echo ""
echo "🌐 服务测试命令:"
echo "├─ DeepSeek API: curl -X POST http://localhost:8000/v1/chat/completions \\"
echo "│                     -H \"Content-Type: application/json\" \\"
echo "│                     -d '{\"model\":\"deepseek\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}]}'"
echo "└─ Qwen API:     curl -X POST http://localhost:8001/v1/chat/completions \\"
echo "                      -H \"Content-Type: application/json\" \\"
echo "                      -d '{\"model\":\"qwen\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}]}'"
