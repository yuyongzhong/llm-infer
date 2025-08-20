#!/bin/bash

### ========= 参数与配置加载 ========= ###

# 必须传入配置文件
if [ $# -lt 1 ]; then
  echo "❌ 用法错误：请指定配置文件路径"
  echo "✅ 示例：sh run_all.sh ./config.yaml"
  exit 1
fi

CONFIG_FILE="$1"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ 配置文件不存在: $CONFIG_FILE"
  exit 1
fi


# 从 YAML 加载配置并导出为环境变量

# ========= 设置数据集缓存环境变量 ========= #
if [ "$DATASET_CACHE_ENABLE" = "true" ]; then
    echo "🚀 设置evalscope数据集缓存优化..."
    export MODELSCOPE_CACHE="/root/.cache/modelscope"
    export HF_HOME="/root/.cache/huggingface"
    mkdir -p "$DATASET_CACHE_DIR"
    mkdir -p /root/.cache/huggingface
    echo "✅ 缓存环境设置完成: DATASET_CACHE_DIR=$DATASET_CACHE_DIR"
    echo "   Hub来源: $DATASET_HUB, 内存缓存: $MEM_CACHE"
else
    echo "⚠️ 数据集缓存优化已禁用"
fi

export model_name=$(yq e '.basic.model_name' "$CONFIG_FILE")
export HOME_PATH=$(yq e '.basic.home_path' "$CONFIG_FILE")
export LOG_INFO=$(yq e '.basic.log_info' "$CONFIG_FILE")
export BASE_INFO=$(yq e '.basic.base_info | tojson' "$CONFIG_FILE")  # 将整个 base_info 对象转换为 JSON 字符串
export RUN_MODE=$(yq e '.basic.run_mode' "$CONFIG_FILE")
export ENABLE_JSON_OUTPUT=$(yq e '.basic.enable_json_output // false' "$CONFIG_FILE")  # 默认 false 如果未设置

export api_url=$(yq e '.accuracy.api_url' "$CONFIG_FILE")
export temperature=$(yq e '.accuracy.temperature' "$CONFIG_FILE")
export top_p=$(yq e '.accuracy.top_p' "$CONFIG_FILE")
export use_cache=$(yq e '.accuracy.use_cache' "$CONFIG_FILE")
export max_tokens=$(yq e '.accuracy.max_tokens' "$CONFIG_FILE")
export datasets=$(yq e '.accuracy.datasets' "$CONFIG_FILE")
export data_mode=$(yq e '.accuracy.data_mode' "$CONFIG_FILE")
export answer_num=$(yq e '.accuracy.answer_num' "$CONFIG_FILE")
export eval_batch_size=$(yq e '.accuracy.eval_batch_size' "$CONFIG_FILE")

# 数据集缓存配置
export DATASET_CACHE_ENABLE=$(yq e '.accuracy.dataset_cache.enable // true' "$CONFIG_FILE")
export DATASET_CACHE_DIR=$(yq e '.accuracy.dataset_cache.cache_dir // "/root/.cache/modelscope/hub/datasets"' "$CONFIG_FILE")
export DATASET_HUB=$(yq e '.accuracy.dataset_cache.dataset_hub // "modelscope"' "$CONFIG_FILE")
export MEM_CACHE=$(yq e '.accuracy.dataset_cache.mem_cache // true' "$CONFIG_FILE")

export webhook_url=$(yq e '.notification.webhook_url' "$CONFIG_FILE")
export CHECK_INTERVAL=$(yq e '.notification.check_interval' "$CONFIG_FILE")

export BASE_URL=$(yq e '.benchmark.base_url' "$CONFIG_FILE")
export TOKENIZER_PATH=$(yq e '.benchmark.tokenizer_path' "$CONFIG_FILE")
export BATCH_SIZES=$(yq e '.benchmark.batch_sizes | join(" ")' "$CONFIG_FILE")  # 将数组转换为空格分隔字符串
export PROMPT_PAIRS=$(yq e '.benchmark.prompt_pairs | map(join(" ")) | join(";")' "$CONFIG_FILE")  # 将嵌套数组转换为原格式 "128 128;128 64;"
export NUM_PROMPTS=$(yq e '.benchmark.num_prompts' "$CONFIG_FILE")

# 检查关键变量
if [[ -z "$LOG_INFO" || -z "$HOME_PATH" ]]; then
  echo "❌ 缺少必要配置项：LOG_INFO 或 HOME_PATH"
  exit 1
fi

# 设置默认模式
RUN_MODE="${RUN_MODE:-acc-then-bench}"  # 如果未设置，默认先精度后性能

# 创建基础输出目录
BASE_OUTPUT_DIR="$HOME_PATH/llm-infer/test/output"
if [ ! -d "$BASE_OUTPUT_DIR" ]; then
  echo "📁 创建基础输出目录: $BASE_OUTPUT_DIR"
  mkdir -p "$BASE_OUTPUT_DIR"
fi

# 日志输出目录
TIMESTAMP=$(date '+%Y%m%d_%H%M')
OUTPUT_DIR="$BASE_OUTPUT_DIR/$LOG_INFO"
mkdir -p "$OUTPUT_DIR"

echo "🟢 日志目录: $OUTPUT_DIR"
echo "📌 当前时间戳: $TIMESTAMP"
echo "📦 模型: $model_name"
echo "🌐 服务地址: $BASE_URL"
echo "🎯 运行模式: $RUN_MODE"
echo ""

### ========= 精度评估函数 ========= ###
ACC_SCRIPT="$HOME_PATH/llm-infer/test/acc_test/scripts/evaluate_test.py"

run_accuracy() {
  echo "🚀 [$(date '+%Y-%m-%d %H:%M:%S')] 开始精度评估..."

  ACCURACY_DIR="$OUTPUT_DIR/Accuracy_Test"

  if [ ! -d "$ACCURACY_DIR" ]; then
    mkdir -p "$ACCURACY_DIR"
  fi

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
    --data_mode "$data_mode" \
    --dataset_cache_enable "$DATASET_CACHE_ENABLE" \
    --dataset_cache_dir "$DATASET_CACHE_DIR" \
    --dataset_hub "$DATASET_HUB" \
    --mem_cache "$MEM_CACHE" 2>&1 | tee "$ACC_LOG_FILE"

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
    echo "📩 发送 dingding 通知..."
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
  skip)
    echo "⚠️ 跳过精度测试和性能测试"
    BENCHMARK_MD=$(ls -t "$OUTPUT_DIR/benchmark/result/"*.md 2>/dev/null | head -n 1)
    ACC_LOG_FILE=$(ls -t "$OUTPUT_DIR/Accuracy_Test/"*.log 2>/dev/null | head -n 1)
    ;;  
  *)
    echo "❌ 错误：未知模式 '$RUN_MODE'"
    echo "🧭 请在 config.yaml 中设置 RUN_MODE 为以下之一：accuracy | benchmark | acc-then-bench | bench-then-acc"
    exit 1
    ;;
