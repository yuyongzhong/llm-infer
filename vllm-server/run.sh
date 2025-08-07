#!/bin/bash

# Default values
TP_SIZE=""
PP_SIZE=""
MODEL_PATH=""
MODEL_NAME="deepseek"
PORT=8000
MUSA_VISIBLE_DEVICES="0,1,2,3,4,5,6,7"
HOSTFILE=""
VLLM_PP_LAYER_PARTITION=""

# Parse named arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --tp)
      TP_SIZE="$2"; shift 2;;
    --pp)
      PP_SIZE="$2"; shift 2;;
    --model-path)
      MODEL_PATH="$2"; shift 2;;
    --model-name)
      MODEL_NAME="$2"; shift 2;;
    --port)
      PORT="$2"; shift 2;;
    --visible-devices)
      MUSA_VISIBLE_DEVICES="$2"; shift 2;;
    --hostfile)
      HOSTFILE="$2"; shift 2;;
    --partition)
      VLLM_PP_LAYER_PARTITION="$2"; shift 2;;
    --help)
      echo "Usage: run.sh --tp <TP_SIZE> --pp <PP_SIZE> --model-path <MODEL_PATH> [--model-name <MODEL_NAME>] [--port <PORT>] [--visible-devices <GPUs>] [--hostfile <HOSTFILE>] [--partition <PP_LAYER_PARTITION>]";
      exit 0;;
    *)
      echo "❌ Unknown argument: $1"; exit 1;;
  esac
done

# Check required args
if [[ -z "$TP_SIZE" || -z "$PP_SIZE" || -z "$MODEL_PATH" ]]; then
  echo "❌ Missing required arguments. Use --help to see usage."
  exit 1
fi

MAX_MODEL_LEN=12000
BATCH_SIZE=128
NUM_GPU_BLOACKS=$(( MAX_MODEL_LEN * BATCH_SIZE ))
GPU_MEMORY_UTILIZATION=0.8
WORLD_SIZE=$((PP_SIZE * TP_SIZE))
SSH_PORT=62262
RAY_PORT=62379

if [[ -z "$HOSTFILE" || ! -f "$HOSTFILE" ]]; then
  echo "💻 未传入 hostfile，默认进入单机模式"
  USE_SINGLE_NODE=true
else
  echo "🌐 检测到 hostfile，启用多机模式"
  USE_SINGLE_NODE=false
fi

env_array=(
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
)

if [[ -n "$VLLM_PP_LAYER_PARTITION" ]]; then
    env_array+=(VLLM_PP_LAYER_PARTITION="$VLLM_PP_LAYER_PARTITION")
fi

for item in "${env_array[@]}"; do
    echo "export $item"
    eval "export $item"
    done

pkill -f /opt/conda/envs/py310/bin/python3
ray stop
rm -rf /tmp/triton/*

CURRENT_TIME=$(date "+%Y-%m-%d_%H:%M:%S")
echo "$CURRENT_TIME"
mkdir -p ./output/$CURRENT_TIME
WORK_HOME="$PWD"
EXPNAME="pp${PP_SIZE}_tp${TP_SIZE}_gpus${WORLD_SIZE}"
LOG_FILE=$WORK_HOME/output/$CURRENT_TIME/$EXPNAME.log

if [[ "$USE_SINGLE_NODE" = false ]]; then
  mapfile -t hostlist < <(grep -v '^#\|^$' "$HOSTFILE" | awk '{print $1}' | tr -d '\r')
  first_host=true
  COUNT=0

  for host in "${hostlist[@]}"; do
    ((COUNT++))
    echo "[$COUNT] Connecting to host: $host"

    echo "Checking if Ray is running on $host..."
    ssh -p "$SSH_PORT" "$host" "pgrep -f 'ray'" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      echo "Ray is running on $host. Attempting to stop it..."
      ssh -p "$SSH_PORT" "$host" "ray stop"
    else
      echo "No running Ray process detected on $host."
    fi

    if $first_host; then
      first_host=false
      first_host_ip="$host"
      echo "Starting Head Node: $host"
      ssh -p "$SSH_PORT" "$host" "${env_array[@]} ray start --head --port=${RAY_PORT} --dashboard-host=\"0.0.0.0\" --num-gpus 8"
      sleep 3s
    else
      echo "Joining cluster: $host -> $first_host_ip:${RAY_PORT}"
      ssh -p "$SSH_PORT" "$host" "${env_array[@]} ray start --address ${first_host_ip}:${RAY_PORT} --num-gpus 8"
    fi

    echo "Host $host setup complete"
    echo "-----------------------------"
  done

  ray status
fi

VLLM_CMD="vllm serve \"$MODEL_PATH\" \
    --trust-remote-code \
    --max-num-seqs $BATCH_SIZE \
    --max_model_len $MAX_MODEL_LEN \
    --gpu-memory-utilization $GPU_MEMORY_UTILIZATION \
    --served-model-name $MODEL_NAME \
    --port $PORT \
    -tp $TP_SIZE \
    -pp $PP_SIZE"

if [[ "$USE_SINGLE_NODE" = false ]]; then
    VLLM_CMD="$VLLM_CMD --distributed-executor-backend ray"
fi

echo "🧐 Final vLLM serve command:"
echo "$VLLM_CMD"

eval "$VLLM_CMD" 2>&1 | tee -a "$LOG_FILE"
