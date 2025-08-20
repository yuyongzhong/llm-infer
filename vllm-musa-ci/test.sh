#!/bin/bash

# test.sh - VLLM 测试脚本
# 该脚本用于在容器内运行 VLLM 测试

set -e

# 获取环境变量
LOG_NAME=${LOG_NAME:-"test_$(date +%Y%m%d_%H%M%S)"}
HOME_PATH="/mnt/vllm/yuyongzhong"
VERBOSE=${VERBOSE:-false}

# 调试输出函数
debug_echo() {
    if [ "$VERBOSE" = "true" ]; then
        echo "🐛 [DEBUG] $*"
    fi
}

# 日志目录
TEST_LOG_DIR="$HOME_PATH/llm-infer/vllm-musa-ci/logs/test-logs"
mkdir -p "$TEST_LOG_DIR"

debug_echo "VERBOSE模式已启用"
debug_echo "LOG_NAME=$LOG_NAME"
debug_echo "HOME_PATH=$HOME_PATH"
debug_echo "TEST_LOG_DIR=$TEST_LOG_DIR"

echo "╔════════════════════════════════════════════════════════════════════════════════╗"
echo "║                           🚀 VLLM 测试脚本启动                                ║"
echo "╠════════════════════════════════════════════════════════════════════════════════╣"
printf "║ 📝 日志名称: %-63s ║\n" "$LOG_NAME"
printf "║ 📁 日志目录: %-63s ║\n" "$TEST_LOG_DIR"
printf "║ 🕐 开始时间: %-63s ║\n" "$(date '+%Y-%m-%d %H:%M:%S')"
echo "╚════════════════════════════════════════════════════════════════════════════════╝"
echo ""

# 进入测试目录
cd "$HOME_PATH/llm-infer/test"
debug_echo "切换到测试目录: $(pwd)"

echo "🚀 [$(date '+%H:%M:%S')] 启动 DeepSeek 精度测试..."
debug_echo "即将执行命令: bash run_all.sh config-dsv2.yaml"

# 运行 DeepSeek 测试
nohup bash run_all.sh config-dsv2.yaml > "$TEST_LOG_DIR/deepseek-${LOG_NAME}.log" 2>&1 &
DEEPSEEK_TEST_PID=$!

# 等待一小段时间，检查进程是否立即失败
sleep 5
if ! kill -0 $DEEPSEEK_TEST_PID 2>/dev/null; then
    echo "❌ DeepSeek 测试进程已退出，检查日志："
    tail -20 "$TEST_LOG_DIR/deepseek-${LOG_NAME}.log"
    
    # 检查日志中是否有错误
    if grep -q "SyntaxError\|Traceback\|Exception\|ERROR\|Failed" "$TEST_LOG_DIR/deepseek-${LOG_NAME}.log" 2>/dev/null; then
        echo "🔍 发现错误，测试启动失败"
        exit 1
    fi
fi

echo "✅ DeepSeek 测试已启动 (PID: $DEEPSEEK_TEST_PID)"
echo "   📄 日志文件: $TEST_LOG_DIR/deepseek-${LOG_NAME}.log"
debug_echo "DeepSeek 测试进程PID: $DEEPSEEK_TEST_PID"
echo ""

# 等待一段时间再启动下一个测试
echo "⏳ 等待 60 秒后启动下一个测试..."
debug_echo "开始等待60秒..."
sleep 60
debug_echo "等待完成，继续下一个测试"

echo "🚀 [$(date '+%H:%M:%S')] 启动 Qwen 精度测试..."
debug_echo "即将执行命令: bash run_all.sh config-qwen2.yaml"

# 运行 Qwen 测试
nohup bash run_all.sh config-qwen2.yaml > "$TEST_LOG_DIR/qwen-${LOG_NAME}.log" 2>&1 &
QWEN_TEST_PID=$!

# 等待一小段时间，检查进程是否立即失败
sleep 5
if ! kill -0 $QWEN_TEST_PID 2>/dev/null; then
    echo "❌ Qwen 测试进程已退出，检查日志："
    tail -20 "$TEST_LOG_DIR/qwen-${LOG_NAME}.log"
    
    # 检查日志中是否有错误
    if grep -q "SyntaxError\|Traceback\|Exception\|ERROR\|Failed" "$TEST_LOG_DIR/qwen-${LOG_NAME}.log" 2>/dev/null; then
        echo "🔍 发现错误，测试启动失败"
        exit 1
    fi
fi

echo "✅ Qwen 测试已启动 (PID: $QWEN_TEST_PID)"
echo "   📄 日志文件: $TEST_LOG_DIR/qwen-${LOG_NAME}.log"
debug_echo "Qwen 测试进程PID: $QWEN_TEST_PID"
echo ""

