#!/bin/bash

# =============================================================================
# vLLM 服务启动脚本
# 支持单机和多机分布式部署，包含完整的参数配置和性能优化选项
# =============================================================================

set -e  # 遇到错误立即退出

# =============================================================================
# 默认配置参数
# =============================================================================

# 基础参数
TP_SIZE=""                              # 张量并行大小（必需）
PP_SIZE=""                              # 流水线并行大小（必需）
MODEL_PATH=""                           # 模型路径（必需）
MODEL_NAME="deepseek"                   # 模型服务名称
PORT=8000                               # 服务端口

# 资源配置
MUSA_VISIBLE_DEVICES="0,1,2,3,4,5,6,7" # 可见GPU设备
MAX_MODEL_LEN=12000                     # 最大模型长度
BATCH_SIZE=128                          # 批处理大小
GPU_MEMORY_UTILIZATION=0.8              # GPU内存利用率
BLOCK_SIZE=16                           # 内存块大小

# 分布式配置
HOSTFILE=""                             # 多机配置文件
SSH_PORT=62262                          # SSH端口
RAY_PORT=62379                          # Ray端口
VLLM_PP_LAYER_PARTITION=""              # 流水线层分区

# 性能优化参数（可选）
MAX_NUM_SEQS=""                         # 最大序列数（为空时使用BATCH_SIZE）
ENABLE_CHUNKED_PREFILL=""               # 启用分块预填充 (true/false)
MAX_NUM_BATCHED_TOKENS=""               # 最大批处理token数
ENABLE_PREFIX_CACHING=""                # 启用前缀缓存 (true/false)
COMPILATION_CONFIG='{"cudagraph_capture_sizes": [1,2,3,4,5,6,7,8,10,12,14,16,18,20,24,28,30,32,64,128], "simple_cuda_graph": true}'  # 编译配置

# =============================================================================
# 帮助信息函数
# =============================================================================

show_help() {
    cat << 'EOF'
vLLM 服务启动脚本

用法:
    run.sh --tp <TP_SIZE> --pp <PP_SIZE> --model-path <MODEL_PATH> [OPTIONS]

必需参数:
    --tp, --tensor-parallel-size    张量并行大小
    --pp, --pipeline-parallel-size  流水线并行大小
    --model-path                    模型路径

基础配置:
    --model-name                    模型服务名称 (默认: deepseek)
    --port                          服务端口 (默认: 8000)
    --visible-devices               可见GPU设备 (默认: 0,1,2,3,4,5,6,7)
    --musa-visible-devices          MUSA可见GPU设备，覆盖默认值

性能参数:
    --max-model-len                 最大模型长度 (默认: 12000)
    --batch-size                    批处理大小 (默认: 128)
    --gpu-memory-utilization        GPU内存利用率 (默认: 0.8)
    --block-size                    内存块大小 (默认: 16)
    --max-num-seqs                  最大序列数
    --max-num-batched-tokens        最大批处理token数

优化选项:
    --enable-chunked-prefill        启用分块预填充 (true/false)
    --enable-prefix-caching         启用前缀缓存 (true/false)
    --compilation-config            编译配置JSON字符串

分布式配置:
    --hostfile                      多机配置文件
    --ssh-port                      SSH端口 (默认: 62262)
    --ray-port                      Ray端口 (默认: 62379)
    --partition                     流水线层分区

示例:
    # 基础单机启动
    run.sh --tp 2 --pp 1 --model-path /path/to/model

    # 高级性能优化
    run.sh --tp 4 --pp 1 --model-path /path/to/model \
           --enable-chunked-prefill true \
           --enable-prefix-caching true \
           --compilation-config '{"simple_cuda_graph": true}'

    # 指定GPU设备
    run.sh --tp 2 --pp 1 --model-path /path/to/deepseek \
           --musa-visible-devices "0,1"

    run.sh --tp 4 --pp 1 --model-path /path/to/qwen \
           --musa-visible-devices "2,3,4,5"

    # 多机分布式
    run.sh --tp 8 --pp 2 --model-path /path/to/model \
           --hostfile hosts.txt \
           --distributed-executor-backend ray

EOF
}

