import time
import openai
import concurrent.futures
from transformers import AutoTokenizer
from datetime import datetime
import argparse
import random

"""
    Concurrent Request Performance Analysis, include Summary of Response Time and Throughput.

    Example:
      python3 ds_r1_bench.py \
        --base_url http://0.0.0.0:8000/v1 \
        --model_name deepseek \
        --model_path /home/dist/DeepSeek-R1-BF16 \
        --max_tokens 100 \
        --num_requests_list 2
"""


questions = [
    "What do you think is the meaning of life?",
    "How do you define success, and what factors contribute to it?",
    "If you could change one thing about the world, what would it be and why?",
    "What are your thoughts on the relationship between science and ethics?",
    "How do you think artificial intelligence will impact human society in the next 50 years?",
    "What are the potential consequences of humans colonizing other planets?",
    "Do you believe that free will truly exists, or is everything determined by external factors?",
    "If you had to choose between love and money, which one would you pick and why?",
    "What is the role of education in shaping a person's future, and how can it be improved?",
    "What do you think is the greatest challenge humanity will face in the coming decades?"
]

def count_tokens(prompt, model_path):
    tokenizer = AutoTokenizer.from_pretrained(model_path)
    return len(tokenizer.encode(prompt))

def measure_performance(prompt, max_tokens, model_name, model_path, api_key, base_url):
    client = openai.Client(base_url=base_url, api_key=api_key)
    token_count = count_tokens(prompt, model_path)
    start_time = time.time()

    response = client.chat.completions.create(
        model=model_name,
        messages=[{"role": "user", "content": prompt}],
        temperature=0,
        max_tokens=max_tokens,
        stream=True  # Enable streaming mode
    )

    first_token_time = None
    total_tokens = 0
    first_token_received = False

    for chunk in response:
        if not first_token_received:
            first_token_time = time.time() - start_time
            first_token_received = True
        total_tokens += len(chunk.choices[0].delta.content.split())

    total_time = time.time() - start_time
    tps = total_tokens / total_time if total_time > 0 else 0

    return {
        "concurrent_requests": None,  # Placeholder, to be updated in multi-run function
        "prompt_length": token_count,
        "max_tokens": max_tokens,
        "time_to_first_token": first_token_time,
        "tokens_per_second": tps,
        "total_time": total_time,
        "total_tokens": total_tokens,
    }

def run_concurrent_tests(questions, num_requests_list, max_tokens, model_name, model_path, api_key, base_url):
    results = []

    try:
        for num_requests in num_requests_list:
            print(f"Running {num_requests} concurrent requests...")
            with concurrent.futures.ThreadPoolExecutor(max_workers=num_requests) as executor:
                futures = [
                    executor.submit(measure_performance, random.choice(questions), max_tokens, model_name, model_path, api_key, base_url)
                    for _ in range(num_requests)
                ]
                concurrent_results = [future.result() for future in concurrent.futures.as_completed(futures)]
                avg_promt_length = sum(res["prompt_length"] for res in concurrent_results) / num_requests
                avg_time_to_first_token = sum(res["time_to_first_token"] for res in concurrent_results) / num_requests
                avg_tokens_per_second = sum(res["tokens_per_second"] for res in concurrent_results) / num_requests
                avg_total_time = sum(res["total_time"] for res in concurrent_results) / num_requests
                total_tokens = sum(res["total_tokens"] for res in concurrent_results)

                results.append({
                    "concurrent_requests": num_requests,
                    "prompt_length": avg_promt_length,
                    "max_tokens": max_tokens,
                    "time_to_first_token": avg_time_to_first_token,
                    "tokens_per_second": avg_tokens_per_second,
                    "total_time": avg_total_time,
                    "total_tokens": total_tokens,
                })
            print("results: ",results)
    except:
        print("Error")
    # 生成 Markdown 报告
    markdown_report = generate_markdown(results)

    # 保存报告到文件
    with open("concurrent_performance_report.md", "w") as f:
        f.write(markdown_report)

    print("Concurrent performance report generated: concurrent_performance_report.md")

    return results

def generate_markdown(results):
    md_report = """# Concurrent Request Performance Analysis
## Summary of Response Time and Throughput
| Concurrent Requests | Prompt Length | Max Tokens | Time to First Token (s) | Tokens per Second | Total Time (s) | Total Tokens |
|--------------------|--------------|------------|-------------------------|-------------------|---------------|-------------|
"""

    for res in results:
        md_report += f"| {res['concurrent_requests']} | {res['prompt_length']} | {res['max_tokens']} | {res['time_to_first_token']:.4f} | {res['tokens_per_second']:.4f} | {res['total_time']:.4f} | {res['total_tokens']} |\n"

    return md_report

def main():
    # 使用 argparse 解析命令行参数
    parser = argparse.ArgumentParser(description="Run concurrent performance tests on an OpenAI-compatible API.")
    parser.add_argument("--base_url", type=str, required=True, help="The base URL of the API (e.g., http://192.168.98.22:30000/v1).")
    parser.add_argument("--api_key", type=str, required=False, default="KEY", help="The API key for authentication.")
    parser.add_argument("--model_name", type=str, required=True, help="The model name you register(e.g., Qwen/Qwen2.5-3B-Instruct).")
    parser.add_argument("--model_path", type=str, required=False, help="The local model path(e.g., /home/Qwen2.5-3B-Instruct).")
    # parser.add_argument("--prompt", type=str, default="Write an extremely long story.", help="The prompt to send to the model.")
    parser.add_argument("--num_requests_list", type=int, nargs="+", default=[1,2,4], help="List of concurrency levels to test (e.g., 1 5 10). default=[1,2,4,8,16,32]")
    parser.add_argument("--max_tokens", type=int, default=8192, help="The maximum number of tokens to generate in the response(default=8192).")

    args = parser.parse_args()

    # 获取命令行参数
    base_url = args.base_url
    api_key = args.api_key
    model_name = args.model_name
    model_path = args.model_path
    # prompt = args.prompt
    num_requests_list = args.num_requests_list
    max_tokens = args.max_tokens

    if not args.model_path:
        model_path = model_name

    # 运行测试
    results = run_concurrent_tests(questions, num_requests_list, max_tokens, model_name, model_path, api_key, base_url)



if __name__ == "__main__":
    main()