# 启动测试监控脚本
echo "🔍 [$(date '+%H:%M:%S')] 启动测试监控..."
debug_echo "启动测试监控子进程"
{
    echo "🚀 测试监控启动于: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "📊 监控的测试:"
    echo "   • DeepSeek 测试 (PID: $DEEPSEEK_TEST_PID)"
    echo "   • Qwen 测试 (PID: $QWEN_TEST_PID)"
    [ "$VERBOSE" = "true" ] && echo "🐛 [DEBUG] VERBOSE模式启用，将显示详细信息"
    echo ""
    
    while true; do
        echo "╔════════════════════════════════════════════════════════════════════════════════╗"
        printf "║ 📅 监控时间: %-64s ║\n" "$(date '+%Y-%m-%d %H:%M:%S')"
        echo "╠════════════════════════════════════════════════════════════════════════════════╣"
        
        # DeepSeek 测试状态
        printf "║ 🤖 [DeepSeek] %-64s ║\n" ""
        if kill -0 $DEEPSEEK_TEST_PID 2>/dev/null; then
            printf "║ ├─ 状态: %-66s ║\n" "🟢 运行中 (PID: $DEEPSEEK_TEST_PID)"
            # 获取最新的日志行并格式化显示
            last_lines=$(tail -n 2 "$TEST_LOG_DIR/deepseek-${LOG_NAME}.log" 2>/dev/null | sed 's/^/║ ├─ /' | sed 's/$/                                                                     /' | cut -c1-80 | sed 's/$/║/')
            if [ -n "$last_lines" ]; then
                echo "$last_lines"
            else
                printf "║ ├─ 日志: %-66s ║\n" "暂无输出"
            fi
            # VERBOSE模式显示更多信息
            if [ "$VERBOSE" = "true" ]; then
                log_size=$(wc -l < "$TEST_LOG_DIR/deepseek-${LOG_NAME}.log" 2>/dev/null || echo "0")
                printf "║ ├─ 🐛 日志行数: %-58s ║\n" "$log_size"
                printf "║ ├─ 🐛 运行时长: %-58s ║\n" "$(ps -o etime= -p $DEEPSEEK_TEST_PID 2>/dev/null | tr -d ' ' || echo '未知')"
            fi
        else
            printf "║ ├─ 状态: %-66s ║\n" "✅ 已完成"
            # 检查是否有错误
            if grep -q "❌\|ERROR\|FAILED\|Exception" "$TEST_LOG_DIR/deepseek-${LOG_NAME}.log" 2>/dev/null; then
                printf "║ ├─ 结果: %-66s ║\n" "❌ 测试中有错误，请检查日志"
                if [ "$VERBOSE" = "true" ]; then
                    error_count=$(grep -c "❌\|ERROR\|FAILED\|Exception" "$TEST_LOG_DIR/deepseek-${LOG_NAME}.log" 2>/dev/null || echo "0")
                    printf "║ ├─ 🐛 错误数量: %-58s ║\n" "$error_count"
                fi
            else
                printf "║ ├─ 结果: %-66s ║\n" "✅ 测试完成"
            fi
        fi
        
        echo "║                                                                                ║"
        
        # Qwen 测试状态
        printf "║ 🤖 [Qwen] %-69s ║\n" ""
        if kill -0 $QWEN_TEST_PID 2>/dev/null; then
            printf "║ ├─ 状态: %-66s ║\n" "🟢 运行中 (PID: $QWEN_TEST_PID)"
            # 获取最新的日志行并格式化显示
            last_lines=$(tail -n 2 "$TEST_LOG_DIR/qwen-${LOG_NAME}.log" 2>/dev/null | sed 's/^/║ ├─ /' | sed 's/$/                                                                     /' | cut -c1-80 | sed 's/$/║/')
            if [ -n "$last_lines" ]; then
                echo "$last_lines"
            else
                printf "║ ├─ 日志: %-66s ║\n" "暂无输出"
            fi
            # VERBOSE模式显示更多信息
            if [ "$VERBOSE" = "true" ]; then
                log_size=$(wc -l < "$TEST_LOG_DIR/qwen-${LOG_NAME}.log" 2>/dev/null || echo "0")
                printf "║ ├─ 🐛 日志行数: %-58s ║\n" "$log_size"
                printf "║ ├─ 🐛 运行时长: %-58s ║\n" "$(ps -o etime= -p $QWEN_TEST_PID 2>/dev/null | tr -d ' ' || echo '未知')"
            fi
        else
            printf "║ ├─ 状态: %-66s ║\n" "✅ 已完成"
            # 检查是否有错误
            if grep -q "❌\|ERROR\|FAILED\|Exception" "$TEST_LOG_DIR/qwen-${LOG_NAME}.log" 2>/dev/null; then
                printf "║ ├─ 结果: %-66s ║\n" "❌ 测试中有错误，请检查日志"
                if [ "$VERBOSE" = "true" ]; then
                    error_count=$(grep -c "❌\|ERROR\|FAILED\|Exception" "$TEST_LOG_DIR/qwen-${LOG_NAME}.log" 2>/dev/null || echo "0")
                    printf "║ ├─ 🐛 错误数量: %-58s ║\n" "$error_count"
                fi
            else
                printf "║ ├─ 结果: %-66s ║\n" "✅ 测试完成"
            fi
        fi
        
        echo "╚════════════════════════════════════════════════════════════════════════════════╝"
        echo ""
        
        # 检查是否都完成了
        if ! kill -0 $DEEPSEEK_TEST_PID 2>/dev/null && ! kill -0 $QWEN_TEST_PID 2>/dev/null; then
            echo "🎉 所有测试已完成于: $(date '+%Y-%m-%d %H:%M:%S')"
            echo ""
            echo "📋 测试总结:"
            echo "├─ DeepSeek 日志: $TEST_LOG_DIR/deepseek-${LOG_NAME}.log"
            echo "└─ Qwen 日志: $TEST_LOG_DIR/qwen-${LOG_NAME}.log"
            echo ""
            echo "⏹️  监控结束，测试任务全部完成"
            break
        fi
        
        sleep 30
    done
    
    # 监控结束后的清理工作
    echo "🔚 测试监控已停止 - $(date '+%Y-%m-%d %H:%M:%S')"
} > "$TEST_LOG_DIR/monitor-${LOG_NAME}.log" 2>&1 &

