#!/bin/bash

# 测试错误处理的脚本

LOG_NAME="error_test_$(date +%Y%m%d_%H%M%S)"
TEST_LOG_DIR="/mnt/vllm/yuyongzhong/llm-infer/vllm-musa-ci/logs/test-logs"
VERBOSE=true

# 调试输出函数
debug_echo() {
    if [ "$VERBOSE" = "true" ]; then
        echo "🐛 [DEBUG] $*"
    fi
}

echo "🔬 开始错误处理测试..."
debug_echo "创建故意失败的测试"

# 创建一个故意失败的脚本
cat > /tmp/failing_script.sh << 'EOF'
#!/bin/bash
echo "脚本开始运行..."
sleep 2
echo "SyntaxError: 故意制造的语法错误"
sleep 1
echo "Traceback (most recent call last):"
echo "  File test.py, line 1"
echo "    invalid syntax"
exit 1
EOF

chmod +x /tmp/failing_script.sh

# 模拟测试启动流程
echo "🚀 [$(date '+%H:%M:%S')] 启动错误测试..."
debug_echo "即将执行故意失败的命令"

# 运行故意失败的测试
nohup bash /tmp/failing_script.sh > "$TEST_LOG_DIR/error-${LOG_NAME}.log" 2>&1 &
TEST_PID=$!

# 等待一小段时间，检查进程是否立即失败
sleep 3
if ! kill -0 $TEST_PID 2>/dev/null; then
    echo "❌ 测试启动失败，检查日志："
    tail -10 "$TEST_LOG_DIR/error-${LOG_NAME}.log"
    
    # 检查是否有错误
    if grep -q "SyntaxError\|Traceback\|Exception\|ERROR" "$TEST_LOG_DIR/error-${LOG_NAME}.log" 2>/dev/null; then
        echo "🔍 发现错误信息:"
        grep -A5 -B5 "SyntaxError\|Traceback\|Exception\|ERROR" "$TEST_LOG_DIR/error-${LOG_NAME}.log"
        echo ""
        echo "❌ 错误处理机制工作正常！"
        exit 1
    fi
else
    echo "⚠️ 进程仍在运行，等待完成..."
    wait $TEST_PID
    EXIT_CODE=$?
    echo "进程退出，退出代码: $EXIT_CODE"
fi

# 清理
rm -f /tmp/failing_script.sh
echo "🧹 清理完成"