# =============================================================================
# 参数解析
# =============================================================================
while [[ $# -gt 0 ]]; do
  case $1 in
    # 必需参数
    --tp|--tensor-parallel-size)
      TP_SIZE="$2"; shift 2;;
    --pp|--pipeline-parallel-size)
      PP_SIZE="$2"; shift 2;;
    --model-path)
      MODEL_PATH="$2"; shift 2;;
    
    # 基础配置
    --model-name)
      MODEL_NAME="$2"; shift 2;;
    --port)
      PORT="$2"; shift 2;;
    --visible-devices)
      MUSA_VISIBLE_DEVICES="$2"; shift 2;;
    --musa-visible-devices)
      MUSA_VISIBLE_DEVICES="$2"; shift 2;;
    
    # 性能参数
    --max-model-len)
      MAX_MODEL_LEN="$2"; shift 2;;
    --batch-size)
      BATCH_SIZE="$2"; shift 2;;
    --gpu-memory-utilization)
      GPU_MEMORY_UTILIZATION="$2"; shift 2;;
    --block-size)
      BLOCK_SIZE="$2"; shift 2;;
    --max-num-seqs)
      MAX_NUM_SEQS="$2"; shift 2;;
    --max-num-batched-tokens)
      MAX_NUM_BATCHED_TOKENS="$2"; shift 2;;
    
    # 优化选项
    --enable-chunked-prefill)
      ENABLE_CHUNKED_PREFILL="$2"; shift 2;;
    --enable-prefix-caching)
      ENABLE_PREFIX_CACHING="$2"; shift 2;;
    --compilation-config)
      COMPILATION_CONFIG="$2"; shift 2;;
    
    # 分布式配置
    --hostfile)
      HOSTFILE="$2"; shift 2;;
    --ssh-port)
      SSH_PORT="$2"; shift 2;;
    --ray-port)
      RAY_PORT="$2"; shift 2;;
    --partition)
      VLLM_PP_LAYER_PARTITION="$2"; shift 2;;
    
    # 兼容性别名（已废弃，建议使用标准参数名）
    --tensor-parallel-size)
      TP_SIZE="$2"; shift 2;;
    --pipeline-parallel-size)
      PP_SIZE="$2"; shift 2;;
    
    # 兼容性别名（已废弃，建议使用标准参数名）
    --tensor-parallel-size)
      TP_SIZE="$2"; shift 2;;
    --pipeline-parallel-size)
      PP_SIZE="$2"; shift 2;;
    
    --help|-h)
      show_help; exit 0;;
    *)
      echo "❌ 未知参数: $1"
      echo "使用 --help 查看用法"
      exit 1;;
  esac
done

# =============================================================================
# 参数验证
# =============================================================================

