#!/bin/bash

# 初始化参数
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --baseurl) BASE_URL="$2"; shift ;;
    --model-name) MODEL_NAME="$2"; shift ;;
    --home-path) HOME_PATH="$2"; shift ;;
    --tokenizer-path) TOKENIZER_PATH="$2"; shift ;;
    --output-dir) OUTPUT_DIR="$2"; shift ;;
    --batch-sizes) BATCH_SIZES="$2"; shift ;;
    --prompt-pairs) PROMPT_PAIRS="$2"; shift ;;
    --num-prompts) NUM_PROMPTS="$2"; shift ;;
    --help)
      echo "Usage: run_benchmark.sh [--baseurl URL] [--model-name NAME] [--home-path PATH] [...]"
      exit 0 ;;
    *) echo "❌ Unknown parameter: $1"; exit 1 ;;
  esac
  shift
done

# 参数检查
for var in BASE_URL MODEL_NAME HOME_PATH TOKENIZER_PATH  BATCH_SIZES PROMPT_PAIRS NUM_PROMPTS; do
  if [ -z "${!var}" ]; then
    echo "❌ ERROR: Missing required parameter --${var,,}"
    exit 1
  fi
done


SCRIPT="$HOME_PATH/llm-infer/test/perf_test/vllm/benchmarks/benchmark_serving.py"
SUMMARY_SCRIPT="$HOME_PATH/llm-infer/test/perf_test/summarize_results.py"
# 时间戳
timestamp=$(date '+%Y%m%d_%H%M')
benchmark_dir="$OUTPUT_DIR/benchmark"
mkdir -p "$benchmark_dir"

benchmark_dir_logs="$benchmark_dir/logs"
mkdir -p "$benchmark_dir_logs"

benchmark_dir_result="$benchmark_dir/result"
mkdir -p "$benchmark_dir_result"

SUMMARY_OUTPUT_MD="$benchmark_dir_result/summary_result_${timestamp}.md"

IFS=' ' read -ra BATCH_ARR <<< "$BATCH_SIZES"
IFS=';' read -ra PROMPT_PAIR_ARR <<< "$PROMPT_PAIRS"

echo "📌 参数确认:"
echo "MODEL_NAME        = $MODEL_NAME"
echo "TOKENIZER_PATH    = $TOKENIZER_PATH"
echo "OUTPUT_DIR        = $OUTPUT_DIR"
echo "BASE_URL          = $BASE_URL"
echo "BATCH_SIZES       = ${BATCH_ARR[*]}"
echo "PROMPT_PAIRS      = ${PROMPT_PAIR_ARR[*]}"
echo "NUM_PROMPTS       = $NUM_PROMPTS"
echo ""

start_time=$(date +%s)

for batch_size in "${BATCH_ARR[@]}"; do
  for pair in "${PROMPT_PAIR_ARR[@]}"; do
    input_len=$(echo "$pair" | awk '{print $1}')
    output_len=$(echo "$pair" | awk '{print $2}')
    LOG_FILE="$benchmark_dir_logs/log_input${input_len}_output${output_len}_batch${batch_size}.log"

    echo "▶️ [$(date '+%F %T')] input_len=$input_len, output_len=$output_len, batch_size=$batch_size" | tee -a "$LOG_FILE"

    python3 "$SCRIPT" \
      --backend vllm \
      --model "$MODEL_NAME" \
      --tokenizer "$TOKENIZER_PATH" \
      --dataset-name random \
      --random-input-len "$input_len" \
      --random-output-len "$output_len" \
      --num-prompts "$NUM_PROMPTS" \
      --max-concurrency "$batch_size" \
      --save-result \
      --base-url "$BASE_URL" \
      --ignore-eos \
      --save-detailed \
      --result-filename "$benchmark_dir_logs/result_input${input_len}_output${output_len}_batch${batch_size}.json" \
      >> "$LOG_FILE" 2>&1

    if [ $? -eq 0 ]; then
      echo "✅ SUCCESS" | tee -a "$LOG_FILE"
    else
      echo "❌ FAILED" | tee -a "$LOG_FILE"
    fi

    echo -e "---\n" >> "$LOG_FILE"
  done
done

python3 "$SUMMARY_SCRIPT" --dir "$benchmark_dir_logs" --output "$SUMMARY_OUTPUT_MD"

end_time=$(date +%s)
elapsed=$((end_time - start_time))
echo ""
echo "✅ 脚本运行完成，总耗时：$elapsed 秒 ($(date -ud "@$elapsed" +'%H:%M:%S'))"
echo "📂 结果已保存到：$benchmark_dir_logs"