MONITOR_PID=$!
echo "✅ 测试监控已启动 (PID: $MONITOR_PID)"
echo "   📄 监控日志: $TEST_LOG_DIR/monitor-${LOG_NAME}.log"
echo ""

echo "╔════════════════════════════════════════════════════════════════════════════════╗"
echo "║                           ✅ 所有测试启动完成                                 ║"
echo "╠════════════════════════════════════════════════════════════════════════════════╣"
printf "║ 🤖 DeepSeek 测试 PID: %-55s ║\n" "$DEEPSEEK_TEST_PID"
printf "║ 🤖 Qwen 测试 PID: %-59s ║\n" "$QWEN_TEST_PID"
printf "║ 🔍 Monitor PID: %-62s ║\n" "$MONITOR_PID"
printf "║ 🕐 完成时间: %-64s ║\n" "$(date '+%Y-%m-%d %H:%M:%S')"
echo "╚════════════════════════════════════════════════════════════════════════════════╝"
echo ""

# 保存 PID 信息
echo "$DEEPSEEK_TEST_PID" > "$TEST_LOG_DIR/deepseek-test.pid"
echo "$QWEN_TEST_PID" > "$TEST_LOG_DIR/qwen-test.pid"
echo "$MONITOR_PID" > "$TEST_LOG_DIR/monitor.pid"

echo "📋 测试启动完成！日志将写入: $TEST_LOG_DIR/"
echo ""
echo "📊 实时查看测试进度命令:"
echo "├─ DeepSeek 测试: tail -f $TEST_LOG_DIR/deepseek-${LOG_NAME}.log"
echo "├─ Qwen 测试:     tail -f $TEST_LOG_DIR/qwen-${LOG_NAME}.log"
echo "└─ 监控总览:       tail -f $TEST_LOG_DIR/monitor-${LOG_NAME}.log"

# 最终状态检查 - 确保关键进程仍在运行
debug_echo "执行最终状态检查..."
FINAL_STATUS=0

# 检查 DeepSeek 测试进程
if ! kill -0 $DEEPSEEK_TEST_PID 2>/dev/null; then
    echo "⚠️ 警告: DeepSeek 测试进程已提前结束"
    if grep -q "SyntaxError\|Traceback\|Exception\|ERROR" "$TEST_LOG_DIR/deepseek-${LOG_NAME}.log" 2>/dev/null; then
        echo "❌ DeepSeek 测试发现错误:"
        grep -A5 -B5 "SyntaxError\|Traceback\|Exception\|ERROR" "$TEST_LOG_DIR/deepseek-${LOG_NAME}.log" | tail -10
        FINAL_STATUS=1
    fi
fi

# 检查 Qwen 测试进程
if ! kill -0 $QWEN_TEST_PID 2>/dev/null; then
    echo "⚠️ 警告: Qwen 测试进程已提前结束"
    if grep -q "SyntaxError\|Traceback\|Exception\|ERROR" "$TEST_LOG_DIR/qwen-${LOG_NAME}.log" 2>/dev/null; then
        echo "❌ Qwen 测试发现错误:"
        grep -A5 -B5 "SyntaxError\|Traceback\|Exception\|ERROR" "$TEST_LOG_DIR/qwen-${LOG_NAME}.log" | tail -10
        FINAL_STATUS=1
    fi
fi

if [ $FINAL_STATUS -ne 0 ]; then
    echo ""
    echo "❌ 测试启动过程中发现错误，请检查日志文件"
    debug_echo "退出状态: $FINAL_STATUS"
    exit $FINAL_STATUS
fi

debug_echo "所有检查通过，脚本正常结束"
