import os
import json
import matplotlib.pyplot as plt
from datetime import datetime
import pandas as pd
import seaborn as sns
from collections import defaultdict

RESULT_DIR = "./benchmark_logs"
SUMMARY_FILE = "./benchmark_summary.csv"

results = []
errors = []

# 遍历目录中的 JSON 文件
for filename in os.listdir(RESULT_DIR):
    if filename.endswith(".json"):
        filepath = os.path.join(RESULT_DIR, filename)
        try:
            with open(filepath, "r") as f:
                result = json.load(f)
        except Exception as e:
            errors.append((filename, f"JSON 读取失败：{e}"))
            continue

        try:
            input_len = int(filename.split("input")[1].split("_")[0])
            batch_size = int(filename.split("batch")[1].split(".")[0])
            request_throughput = result.get("request_throughput", 0)
            output_throughput = result.get("output_throughput", 0)
            total_token_throughput = result.get("total_token_throughput", 0)
            mean_ttft_ms = result.get("mean_ttft_ms", 0)
            mean_tpot_ms = result.get("mean_tpot_ms", 0)
            mean_itl_ms = result.get("mean_itl_ms", 0)
            request_goodput = result.get("request_goodput") or result.get("request_goodput:")

            results.append({
                "input_len": input_len,
                "batch_size": batch_size,
                "request_throughput": request_throughput,
                "output_throughput": output_throughput,
                "total_token_throughput": total_token_throughput,
                "mean_ttft_ms": mean_ttft_ms,
                "mean_tpot_ms": mean_tpot_ms,
                "mean_itl_ms": mean_itl_ms,
                "request_goodput": request_goodput
            })
        except Exception as e:
            errors.append((filename, f"字段解析失败：{e}"))
            continue

print("results : ",results)
# 保存为 CSV
df = pd.DataFrame(results)
df = df.sort_values(by=["input_len", "batch_size"])
df.to_csv(SUMMARY_FILE, index=False)

# 可视化
plt.figure(figsize=(10, 6))
sns.lineplot(data=df, x="input_len", y="total_token_throughput", hue="batch_size", marker="o")
plt.title("Total Token Throughput vs. Input Length")
plt.xlabel("Input Length")
plt.ylabel("Token Throughput (tokens/s)")
plt.grid(True)
plt.tight_layout()
plt.savefig("throughput_plot.png")

# 打印错误信息
if errors:
    print("\n⚠️ 解析失败的文件：")
    for fname, reason in errors:
        print(f" - {fname}: {reason}")
