import argparse
import importlib
from evalscope import TaskConfig, run_task
from evalscope.constants import EvalType

def load_subset(tasks):
    try:
        module = importlib.import_module(f"tasks.{tasks}")
        return module.subset_list
    except (ImportError, AttributeError) as e:
        raise ValueError(f"load tasks subset_list {tasks}: {str(e)}")

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
    parser.add_argument("--use_cache", type=str, required=False,  default= "",help="The  cache path for the inference results.")
    parser.add_argument("--eval_batch_size", type=int, required=False,  default=1, help="The  cache path for the inference results.")
    args = parser.parse_args()

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
        model=model_name,
        api_url=base_url,
        api_key=api_key,
        eval_type=EvalType.SERVICE,

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


    run_task(task_cfg=task_cfg)

if __name__ == "__main__":
    main()
