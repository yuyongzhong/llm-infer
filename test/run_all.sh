#!/bin/bash

### ========= 参数与配置加载 ========= ###

# 必须传入配置文件
if [ $# -lt 1 ]; then
  echo "❌ 用法错误：请指定配置文件路径"
  echo "✅ 示例：sh run_all.sh ./config.env"
  exit 1
fi

CONFIG_FILE="$1"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ 配置文件不存在: $CONFIG_FILE"
  exit 1
fi

# 加载配置变量
set -a
. "$CONFIG_FILE"
set +a

# 检查关键变量
if [[ -z "$LOG_INFO" || -z "$HOME_PATH" ]]; then
  echo "❌ 缺少必要配置项：LOG_INFO 或 HOME_PATH"
  exit 1
fi

# 设置默认模式
RUN_MODE="${RUN_MODE:-acc-then-bench}"  # 如果未设置，默认先精度后性能

# 日志输出目录
TIMESTAMP=$(date '+%Y%m%d_%H%M')
OUTPUT_DIR="$HOME_PATH/llm-infer/test/logs/$LOG_INFO"
mkdir -p "$OUTPUT_DIR"

echo "🟢 日志目录: $OUTPUT_DIR"
echo "📌 当前时间戳: $TIMESTAMP"
echo "📦 模型: $model_name"
echo "🌐 服务地址: $BASE_URL"
echo "🎯 运行模式: $RUN_MODE"
echo ""

### ========= 精度评估函数 ========= ###
ACC_SCRIPT="$HOME_PATH/llm-infer/test/acc_test/scripts/evaluate_debug_yyz.py"

run_accuracy() {
  echo "🚀 [$(date '+%Y-%m-%d %H:%M:%S')] 开始精度评估..."

  ACCURACY_DIR="$OUTPUT_DIR/Accuracy_Test"
  mkdir -p "$ACCURACY_DIR"
  ACC_LOG_FILE="$ACCURACY_DIR/${TIMESTAMP}_acc_test.log"

  # 记录开始时间（秒级时间戳）
  start_time=$(date +%s)

  python3 "$ACC_SCRIPT" \
    --api_url "$api_url" \
    --model "$model_name" \
    --max_tokens "$max_tokens" \
    --datasets "$datasets" \
    --temperature "$temperature" \
    --top_p "$top_p" \
    --answer_num "$answer_num" \
    --use_cache "$use_cache" \
    --eval_batch_size "$eval_batch_size" \
    --acc_log_file "$ACC_LOG_FILE" \
    --webhook_url "$webhook_url" \
    --CHECK_INTERVAL "$CHECK_INTERVAL" \
    --base_info "$BASE_INFO" \
    --data_mode "$data_mode" 2>&1 | tee "$ACC_LOG_FILE"

  # 记录结束时间
  end_time=$(date +%s)
  duration=$((end_time - start_time))

  # 格式化输出为 HH:MM:SS
  duration_fmt=$(date -ud "@$duration" +'%H:%M:%S')

  echo "✅ 精度评估完成，耗时 ${duration} 秒（$duration_fmt），日志写入：$ACC_LOG_FILE"
  echo ""
}


### ========= 性能测试函数 ========= ###

BENCHMARK_SCRIPT="$HOME_PATH/llm-infer/test/perf_test/run_benchmark.sh"

run_benchmark() {

  BENCHMARK_LOG_FILE="$OUTPUT_DIR/benchmark/${TIMESTAMP}_benchmark.log"
  echo "🚀 [$(date '+%Y-%m-%d %H:%M:%S')] 开始性能测试..."

  start_time=$(date +%s)

  bash "$BENCHMARK_SCRIPT" \
    --baseurl "$BASE_URL" \
    --model-name "$model_name" \
    --home-path "$HOME_PATH" \
    --tokenizer-path "$TOKENIZER_PATH" \
    --output-dir "$OUTPUT_DIR" \
    --batch-sizes "$BATCH_SIZES" \
    --prompt-pairs "$PROMPT_PAIRS" \
    --num-prompts "$NUM_PROMPTS" 2>&1 | tee "$BENCHMARK_LOG_FILE"

  end_time=$(date +%s)
  duration=$((end_time - start_time))
  duration_fmt=$(date -ud "@$duration" +'%H:%M:%S')

  echo "✅ 性能测试完成，耗时 ${duration} 秒（$duration_fmt）"
  echo ""

  BENCHMARK_MD=$(ls -t "$OUTPUT_DIR/benchmark/result/"*.md 2>/dev/null | head -n 1)

  if [ -f "$BENCHMARK_MD" ]; then
    echo "📩 发送 Feishu 通知..."
    python3 "$HOME_PATH/llm-infer/test/acc_test/scripts/tools.py" \
      --benchmark_result "$BENCHMARK_MD" \
      --base_info "$BASE_INFO" \
      --webhook_url "$webhook_url"
    echo "✅ 通知已发送：$BENCHMARK_MD"
  else
    echo "⚠️ 没找到 benchmark markdown 结果文件，跳过通知。"
  fi
}

### ========= 主调度逻辑 ========= ###
case "$RUN_MODE" in
  accuracy)
    run_accuracy
    ;;
  benchmark)
    run_benchmark
    ;;
  acc-then-bench)
    run_accuracy
    run_benchmark
    ;;
  bench-then-acc)
    run_benchmark
    run_accuracy
    ;;
  *)
    echo "❌ 错误：未知模式 '$RUN_MODE'"
    echo "🧭 请在 config.env 中设置 RUN_MODE 为以下之一：accuracy | benchmark | acc-then-bench | bench-then-acc"
    exit 1
    ;;
esac

echo "🎉 所有任务执行完成 ✅"