esac

# ========= 生成标准化 JSON 结果 ========= ###
if [ "$ENABLE_JSON_OUTPUT" = "true" ]; then
  echo "🚀 生成标准化测试结果 JSON..."

  # 确保变量已定义，如果没有则查找最新的文件
  if [ -z "$BENCHMARK_MD" ]; then
    BENCHMARK_MD=$(ls -t "$OUTPUT_DIR/benchmark/result/"*.md 2>/dev/null | head -n 1)
  fi
  
  if [ -z "$ACC_LOG_FILE" ]; then
    ACC_LOG_FILE=$(ls -t "$OUTPUT_DIR/Accuracy_Test/"*.log 2>/dev/null | head -n 1)
  fi

  # 生成 JSON 结果，如果文件不存在则传递空字符串
  python3 "$HOME_PATH/llm-infer/test/acc_test/scripts/generate_test_results.py" \
    --output-dir "$OUTPUT_DIR" \
    --acc-log "${ACC_LOG_FILE:-}" \
    --benchmark-md "${BENCHMARK_MD:-}" \
    --config "$HOME_PATH/llm-infer/test/config.yaml"

  echo "✅ JSON 生成完成"
else
  echo "⚠️ 标准化 JSON 输出已禁用（enable_json_output=false）"
fi

echo "🎉 所有任务执行完成 ✅"