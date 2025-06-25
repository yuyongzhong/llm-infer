import json
import argparse
from pathlib import Path
from datetime import datetime
import pandas as pd
import re

def summarize_json_files(input_dir: Path, output_file: Path, sort_by: str):
    records = []

    for json_file in sorted(input_dir.glob("result_*.json")):
        try:
            with open(json_file) as f:
                data = json.load(f)

            date_fmt = datetime.strptime(data["date"], "%Y%m%d-%H%M%S").strftime("%Y-%m-%d")
            completed = data.get("completed", 1)
            total_input = data.get("total_input_tokens", 0)
            total_output = data.get("total_output_tokens", 0)
            avg_input = total_input / completed if completed else 0
            avg_output = total_output / completed if completed else 0

            # 从文件名提取标准 input/output token 长度
            match = re.search(r"input(\d+)_output(\d+)", json_file.name)
            expected_input = int(match.group(1)) if match else None
            expected_output = int(match.group(2)) if match else None

            records.append({
                "date": date_fmt,
                "model": data["model_id"],
                "concurrency": data["max_concurrency"],
                "input_tokens": total_input,
                "output_tokens": total_output,
                "avg_input": avg_input,
                "avg_output": avg_output,
                "expected_input": expected_input,
                "expected_output": expected_output,
                "duration": data["duration"],
                "request_throughput": data["request_throughput"],
                "output_throughput": data["output_throughput"],
                "total_token_throughput": data["total_token_throughput"],
                "mean_ttft": data["mean_ttft_ms"],
                "p99_ttft": data["p99_ttft_ms"],
            })
        except Exception as e:
            print(f"⚠️ Failed to parse {json_file.name}: {e}")

    df = pd.DataFrame(records)

    # 排序逻辑
    if sort_by == "request_throughput":
        df.sort_values(by=["request_throughput"], ascending=False, inplace=True)
    elif sort_by == "duration":
        df.sort_values(by=["duration"], ascending=True, inplace=True)
    elif sort_by == "ttft":
        df.sort_values(by=["mean_ttft"], ascending=True, inplace=True)
    else:  # 默认按并发+期望输入token排序
        df.sort_values(by=["concurrency", "expected_input"], inplace=True)

    # 输出 Markdown 表格
    header = (
        "| 时间戳 | 模型 | 并发数 | 输入Tokens | 输出Tokens | 期望输入 | 期望输出 | 平均输入 | 平均输出 | 总耗时(s) | "
        "请求吞吐率 (req/s) | 输出吞吐率 (tok/s) | 总吞吐率 (tok/s) | 平均TTFT(ms) | P99_TTFT(ms) |"
    )
    align = (
        "|:--------:|:------:|:------:|:-----------:|:------------:|:----------:|:----------:|:----------:|:-----------:|:---------:|"
        ":------------------:|:------------------:|:----------------:|:-------------:|:-------------:|"
    )

    rows = [
        f"| {r.date} | {r.model} | {r.concurrency} | {r.input_tokens} | {r.output_tokens} | "
        f"{r.expected_input} | {r.expected_output} | {r.avg_input:.1f} | {r.avg_output:.1f} | "
        f"{r.duration:.2f} | {r.request_throughput:.2f} | {r.output_throughput:.2f} | "
        f"{r.total_token_throughput:.2f} | {r.mean_ttft:.2f} | {r.p99_ttft:.2f} |"
        for r in df.itertuples()
    ]

    with open(output_file, "w") as f:
        f.write("\n".join([header, align] + rows))

    print(f"✅ Markdown summary saved to {output_file}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir", type=Path, required=True, help="Directory containing result_*.json")
    parser.add_argument("--output", type=Path, required=True, help="Output markdown file")
    parser.add_argument(
        "--sort-by", type=str, default="concurrency+input_tokens",
        choices=["concurrency+input_tokens", "request_throughput", "duration", "ttft"],
        help="Sorting method for the markdown table"
    )
    args = parser.parse_args()

    summarize_json_files(args.dir, args.output, args.sort_by)

