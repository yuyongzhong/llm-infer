import sys, os

# 添加 test/ 目录到模块路径
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../../")))
# 添加 tasks/ 目录到模块路径
TASKS_PATH = os.path.abspath(os.path.join(os.path.dirname(__file__), "../tasks"))
if TASKS_PATH not in sys.path:
    sys.path.insert(0, TASKS_PATH)
import ceval
print(ceval.subset_list)

import argparse
import importlib
import sys
import time
import requests
from requests.exceptions import ConnectionError, Timeout, TooManyRedirects
from evalscope import TaskConfig, run_task
from evalscope.constants import EvalType
from acc_test.scripts.tools import acc_log_monitor 
import threading

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

def load_subset(tasks, data_mode="all"):
    """
    加载任务子集列表或使用全量任务列表（等价于模块名本身）.

    参数:
        tasks (str): 模块名，例如 'ceval'
        mode (str): 'subset' 使用模块中的 subset_list,
                    'all' 表示使用模块名本身作为唯一项返回

    返回:
        dict: 包含每个任务名称及其对应子集列表的字典
    """
    # 兼容字符串和 list 输入
    if isinstance(tasks, str):
        task_list = [t.strip() for t in tasks.split(",") if t.strip()]
    else:
        task_list = list(tasks)
    if isinstance(data_mode, str):
        data_mode_list = [t.strip() for t in data_mode.split(",") if t.strip()]
    else:
        data_mode_list = list(data_mode)

    if len(task_list) != len(data_mode_list):
        raise ValueError(f"task_list 和 data_mode_list 长度不一致: {len(task_list)} vs {len(data_mode_list)}")
    
    
    results = {}

    for task_name, data_mode in zip(task_list, data_mode_list):
        try:
            module_name = task_name
            try:
                module = sys.modules[module_name]
                importlib.reload(module)
            except (KeyError, NameError):
                module = importlib.import_module(module_name)
            
            # 根据模式获取数据
            if data_mode == "subset":
                if not hasattr(module, 'subset_list'):
                    raise AttributeError(f"Module {module_name} has no attribute 'subset_list'")
                results[task_name] = module.subset_list
                # return module.subset_list        
            elif data_mode == "all":
                if not hasattr(module, 'all'):
                    raise AttributeError(f"Module {module_name} has no attribute 'subset_list'")
                results[task_name] = module.all
                # return module.all
            else:
                raise ValueError(f"Invalid mode '{data_mode}'. Use 'subset' or 'all'.")
        
        except Exception as e:
            raise ValueError(f"Failed to load subset list for {tasks}: {str(e)}")
        
    return results




def main():
    parser = argparse.ArgumentParser(description="Run evaluate tests on an OpenAI-compatible API.")
    parser.add_argument("--api_url", type=str, required=True, help="The base URL of the API (e.g., http://192.168.98.22:30000/v1).")
    parser.add_argument("--api_key", type=str, required=False, default="KEY", help="The API key for authentication.")
    parser.add_argument("--model", type=str, required=True, help="The model name you register(e.g., Qwen/Qwen2.5-3B-Instruct).")
    parser.add_argument("--max_tokens", type=int, default=8192, help="The maximum number of tokens to generate in the response(default=8192).")
    parser.add_argument("--datasets", type=str, required=False, default="ceval", help="The dataset to evaluate(default=ceval).")
    parser.add_argument("--temperature", type=float, required=False, default=0.6, help="The sampling temperature(default=0.6).")
    parser.add_argument("--top_p", type=float, required=False, default=0.95, help="The sampling top-p(default=1).")
    parser.add_argument("--answer_num", type=int, required=False, default=1, help="The answer for each request(default=1).")
    parser.add_argument("--use_cache", type=str, required=False, default="", help="The  cache path for the inference results.")
    parser.add_argument("--eval_batch_size", type=int, required=False, default=1, help="并发量")
    parser.add_argument("--data_mode", type=str, required=False, default="all", help="The mode for loading subsets: 'subset' for specific subsets, 'all' for the entire module name.")
    parser.add_argument("--acc_log_file", type=str, required=True, help="The log file for accuracy test results. ")
    parser.add_argument("--webhook_url", type=str, required=False, default="https://oapi.dingtalk.com/robot/send?access_token=9ad9373a15c82ad31bca9da0d92f8602432b79c3ae5975bc6160cf9ab5d82b49", help="The webhook URL for sending notifications.")
    parser.add_argument("--CHECK_INTERVAL", type=int, required=False, default=300, help="The interval in seconds to check the log file for updates(default=300).")
    parser.add_argument("--base_info", type=str, required=False,default="",help="The base information to include in notifications.")

    args = parser.parse_args()

    # 打印所有参数
    print("\n===== 传入的参数 =====")
    for arg_name, arg_value in vars(args).items():
        print(f"{arg_name}: {arg_value}")
    print("=====================\n")

    api_url = args.api_url
    api_key = args.api_key
    model = args.model
    max_tokens = args.max_tokens
    datasets = args.datasets
    temperature = args.temperature
    top_p = args.top_p
    answer_num = args.answer_num
    eval_batch_size = args.eval_batch_size
    use_cache = args.use_cache
    data_mode = args.data_mode

    ###监控参数
    acc_log_file = args.acc_log_file
    
    webhook_url = args.webhook_url
    CHECK_INTERVAL = args.CHECK_INTERVAL
    base_info = args.base_info

    subset_lists = load_subset(datasets, data_mode=data_mode)

    task_cfg = TaskConfig(
        model = model,
        api_url = api_url,
        api_key = api_key,
        eval_type = EvalType.SERVICE,

        datasets=list(subset_lists.keys()),
        dataset_args={
            task_name: {
                "subset_list": subset_list,
                } for task_name, subset_list in subset_lists.items()
        },

        eval_batch_size=eval_batch_size,
        generation_config={
            'max_tokens': max_tokens,
            'temperature': temperature,
            'top_p': top_p,
            'n': answer_num
        },

        stream=True,
    )

    if use_cache != "":
        task_cfg.use_cache = use_cache

    # 创建守护线程来执行 acc_log_monitor
    monitor_thread = threading.Thread(target=acc_log_monitor,    kwargs={
        "file_path": acc_log_file,
        "base_info": base_info,
        "webhook_url": webhook_url,
        "CHECK_INTERVAL": 300
    })
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
            subset_list = load_subset(datasets,data_mode=data_mode)
            # 更新配置
            task_cfg.dataset_args = {datasets: {"subset_list": subset_list}}
            # 检查服务状态
            if check_service_availability(api_url, api_key, model):
                print("服务已恢复，准备下一次重试...")
            else:
                print("服务仍不可用，退出程序")
                break  # 服务不可用，不再重试
    time.sleep(300)    

if __name__ == "__main__":
    main()
