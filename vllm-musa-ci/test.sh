#!/bin/bash

# test.sh - VLLM 测试脚本
# 该脚本用于在容器内运行 VLLM 测试

set -e

# 获取环境变量
LOG_NAME=${LOG_NAME:-"test_$(date +%Y%m%d_%H%M%S)"}
HOME_PATH="/mnt/vllm/yuyongzhong"

# 日志目录
TEST_LOG_DIR="$HOME_PATH/llm-infer/vllm-musa-ci/logs/test-logs"
mkdir -p "$TEST_LOG_DIR"

echo "=== VLLM 测试脚本 ==="
echo "日志名称: $LOG_NAME"
echo "日志目录: $TEST_LOG_DIR"
echo "开始时间: $(date)"

# 进入测试目录
cd "$HOME_PATH/llm-infer/test"

echo "=== 运行 DeepSeek 精度测试 ==="
# 运行 DeepSeek 测试
nohup bash run_all.sh config-dsv2.yaml > "$TEST_LOG_DIR/deepseek-${LOG_NAME}.log" 2>&1 &
DEEPSEEK_TEST_PID=$!
echo "DeepSeek 测试已启动，PID: $DEEPSEEK_TEST_PID"

# 等待一段时间再启动下一个测试
sleep 60

echo "=== 运行 Qwen 精度测试 ==="
# 运行 Qwen 测试
nohup bash run_all.sh config-qwen2.yaml > "$TEST_LOG_DIR/qwen-${LOG_NAME}.log" 2>&1 &
QWEN_TEST_PID=$!
echo "Qwen 测试已启动，PID: $QWEN_TEST_PID"

# 启动测试监控脚本
echo "=== 启动测试监控 ==="
{
    while true; do
        echo "====== $(date) ======"
        echo "=== DeepSeek 测试状态 ==="
        if kill -0 $DEEPSEEK_TEST_PID 2>/dev/null; then
            echo "DeepSeek 测试运行中 (PID: $DEEPSEEK_TEST_PID)"
            tail -n 3 "$TEST_LOG_DIR/deepseek-${LOG_NAME}.log" 2>/dev/null || echo "暂无日志"
        else
            echo "DeepSeek 测试已完成"
        fi
        
        echo "=== Qwen 测试状态 ==="
        if kill -0 $QWEN_TEST_PID 2>/dev/null; then
            echo "Qwen 测试运行中 (PID: $QWEN_TEST_PID)"
            tail -n 3 "$TEST_LOG_DIR/qwen-${LOG_NAME}.log" 2>/dev/null || echo "暂无日志"
        else
            echo "Qwen 测试已完成"
        fi
        
        # 检查是否都完成了
        if ! kill -0 $DEEPSEEK_TEST_PID 2>/dev/null && ! kill -0 $QWEN_TEST_PID 2>/dev/null; then
            echo "所有测试已完成"
            break
        fi
        
        sleep 30
    done
} > "$TEST_LOG_DIR/monitor-${LOG_NAME}.log" 2>&1 &

MONITOR_PID=$!
echo "测试监控已启动，PID: $MONITOR_PID"

echo "=== 所有测试启动完成 ==="
echo "DeepSeek 测试 PID: $DEEPSEEK_TEST_PID"
echo "Qwen 测试 PID: $QWEN_TEST_PID"
echo "Monitor PID: $MONITOR_PID"
echo "完成时间: $(date)"

# 保存 PID 信息
echo "$DEEPSEEK_TEST_PID" > "$TEST_LOG_DIR/deepseek-test.pid"
echo "$QWEN_TEST_PID" > "$TEST_LOG_DIR/qwen-test.pid"
echo "$MONITOR_PID" > "$TEST_LOG_DIR/monitor.pid"

echo "测试启动完成，日志将写入 $TEST_LOG_DIR/"
echo "使用以下命令查看测试进度："
echo "  tail -f $TEST_LOG_DIR/deepseek-${LOG_NAME}.log"
echo "  tail -f $TEST_LOG_DIR/qwen-${LOG_NAME}.log"
echo "  tail -f $TEST_LOG_DIR/monitor-${LOG_NAME}.log"
