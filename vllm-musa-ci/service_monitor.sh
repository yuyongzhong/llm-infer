#!/bin/bash

# service_monitor.sh - VLLM服务监控和自动重启脚本
# 解决8001端口频繁失效问题

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_PATH="/mnt/vllm/yuyongzhong"
SERVICE_LOG_DIR="$HOME_PATH/llm-infer/vllm-musa-ci/logs/service-logs"

# 服务配置
DEEPSEEK_PORT=8000
QWEN_PORT=8001
CHECK_INTERVAL=60  # 检查间隔(秒)
MAX_RETRIES=3      # 最大重试次数

# 日志函数
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ℹ️  $*"
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $*"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $*"
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $*"
}

# 检查服务健康状态
check_service_health() {
    local port=$1
    local service_name=$2
    
    # 检查端口监听
    if ! netstat -tln | grep -q ":${port} "; then
        log_error "${service_name} 端口 ${port} 未监听"
        return 1
    fi
    
    # 检查API响应
    if ! curl -s --max-time 10 "http://127.0.0.1:${port}/v1/models" >/dev/null; then
        log_error "${service_name} API 无响应 (端口 ${port})"
        return 1
    fi
    
    return 0
}

# 重启Qwen服务
restart_qwen_service() {
    log_warn "准备重启 Qwen 服务..."
    
    # 杀死现有Qwen进程
    pkill -f "qwen.*8001" || true
    sleep 5
    
    # 清理资源
    log_info "清理GPU资源..."
    
    # 重新启动Qwen服务(使用优化配置)
    log_info "启动 Qwen 服务(优化配置)..."
    cd "$HOME_PATH/llm-infer/vllm-server"
    
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    nohup bash run.sh \
        --tp 2 \
        --pp 1 \
        --model-path /mnt/models/Qwen2.5-7B-Instruct \
        --model-name qwen \
        --port 8001 \
        --max-model-len 4000 \
        --gpu-memory-utilization 0.5 \
        --block-size 32 \
        --max-num-seqs 20 \
        --enable-chunked-prefill true \
        --max-num-batched-tokens 4096 \
        --enable-prefix-caching true \
        --musa-visible-devices '2,3' \
        > "$SERVICE_LOG_DIR/qwen-restart-${timestamp}.log" 2>&1 &
    
    local qwen_pid=$!
    log_info "Qwen 服务重启中 (PID: $qwen_pid)"
    
    # 等待服务启动
    log_info "等待 Qwen 服务启动..."
    sleep 60
    
    # 验证重启结果
    if check_service_health $QWEN_PORT "Qwen"; then
        log_success "Qwen 服务重启成功！"
        return 0
    else
        log_error "Qwen 服务重启失败"
        return 1
    fi
}

# 主监控循环
main_monitor() {
    log_info "🔍 VLLM 服务监控启动"
    log_info "检查间隔: ${CHECK_INTERVAL}秒"
    log_info "监控端口: DeepSeek(${DEEPSEEK_PORT}), Qwen(${QWEN_PORT})"
    
    local qwen_retry_count=0
    
    while true; do
        log_info "执行服务健康检查..."
        
        # 检查DeepSeek服务
        if check_service_health $DEEPSEEK_PORT "DeepSeek"; then
            log_success "DeepSeek 服务正常"
        else
            log_warn "DeepSeek 服务异常，但不自动重启(需手动处理)"
        fi
        
        # 检查Qwen服务
        if check_service_health $QWEN_PORT "Qwen"; then
            log_success "Qwen 服务正常"
            qwen_retry_count=0  # 重置重试计数
        else
            log_error "Qwen 服务异常！"
            
            if [ $qwen_retry_count -lt $MAX_RETRIES ]; then
                qwen_retry_count=$((qwen_retry_count + 1))
                log_warn "尝试第 ${qwen_retry_count}/${MAX_RETRIES} 次重启 Qwen 服务"
                
                if restart_qwen_service; then
                    qwen_retry_count=0
                else
                    log_error "第 ${qwen_retry_count} 次重启失败"
                fi
            else
                log_error "Qwen 服务重启达到最大次数(${MAX_RETRIES})，停止自动重启"
                log_error "请手动检查以下问题："
                log_error "1. GPU内存是否充足"
                log_error "2. 模型文件是否完整"
                log_error "3. 端口是否被占用"
                log_error "4. 查看日志: $SERVICE_LOG_DIR/qwen-*.log"
                break
            fi
        fi
        
        log_info "等待 ${CHECK_INTERVAL} 秒后进行下次检查..."
        sleep $CHECK_INTERVAL
    done
}

# 信号处理
cleanup() {
    log_info "收到退出信号，停止监控..."
    exit 0
}

trap cleanup SIGINT SIGTERM

# 启动监控
main_monitor
