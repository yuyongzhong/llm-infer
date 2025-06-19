#!/bin/bash

# 默认 baseurl（可通过 --baseurl 参数覆盖）
BASE_URL="http://127.0.0.1:8000"

# 解析命令行参数
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --baseurl) BASE_URL="$2"; shift ;;
    *) echo "Unknown parameter passed: $1"; exit 1 ;;
  esac
  shift
done
INPUT_LENS=(32 128)
BATCH_SIZES=(16 32)
# INPUT_LENS=(32 128 256 1024)
# BATCH_SIZES=(1 4 16 32 64)
num_prompts=200
MODEL_NAME="deepseek"
TOKENIZER_PATH="/home/models/DeepSeek-R1-32B/"
OUTPUT_DIR="/home/llm-infer/test/perf-test/benchmark_logs"
SCRIPT="/home/llm-infer/test/perf-test/vllm/benchmarks/benchmark_serving.py"

mkdir -p $OUTPUT_DIR


for batch_size in "${BATCH_SIZES[@]}"; do
  for input_len in "${INPUT_LENS[@]}"; do
    LOG_FILE="$OUTPUT_DIR/log_input${input_len}_batch${batch_size}.log"
    echo "Running input_len=$input_len, batch_size=$batch_size..." | tee -a "$LOG_FILE"

    python3 $SCRIPT \
      --backend vllm \
      --model $MODEL_NAME \
      --tokenizer $TOKENIZER_PATH \
      --dataset-name random \
      --random-input-len $input_len \
      --random-output-len 128 \
      --num-prompts $num_prompts \
      --max-concurrency $batch_size \
      --save-result \
      --base-url $BASE_URL \
      --result-filename "$OUTPUT_DIR/result_input${input_len}_batch${batch_size}.json" \
      >> "$LOG_FILE" 2>&1

    if [ $? -eq 0 ]; then
      echo "�?SUCCESS input_len=$input_len batch_size=$batch_size" | tee -a "$LOG_FILE"
    else
      echo "�?FAILED input_len=$input_len batch_size=$batch_size" | tee -a "$LOG_FILE"
    fi

    echo -e "---\n" >> "$LOG_FILE"
  done
done
# # 所有测试完成后，调用结果汇�?echo "📊 所有测试完成，开始汇总结�?.."
# python3 run_summarize_results.py
