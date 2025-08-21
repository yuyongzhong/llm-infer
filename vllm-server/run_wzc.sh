#!/bin/bash

if [[ $1 == "--help" ]]; then
    echo "Usage: run.sh [TP_SIZE] [PP_SIZE] [MODEL_PATH] [HOSTFILE] [VLLM_PP_LAYER_PARTITION]"
    echo ""
    echo "Parameters:"
    echo "  TP_SIZE                      Number of Tensor Parallelism"
    echo "  PP_SIZE                      Number of Pipeline Parallelism"
    echo "  MODEL_PATH                   Path to the model"
    echo "  HOSTFILE                     Host file for distributed inference"
    echo "  VLLM_PP_LAYER_PARTITION      Optional partition scheme (comma-separated values); omit to skip"
    echo ""
    echo "Example:"
    echo "  ./run.sh 2 4 /path/to/model /path/to/hostfile 13,12,12,12,12"
    exit 0
fi

set -u
TP_SIZE=$1
PP_SIZE=$2
MODEL_PATH=$3
HOSTFILE=$4
VLLM_PP_LAYER_PARTITION="${5:-}"
set +u

MODEL_NAME=deepseek
MAX_MODEL_LEN=12000
BATCH_SIZE=128
NUM_GPU_BLOACKS=$(( MAX_MODEL_LEN * BATCH_SIZE ))
GPU_MEMORY_UTILIZATION=0.8
WORLD_SIZE=$((PP_SIZE * TP_SIZE))
SSH_PORT=62262
RAY_PORT=62379
MUSA_PRINT_ENV=1
MUSA_ERROR_DUMP_VERBOSE=1

env_array=(
    MCCL_PROTOS=2
    MUSA_PRINT_ENV=1
    MUSA_HOME="/usr/local/musa"
    TRITON_CACHE_DIR="/tmp/triton"
    LIBRARY_PATH="/opt/intel/oneapi/mkl/lib/intel64:${LIBRARY_PATH}"
    LD_LIBRARY_PATH="/usr/lib/x86_64-linux-gnu/:/usr/local/musa/lib"
    VLLM_NCCL_SO_PATH="/usr/local/musa/lib/libmccl.so.2"
    VLLM_TORCH_PROFILER_DIR="/home/model/"
    GLOO_SOCKET_IFNAME=bond0
    TP_SOCKET_IFNAME=bond0
    MUSA_LAUNCH_BLOCKING=1
    VLLM_USE_RAY_COMPILED_DAG_CHANNEL_TYPE=shm
    RAY_CGRAPH_get_timeout=3000
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

set -u
WORK_HOME="$PWD"
EXPNAME="pp${PP_SIZE}_tp${TP_SIZE}_gpus${WORLD_SIZE}"
LOG_FILE=$WORK_HOME/output/$CURRENT_TIME/$EXPNAME.log
set +u

mapfile -t hostlist < <(grep -v '^#\|^$' "$HOSTFILE" | awk '{print $1}' | tr -d '\r')


first_host=true
first_host_ip="127.0.0.1"
COUNT=0

for host in "${hostlist[@]}"; do
  ((COUNT++))
  echo "[$COUNT] Connecting to host: $host"

  env_str=$(printf "%s " "${env_array[@]}")

  echo "Checking if Ray is running on $host..."
  ssh -p "$SSH_PORT" "$host" "pgrep -f 'ray'" >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo "Ray is running on $host. Attempting to stop it..."
    ssh -p "$SSH_PORT" "$host" "ray stop"
  else
    echo "No running Ray process detected on $host."
  fi

  if [ "$first_host" = "true" ]; then
    first_host=false
    first_host_ip="$host"
    echo "Starting Head Node: $host"


    echo "Executing on $host:"
    printf "  %q " ssh -p "$SSH_PORT" "$host" "${env_array[@]}" ray start --head --port="${RAY_PORT}" --dashboard-host="0.0.0.0" --num-gpus 8
    echo

    ssh -p "$SSH_PORT" "$host" "${env_array[@]}" ray start --head --port="${RAY_PORT}" --dashboard-host="0.0.0.0" --num-gpus 8


    sleep 3s
  else
    echo "Joining cluster: $host -> $first_host_ip:${RAY_PORT}"


    echo "Executing on $host:"
    printf "  %q " ssh -p "$SSH_PORT" "$host" "${env_array[@]}" ray start --head --port="${RAY_PORT}" --dashboard-host="0.0.0.0" --num-gpus 8
    echo
    ssh -p $SSH_PORT $host "${env_array[@]} ray start --address ${first_host_ip}:${RAY_PORT} --num-gpus 8"

  fi

  echo "Host $host setup complete"
  echo "-----------------------------"
done



ray status
 
vllm serve $MODEL_PATH \
    --trust-remote-code \
    --gpu-memory-utilization 0.7 \
    --served-model-name deepseek \
    --block-size 16 \
    --tensor-parallel-size 8 \
    --pipeline-parallel-size 2 \
    --max-num-seqs 30 \
    --distributed-executor-backend ray\
    --compilation-config '{"cudagraph_capture_sizes": [1,2,3,4,5,6,7,8], "simple_cuda_graph": true}'
