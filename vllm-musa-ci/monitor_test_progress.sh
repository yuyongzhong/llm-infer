#!/bin/bash

# 简单的测试监控脚本
# 用法: monitor_test_progress.sh [容器名称] [日志名称]

CONTAINER_NAME=${1:-"vllm-test-0805"}  # 第一个参数是容器名称，默认为vllm-test-0805兼容性
LOG_NAME=${2:-$(date +%Y%m%d_%H%M%S)}   # 第二个参数是日志名称

# 如果第一个参数看起来像日志名称（包含数字和下划线），则调整参数
if [[ "$1" =~ ^[0-9_]+$ ]]; then
    LOG_NAME="$1"
    CONTAINER_NAME="vllm-test-0805"
fi

echo "🔍 开始监控测试进度..."
echo "📅 时间: $(date)"
echo "🐳 容器名称: $CONTAINER_NAME"
echo "🏷️  日志名称: $LOG_NAME"
echo ""

while true; do
    echo "────────────────────────────────────────────────────────────────"
    echo "📊 监控时间: $(date '+%Y-%m-%d %H:%M:%S')"
    
    # 检查测试进程
    if docker exec $CONTAINER_NAME pgrep -f "bash run_all.sh" >/dev/null 2>&1; then
        echo "🟢 测试进程: 运行中"
        
        # 检查最新的评估日志
        LATEST_LOG=$(docker exec $CONTAINER_NAME find /mnt/vllm/yuyongzhong/llm-infer/test/outputs -name "eval_log.log" -type f -exec ls -t {} + | head -1)
        if [ -n "$LATEST_LOG" ]; then
            echo "📄 评估日志: $LATEST_LOG"
            echo "📝 最新进度:"
            docker exec $CONTAINER_NAME tail -3 "$LATEST_LOG" | sed 's/^/   /'
        fi
        
        # 检查钉钉监控线程
        if docker exec $CONTAINER_NAME pgrep -f "acc_log_monitor" >/dev/null 2>&1; then
            echo "📢 钉钉监控: 运行中"
        else
            echo "⚠️  钉钉监控: 未检测到"
        fi
        
    else
        echo "🔴 测试进程: 已停止"
        
        # 检查是否有完成的测试报告
        REPORTS=$(docker exec $CONTAINER_NAME find /mnt/vllm/yuyongzhong/llm-infer/test -name "*.json" -path "*/reports/*" -newer /tmp/test_start 2>/dev/null | wc -l)
        echo "📊 生成报告: $REPORTS 个"
        
        break
    fi
    
    echo ""
    sleep 30
done

echo "🎉 监控结束: $(date)"