validate_parameters() {
    local errors=()
    
    # 检查必需参数
    [[ -z "$TP_SIZE" ]] && errors+=("缺少必需参数: --tp")
    [[ -z "$PP_SIZE" ]] && errors+=("缺少必需参数: --pp")
    [[ -z "$MODEL_PATH" ]] && errors+=("缺少必需参数: --model-path")
    
    # 检查数值参数
    [[ ! "$TP_SIZE" =~ ^[0-9]+$ ]] && errors+=("--tp 必须是正整数")
    [[ ! "$PP_SIZE" =~ ^[0-9]+$ ]] && errors+=("--pp 必须是正整数")
    [[ ! "$PORT" =~ ^[0-9]+$ ]] && errors+=("--port 必须是正整数")
    
    # 检查模型路径
    [[ ! -d "$MODEL_PATH" ]] && errors+=("模型路径不存在: $MODEL_PATH")
    
    if [[ ${#errors[@]} -gt 0 ]]; then
        echo "❌ 参数验证失败:"
        printf "   %s\n" "${errors[@]}"
        echo "使用 --help 查看用法"
        exit 1
    fi
}

validate_parameters

# =============================================================================
# 计算派生参数
# =============================================================================

NUM_GPU_BLOCKS=$(( MAX_MODEL_LEN * BATCH_SIZE ))
WORLD_SIZE=$((PP_SIZE * TP_SIZE))

echo "📊 配置信息:"
echo "   模型路径: $MODEL_PATH"
echo "   张量并行: $TP_SIZE, 流水线并行: $PP_SIZE"
echo "   总GPU数: $WORLD_SIZE, 服务端口: $PORT"
echo "   最大模型长度: $MAX_MODEL_LEN, 批处理大小: $BATCH_SIZE"

# =============================================================================
# 环境配置
# =============================================================================

setup_environment() {
    echo "🔧 配置运行环境..."
    
    # 确定运行模式
    if [[ -z "$HOSTFILE" || ! -f "$HOSTFILE" ]]; then
        echo "💻 单机模式"
        USE_SINGLE_NODE=true
    else
        echo "🌐 多机模式，配置文件: $HOSTFILE"
        USE_SINGLE_NODE=false
    fi
    
    # 设置环境变量
    local env_vars=(
        MCCL_PROTOS=2
        MUSA_PRINT_ENV=1
        MTHREADS_VISIBLE_DEVICES=0,1,2,3,4,5,6,7
        MUSA_HOME="/usr/local/musa"
        TRITON_CACHE_DIR="/tmp/triton"
        LIBRARY_PATH="/opt/intel/oneapi/mkl/lib/intel64:${LIBRARY_PATH}"
        LD_LIBRARY_PATH="/usr/lib/x86_64-linux-gnu/:/usr/local/musa/lib"
        VLLM_NCCL_SO_PATH="/usr/local/musa/lib/libmccl.so.2"
        VLLM_TORCH_PROFILER_DIR="/home/model/"
        GLOO_SOCKET_IFNAME=bond0
        TP_SOCKET_IFNAME=bond0
        MUSA_VISIBLE_DEVICES=$MUSA_VISIBLE_DEVICES
        VLLM_USE_RAY_COMPILED_DAG_CHANNEL_TYPE=shm
        RAY_CGRAPH_get_timeout=3000
    )
    
    # 添加可选环境变量
    [[ -n "$VLLM_PP_LAYER_PARTITION" ]] && env_vars+=(VLLM_PP_LAYER_PARTITION="$VLLM_PP_LAYER_PARTITION")
    
    # 导出环境变量
    for var in "${env_vars[@]}"; do
        echo "export $var"
        eval "export $var"
    done
    
    # 清理之前的进程
    echo "🧹 清理环境..."
    pkill -f /opt/conda/envs/py310/bin/python3 || true
    ray stop || true
    rm -rf /tmp/triton/* || true
}

setup_environment

# =============================================================================
# 日志和输出目录设置
# =============================================================================

setup_logging() {
    CURRENT_TIME=$(date "+%Y-%m-%d_%H:%M:%S")
    WORK_HOME="$PWD"
    EXPNAME="pp${PP_SIZE}_tp${TP_SIZE}_gpus${WORLD_SIZE}"
    LOG_FILE="$WORK_HOME/output/$CURRENT_TIME/$EXPNAME.log"
    
    echo "📁 创建输出目录: $WORK_HOME/output/$CURRENT_TIME"
    mkdir -p "$WORK_HOME/output/$CURRENT_TIME"
    
    echo "📝 日志文件: $LOG_FILE"
}

setup_logging

# =============================================================================
# 分布式集群设置
# =============================================================================

setup_distributed_cluster() {
    [[ "$USE_SINGLE_NODE" = true ]] && return 0
    
    echo "🚀 设置分布式集群..."
    
    # 读取主机列表
    mapfile -t hostlist < <(grep -v '^#\|^$' "$HOSTFILE" | awk '{print $1}' | tr -d '\r')
    
    # 准备环境变量数组
    env_array=(
        "MCCL_PROTOS=2"
        "MUSA_PRINT_ENV=1" 
        "MTHREADS_VISIBLE_DEVICES=0,1,2,3,4,5,6,7"
        "MUSA_HOME=/usr/local/musa"
        "TRITON_CACHE_DIR=/tmp/triton"
        "LIBRARY_PATH=/opt/intel/oneapi/mkl/lib/intel64:"
        "LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu/:/usr/local/musa/lib"
        "VLLM_NCCL_SO_PATH=/usr/local/musa/lib/libmccl.so.2"
        "VLLM_TORCH_PROFILER_DIR=/home/model/"
        "GLOO_SOCKET_IFNAME=bond0"
        "TP_SOCKET_IFNAME=bond0"
        "MUSA_VISIBLE_DEVICES=${MUSA_VISIBLE_DEVICES}"
        "VLLM_USE_RAY_COMPILED_DAG_CHANNEL_TYPE=shm"
        "RAY_CGRAPH_get_timeout=3000"
    )
    
    first_host=true
    first_host_ip=""
    
    for host in "${hostlist[@]}"; do
        echo "🔗 处理主机: $host"
        
        # 停止现有Ray进程
        ssh -p "$SSH_PORT" "$host" "ray stop" || true
        
        if [ "$first_host" = "true" ]; then
            first_host=false
            first_host_ip="$host"
            echo "   启动头节点..."
            ssh -p "$SSH_PORT" "$host" "${env_array[@]}" ray start --head --port="${RAY_PORT}" --dashboard-host=0.0.0.0 --num-gpus=8
        else
            echo "   加入集群..."
            ssh -p "$SSH_PORT" "$host" "${env_array[@]}" ray start --address "${first_host_ip}:${RAY_PORT}" --num-gpus=8
        fi
        
        echo "   ✅ 主机 $host 完成"
    done
    
    echo "🔍 检查集群状态:"
    ray status
}

setup_distributed_cluster

# =============================================================================
# vLLM 命令构建
# =============================================================================

build_vllm_command() {
    echo "🔨 构建vLLM服务命令..."
    
    local cmd="vllm serve \"$MODEL_PATH\""
    
    # 基础参数
    cmd="$cmd --trust-remote-code"  # 默认启用
    cmd="$cmd --max_model_len $MAX_MODEL_LEN"
    cmd="$cmd --gpu-memory-utilization $GPU_MEMORY_UTILIZATION"
    cmd="$cmd --served-model-name $MODEL_NAME"
    cmd="$cmd --port $PORT"
    
    # 并行配置
    cmd="$cmd -tp $TP_SIZE"
    cmd="$cmd -pp $PP_SIZE"
    
    # 序列和批处理配置
    if [[ -n "$MAX_NUM_SEQS" && "$MAX_NUM_SEQS" != "" ]]; then
        cmd="$cmd --max-num-seqs $MAX_NUM_SEQS"
    else
        cmd="$cmd --max-num-seqs $BATCH_SIZE"
    fi
    
    # 可选的基础参数
    [[ -n "$BLOCK_SIZE" && "$BLOCK_SIZE" != "" ]] && cmd="$cmd --block-size $BLOCK_SIZE"
    
    # 性能优化参数
    [[ "$ENABLE_CHUNKED_PREFILL" = "true" ]] && cmd="$cmd --enable-chunked-prefill"
    [[ "$ENABLE_PREFIX_CACHING" = "true" ]] && cmd="$cmd --enable-prefix-caching"
    [[ -n "$MAX_NUM_BATCHED_TOKENS" && "$MAX_NUM_BATCHED_TOKENS" != "" ]] && cmd="$cmd --max-num-batched-tokens $MAX_NUM_BATCHED_TOKENS"
    
    # 编译配置
    if [[ -n "$COMPILATION_CONFIG" && "$COMPILATION_CONFIG" != "" ]]; then
        cmd="$cmd --compilation-config '$COMPILATION_CONFIG'"
    fi
    
    # 分布式执行后端（多机时使用Ray）
    if [[ "$USE_SINGLE_NODE" = false ]]; then
        cmd="$cmd --distributed-executor-backend ray"
    fi
    
    VLLM_CMD="$cmd"
}

build_vllm_command

# =============================================================================
# 启动 vLLM 服务
# =============================================================================

echo "🚀 启动vLLM服务..."
echo "🧐 最终命令:"
echo "$VLLM_CMD"
echo ""

eval "$VLLM_CMD" 2>&1 | tee -a "$LOG_FILE"
