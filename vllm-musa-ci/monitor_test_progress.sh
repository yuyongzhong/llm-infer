#!/bin/bash

# 简单的测试监控脚本

LOG_NAME=${1:-$(date +%Y%m%d_%H%M%S)}

echo "🔍 开始监控测试进度..."
echo "📅 时间: $(date)"
echo "🏷️  日志名称: $LOG_NAME"
echo ""

while true; do
    echo "────────────────────────────────────────────────────────────────"
    echo "📊 监控时间: $(date '+%Y-%m-%d %H:%M:%S')"
    
    # 检查测试进程
    if docker exec vllm-test-0805 pgrep -f "bash run_all.sh" >/dev/null 2>&1; then
        echo "🟢 测试进程: 运行中"
        
        # 检查最新的评估日志
        LATEST_LOG=$(docker exec vllm-test-0805 find /mnt/vllm/yuyongzhong/llm-infer/test/outputs -name "eval_log.log" -type f -exec ls -t {} + | head -1)
        if [ -n "$LATEST_LOG" ]; then
            echo "📄 评估日志: $LATEST_LOG"
            echo "📝 最新进度:"
            docker exec vllm-test-0805 tail -3 "$LATEST_LOG" | sed 's/^/   /'
        fi
        
        # 检查钉钉监控线程
        if docker exec vllm-test-0805 pgrep -f "acc_log_monitor" >/dev/null 2>&1; then
            echo "📢 钉钉监控: 运行中"
        else
            echo "⚠️  钉钉监控: 未检测到"
        fi
        
    else
        echo "🔴 测试进程: 已停止"
        
        # 检查是否有完成的测试报告
        REPORTS=$(docker exec vllm-test-0805 find /mnt/vllm/yuyongzhong/llm-infer/test -name "*.json" -path "*/reports/*" -newer /tmp/test_start 2>/dev/null | wc -l)
        echo "📊 生成报告: $REPORTS 个"
        
        break
    fi
    
    echo ""
    sleep 30
done

echo "🎉 监控结束: $(date)"
