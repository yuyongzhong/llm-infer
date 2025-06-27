import argparse
import importlib
import sys
import time
import requests
import threading
from requests.exceptions import ConnectionError, Timeout, TooManyRedirects
from evalscope import TaskConfig, run_task
from evalscope.constants import EvalType
from update_subset_list import main as update_subset_main
from log_monitor import main as log_monitor_main

# 全局停止标志
stop_flag = threading.Event()

def load_subset(tasks):
    try:
        # 尝试导入模块
        module_name = f"tasks.{tasks}"
        try:
            # 如果模块已导入，先卸载它
            module = sys.modules[module_name]
            importlib.reload(module)  # 重新加载模块
        except (KeyError, NameError):
            # 模块未导入，正常导入
            module = importlib.import_module(module_name)

        # 确保 subset_list 存在
        if not hasattr(module, 'subset_list'):
            raise AttributeError(f"Module {module_name} has no attribute 'subset_list'")

        return module.subset_list

    except (ImportError, AttributeError) as e:
        raise ValueError(f"Failed to load subset_list for {tasks}: {str(e)}")

def main():
    parser = argparse.ArgumentParser(description="Run evaluate tests on an OpenAI-compatible API.")
    parser.add_argument("--base_url", type=str, required=True, help="The base URL of the API (e.g., http://192.168.98.22:30000/v1).")
    parser.add_argument("--api_key", type=str, required=False, default="KEY", help="The API key for authentication.")
    parser.add_argument("--model_name", type=str, required=True, help="The model name you register(e.g., Qwen/Qwen2.5-3B-Instruct).")
    parser.add_argument("--max_tokens", type=int, default=8192, help="The maximum number of tokens to generate in the response(default=8192).")
    parser.add_argument("--tasks", type=str, required=False, default="ceval", help="The dataset to evaluate(default=ceval).")
    parser.add_argument("--temperature", type=float, required=False, default=0.6, help="The sampling temperature(default=0.6).")
    parser.add_argument("--top_p", type=float, required=False, default=0.95, help="The sampling top-p(default=1).")
    parser.add_argument("--answer_num", type=int, required=False, default=1, help="The answer for each request(default=1).")
    parser.add_argument("--use_cache", type=str, required=False, default="", help="The  cache path for the inference results.")
    parser.add_argument("--eval_batch_size", type=int, required=False, default=1, help="并发量")

    args = parser.parse_args()

    # 打印所有参数
    print("\n===== 传入的参数 =====")
    for arg_name, arg_value in vars(args).items():
        print(f"{arg_name}: {arg_value}")
    print("=====================\n")

    base_url = args.base_url
    api_key = args.api_key
    model_name = args.model_name
    max_tokens = args.max_tokens
    tasks = args.tasks
    temperature = args.temperature
    top_p = args.top_p
    answer_num = args.answer_num
    eval_batch_size = args.eval_batch_size
    use_cache = args.use_cache

    subset_list = load_subset(tasks)

    task_cfg = TaskConfig(
        model = model_name,
        api_url = base_url,
        api_key = api_key,
        eval_type = EvalType.SERVICE,

        datasets=[tasks],
        dataset_args={
            tasks: {
                "subset_list": subset_list
                }
        },

        eval_batch_size=eval_batch_size,
        generation_config={
            'max_tokens': max_tokens,
            'temperature': temperature,
            'top_p': top_p,
            'n': answer_num
        },

        stream=True
    )

    if use_cache != "":
        task_cfg.use_cache = use_cache

    # 创建守护线程来执行 log_monitor_main
    monitor_thread = threading.Thread(target=log_monitor_main)
    monitor_thread.daemon = True
    monitor_thread.start()

    # 执行评估任务
    max_run_retries = 5  # 最大运行重试次数
    run_retries = 0
    while run_retries < max_run_retries:
        try:
            print(f"开始第 {run_retries + 1} 次评估尝试...")
            run_task(task_cfg=task_cfg)
            # 删除subset_list 列表数据
            # update_subset_main()
            break  # 评估成功，跳出循环
        except Exception as e:
            print(f"评估过程中发生错误 (尝试 {run_retries + 1}/{max_run_retries}): {e}")
            run_retries += 1  # 增加重试计数
            # 删除subset_list 列表数据
            # update_subset_main()
            # 重新加载
            subset_list = load_subset(tasks)
            # 更新配置
            task_cfg.dataset_args = {tasks: {"subset_list": subset_list}}
            # 检查服务状态
            if check_service_availability(base_url, api_key, model_name):
                print("服务已恢复，准备下一次重试...")
            else:
                print("服务仍不可用，退出程序")
                break  # 服务不可用，不再重试
    time.sleep(300)

# 重试配置
MAX_RETRIES = 10
RETRY_DELAY = 60  # 秒
BACKOFF_FACTOR = 1.5  # 退避因子


def check_service_availability(url, api_key, model_name, retries=MAX_RETRIES, delay=RETRY_DELAY):
    """检查服务是否可用，并验证指定模型是否存在"""
    headers = {"Authorization": f"Bearer {api_key}"} if api_key else {}
    endpoint = f"{url}/models"  # 检查模型列表端点

    for attempt in range(retries):
        try:
            response = requests.get(endpoint, headers=headers, timeout=10)
            if response.status_code != 200:
                raise ConnectionError(f"服务返回错误: {response.status_code}")

            # 解析模型列表，验证指定模型是否存在
            models = response.json()
            if model_name:
                model_exists = any(
                    model.get("id") == model_name or model.get("name") == model_name
                    for model in models.get("data", [])
                )
                if not model_exists:
                    raise ValueError(f"模型 '{model_name}' 不存在于服务中")

            print(f"服务已恢复，模型可用 (尝试 {attempt + 1}/{retries})")
            return True

        except (ConnectionError, Timeout, TooManyRedirects) as e:
            print(f"服务不可用 (尝试 {attempt + 1}/{retries}): {e}")
        except ValueError as e:
            print(f"服务可用，但模型检查失败 (尝试 {attempt + 1}/{retries}): {e}")
        except Exception as e:
            print(f"未知错误 (尝试 {attempt + 1}/{retries}): {e}")

        # 指数退避：每次重试等待时间递增
        wait_time = delay * (BACKOFF_FACTOR ** attempt)
        print(f"等待 {wait_time:.1f} 秒后重试...")
        time.sleep(wait_time)

    print(f"达到最大重试次数 ({retries})，服务仍不可用或模型不存在")
    return False

if __name__ == "__main__":
    main()
    #service_url = "http://10.1.1.11:8000/v1"
    #api_key = "KEY"
    #model_name = "deepseek"

    #print(f"测试服务和模型: {model_name} @ {service_url}")
    #is_available = check_service_availability(service_url, api_key, model_name)

    #if is_available:
    #    print("✅ 服务和模型均可用")
    #else:
    #    print("❌ 服务不可用或模型不存在")