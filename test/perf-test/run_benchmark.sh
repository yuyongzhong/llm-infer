#!/bin/bash

# 默认 baseurl（可通过 --baseurl 参数覆盖）
BASE_URL="http://127.0.0.1:8000"
MODEL_NAME="deepseek"
HOME_PATH=""
MODEL_DIR_NAME=""

# 解析命令行参数
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --model-name) MODEL_NAME="$2"; shift ;;
    --home-path) HOME_PATH="$2"; shift ;;
    --model-dir-name) MODEL_DIR_NAME="$2"; shift ;;
    --baseurl) BASE_URL="$2"; shift ;;
    --help)
      echo "Usage: run_benchmark.sh [--model-name NAME] [--home-path PATH] [--model-dir-name NAME]"
      echo ""
      echo "  --model-name       模型名称（默认：deepseek）"
      echo "  --home-path        主目录路径，如 /home/llm-infer"
      echo "  --model-dir-name   模型目录名，如 DeepSeek-R1-32B"
      echo "  --baseurl          自定义推理服务 URL（默认：http://127.0.0.1:8000）"
      exit 0 ;;
    *) echo "Unknown parameter: $1"; exit 1 ;;
  esac
  shift
done

if [[ -z "$HOME_PATH" || -z "$MODEL_DIR_NAME" ]]; then
  echo "❌ ERROR: --home-path 和 --model-dir-name 为必填项。"
  exit 1
fi

# 统一时间戳（年月日_时分）
timestamp=$(date '+%Y%m%d_%H%M')

BATCH_SIZES=(1 4 8 16 32)
PROMPT_PAIRS=(
  "128 128"
  "256 256"
  "1024 1024"
  "2048 200"
  "2048 1024"
)
num_prompts=200



# PROMPT_PAIRS=(
#   "16 16"
#   "32 32"
# )
# BATCH_SIZES=(5 10)
# num_prompts=5


# 自动组装路径
TOKENIZER_PATH="$HOME_PATH/models/$MODEL_DIR_NAME/"
OUTPUT_DIR_FATHER="$HOME_PATH/llm-infer/test/perf-test/benchmark_logs"
OUTPUT_DIR="$OUTPUT_DIR_FATHER/benchmark_logs_${timestamp}"
SCRIPT="$HOME_PATH/llm-infer/test/perf-test/vllm/benchmarks/benchmark_serving.py"
SUMMARY_SCRIPT="$HOME_PATH/llm-infer/test/perf-test/summarize_results.py"
SUMMARY_OUTPUT_MD="$OUTPUT_DIR/summary_result_${timestamp}_.md"

echo "MODEL_NAME=$MODEL_NAME"
echo "TOKENIZER_PATH=$TOKENIZER_PATH"
echo "OUTPUT_DIR=$OUTPUT_DIR"

mkdir -p "$OUTPUT_DIR_FATHER"
mkdir -p "$OUTPUT_DIR"


start_time=$(date +%s)  # ⏱ 开始时间戳

for batch_size in "${BATCH_SIZES[@]}"; do
  for pair in "${PROMPT_PAIRS[@]}"; do
    input_len=$(echo "$pair" | awk '{print $1}')
    output_len=$(echo "$pair" | awk '{print $2}')
    LOG_FILE="$OUTPUT_DIR/log_${timestamp}_input${input_len}_output${output_len}_batch${batch_size}.log"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Running input_len=$input_len, output_len=$output_len, batch_size=$batch_size..." | tee -a "$LOG_FILE"

    python3 "$SCRIPT" \
      --backend vllm \
      --model "$MODEL_NAME" \
      --tokenizer "$TOKENIZER_PATH" \
      --dataset-name random \
      --random-input-len "$input_len" \
      --random-output-len "$output_len" \
      --num-prompts "$num_prompts" \
      --max-concurrency "$batch_size" \
      --save-result \
      --base-url "$BASE_URL" \
      --ignore-eos \
      --save-detailed \
      --result-filename "$OUTPUT_DIR/result_${timestamp}_input${input_len}_output${output_len}_batch${batch_size}.json" \
      >> "$LOG_FILE" 2>&1

    if [ $? -eq 0 ]; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS input_len=$input_len output_len=$output_len batch_size=$batch_size" | tee -a "$LOG_FILE"
    else
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] FAILED input_len=$input_len output_len=$output_len batch_size=$batch_size" | tee -a "$LOG_FILE"
    fi

    echo -e "---\n" >> "$LOG_FILE"
  done
done
# 🔍 汇总所有结果并生成 markdown 表格
python3 "$SUMMARY_SCRIPT" --dir "$OUTPUT_DIR" --output "$SUMMARY_OUTPUT_MD"

end_time=$(date +%s)  # ⏱ 结束时间戳
elapsed=$((end_time - start_time))  # 运行秒数
# 格式化输出运行时间
echo ""
echo "✅ 脚本运行完成，总耗时：${elapsed} 秒 ($(date -ud "@$elapsed" +'%H:%M:%S'))"