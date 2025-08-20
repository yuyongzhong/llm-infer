import sys
import os
import time
import re
from datetime import datetime
import requests
import json
import argparse



def send_post_request(url, text):
    """ 发送 POST 请求到钉钉 """
    json_data = {
        "msgtype": "text",
        "text": {
            "content": text
        }
    }
    headers = {
        "Content-Type": "application/json"
    }

    try:
        response = requests.post(url, json=json_data, headers=headers, timeout=10)
        if response.status_code == 200:
            result = response.json()
            if result.get('errcode') == 0:
                print("✅ 钉钉消息发送成功")
                return response
            else:
                print(f"❌ 钉钉返回错误: {result}")
                return response
        else:
            print(f"❌ HTTP请求失败，状态码: {response.status_code}")
            return response
    except Exception as e:
        print(f"❌ 发送钉钉消息时出错: {e}")
        return None




def find_work_dir(log_file_path):
    """从日志文件中查找work_dir"""
    work_dir_pattern = re.compile(r'"work_dir"\s*[:=]\s*[\'"](.+?)[\'"]')
    work_dir = None

    try:
        with open(log_file_path, 'r', encoding='utf-8') as log_file:
            for line in log_file:
                match = work_dir_pattern.search(line)
                if match:
                    work_dir = match.group(1)
                    print(f"在日志中找到 work_dir: {work_dir}\n")
                    break
    except Exception as e:
        print(f"查找work_dir时出错: {e}\n")

    return work_dir


def report(log_file_path):
    """处理并报告评估结果"""
    # 查找work_dir
    work_dir = find_work_dir(log_file_path)

    if not work_dir:
        message = f"❌ 错误: 在{log_file_path}中未找到work_dir，无法继续处理JSON文件\n"
        return None, message

    # 从日志文件路径或内容中推断模型名称
    model_name = extract_model_name_from_log(log_file_path)
    
    # 处理work_dir的JSON文件，支持多种可能的模型名称
    possible_models = [model_name, 'deepseek', 'qwen', 'qwen2', 'chatglm', 'llama']
    json_path = None
    metrics = None
    
    for model in possible_models:
        if model:  # 确保model不是None
            json_path = os.path.join(work_dir, f"reports/{model}/ceval.json")
            print(f"🔍 尝试查找JSON文件: {json_path}")
            
            try:
                if os.path.exists(json_path):
                    print(f"✅ 报告文件路径: {json_path}")
                    with open(json_path, 'r') as json_file:
                        data = json.load(json_file)
                        # 提取metrics数据
                        metrics = data.get("metrics", {})
                        print("📊 找到ceval.json文件，metrics数据如下:")
                        print(str(metrics) + "\n")
                        message = f"✅ 成功找到评估文件: {json_path}"
                        return metrics, message
            except Exception as e:
                print(f"⚠️ 解析JSON文件时出错: {e}")
                continue
    
    # 如果所有尝试都失败，返回美化的错误信息
    tried_paths = []
    for model in possible_models:
        if model:
            tried_paths.append(os.path.join(work_dir, f"reports/{model}/ceval.json"))
    
    attempted_paths = "\n".join([f"   • {path}" for path in tried_paths])
    message = f"""🔍 搜索评估结果失败
📂 工作目录: {work_dir}
🤖 检测模型: {model_name or '未检测到'}
📋 尝试的路径:
{attempted_paths}

💡 请检查评估是否正常完成并生成了结果文件"""
    
    return None, message


def extract_model_name_from_log(log_file_path):
    """从日志文件路径或内容中提取模型名称"""
    # 首先尝试从文件路径中提取
    file_path_lower = log_file_path.lower()
    if 'deepseek' in file_path_lower:
        return 'deepseek'
    elif 'qwen' in file_path_lower:
        return 'qwen'
    
    # 如果文件路径中没有明确的模型名称，尝试从日志内容中提取
    try:
        with open(log_file_path, 'r', encoding='utf-8') as f:
            content = f.read()
            content_lower = content.lower()
            
            # 查找模型相关的关键词
            if 'deepseek' in content_lower or 'DeepSeek' in content:
                return 'deepseek'
            elif 'qwen' in content_lower or 'Qwen' in content:
                return 'qwen'
    except Exception as e:
        print(f"读取日志文件时出错: {e}")
    
    # 默认返回None，让调用者尝试所有可能的模型名称
    return None
        


def parse_metrics_data(metrics_data):
    """解析复杂的metrics数据结构，提取总体分数和类别分数"""
    if not metrics_data or not isinstance(metrics_data, list):
        return "无有效metrics数据", {}

    # 提取总体分数
    overall_score = "未找到"
    categories = {}

    for item in metrics_data:
        if item.get('name') == 'AverageAccuracy':
            overall_score = item.get('score', "未知")
            # 提取类别分数
            if 'categories' in item:
                for category in item['categories']:
                    cat_name = category.get('name', ["未知"])[0]  # 处理name可能是列表的情况
                    cat_score = category.get('score', "未知")
                    categories[cat_name] = cat_score
            break

    return overall_score, categories


def extract_errors(file_path, last_position):
    """从日志文件中提取错误信息，从指定位置开始读取"""
    error_pattern = re.compile(r'( error| failed)', re.IGNORECASE)
    finish_pattern = re.compile(r' finished', re.IGNORECASE)

    errors_found = False
    finished_found = False
    error_lines = []

    try:
        with open(file_path, 'r', encoding='utf-8') as log_file:
            log_file.seek(last_position)  # 移动到上一次读取的位置
            for line in log_file:
                if finish_pattern.search(line):
                    print("找到 Finished 标记，停止监控\n")
                    finished_found = True
                    break
                if error_pattern.search(line):
                    error_lines.append(line.strip())
                    errors_found = True
        if not errors_found:
            print("本次检查未发现错误\n")

    except Exception as e:
        print(f"处理文件时出错: {e}\n")
        error_lines.append(f"处理文件时出错: {e}\n")
        errors_found = True


    return finished_found,errors_found


def acc_log_monitor(file_path,base_info = None, webhook_url="https://oapi.dingtalk.com/robot/send?access_token=9ad9373a15c82ad31bca9da0d92f8602432b79c3ae5975bc6160cf9ab5d82b49",CHECK_INTERVAL=60):

    if base_info:
        base_info_text = f"{base_info}\n"
    else:
        base_info_text = ""

    print(f"日志文件: {file_path}")

    print(f"开始监控日志文件，每 {CHECK_INTERVAL / 60} 分钟检查一次\n")
    last_position = 0  # 初始位置为文件开头

    try:
        while True:
            print(f"检查时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            finished,errors_found = extract_errors(file_path, last_position)
            
            # 发送错误通知
            if errors_found:
                message_content = "\n".join([
                    base_info_text.rstrip(),  # 去掉末尾多余的换行
                    "docker eval 运行检测",
                    "运行出现异常",
                    "检测出Error/Failed 错误详情见 ",
                    f"eval日志文件: {file_path}"
                ])
                print(message_content)
                send_post_request(webhook_url, message_content)
                print("\n已发送钉钉信息\n")

            if finished:
                # 任务完成，获取评估报告
                metrics, message = report(file_path)
                if metrics:
                    # 解析复杂的metrics结构
                    overall_score, categories = parse_metrics_data(metrics)

                    # 构建美化的分数展示文本
                    if isinstance(overall_score, float):
                        score_text = f"📊 总体分数: {overall_score:.4f} ({overall_score*100:.2f}%)"
                    else:
                        score_text = f"📊 总体分数: {overall_score}"

                    # 构建类别分数，按分数排序
                    category_items = []
                    if categories:
                        # 按分数从高到低排序
                        sorted_categories = sorted(categories.items(), 
                                                 key=lambda x: x[1] if isinstance(x[1], float) else 0, 
                                                 reverse=True)
                        
                        for cat_name, cat_score in sorted_categories:
                            if isinstance(cat_score, float):
                                score_str = f"{cat_score:.4f} ({cat_score*100:.2f}%)"
                            else:
                                score_str = str(cat_score)
                            category_items.append(f"   • {cat_name}: {score_str}")

                    # 构建完整的评估结果
                    if category_items:
                        metrics_text = "\n".join([
                            score_text,
                            "📋 类别分数详情:",
                            *category_items
                        ])
                    else:
                        metrics_text = score_text

                    # 构建通知内容
                    newline_char = '\n'  # 先定义反斜杠字符
                    message_content = "\n".join([
                        base_info_text.rstrip(),
                        "🔍 docker eval 运行检测",
                        "✅ 运行正常结束",
                        "",
                        "📈 评估分数汇总:",
                        metrics_text,
                        "",
                        f"📄 详细报告文件: {message.split('文件: ')[-1].split(newline_char)[0] if '文件: ' in message else '已生成'}"
                    ])
                    print(message_content)
                    send_post_request(webhook_url, message_content)
                    print("\n已发送钉钉信息\n")
                else:
                    # 如果没有找到metrics数据，发送警告信息
                    message_content = "\n".join([
                        base_info_text.rstrip(),
                        "🔍 docker eval 运行检测", 
                        "⚠️ 运行正常结束，但未找到评估分数数据",
                        "",
                        "📋 详细信息:",
                        message.replace("❌ 错误: ", "").replace("🔍 搜索评估结果失败", "🔍 搜索评估结果失败").strip()
                    ])
                    print(message_content)
                    send_post_request(webhook_url, message_content)
                    print("\n已发送钉钉信息\n")


            # 更新文件位置
            last_position = os.path.getsize(file_path)
            time.sleep(CHECK_INTERVAL)
    except KeyboardInterrupt:
        print("\n程序已停止")

def benchmark_log_monitor(benchmark_result, base_info=None, webhook_url="https://oapi.dingtalk.com/robot/send?access_token=9ad9373a15c82ad31bca9da0d92f8602432b79c3ae5975bc6160cf9ab5d82b49"):
    if base_info:
        base_info_text = f"{base_info}\n"
    else:
        base_info_text = ""

    """
    构建推理性能测试通知内容（支持读取 result.md 文件）
    """
    if not os.path.exists(benchmark_result):
        message_content = "\n".join([
            base_info_text.rstrip(),
            "⚠️ 性能测试结果文件未找到: `{}`".format(benchmark_result)
        ])
    else:
        with open(benchmark_result, 'r', encoding='utf-8') as f:
            result_md = f.read()

        message_content = "\n".join([
            base_info_text.rstrip(),
            "✅ docker 性能测试结果如下：",
            "```markdown",
            result_md.strip(),
            "```"
        ])

    print(message_content)
    send_post_request(webhook_url, message_content)
    print("\n已发送钉钉信息\n")

if __name__ == "__main__":
    # base_info = "143机器，deepseek-r1"
    # file_path ="../../logs/temp.log"
    # acc_log_monitor(file_path,base_info)

    parser = argparse.ArgumentParser(description="Run evaluate tests on an OpenAI-compatible API.")
    parser.add_argument("--benchmark_result", type=str, required=True, help="The log file to monitor for errors.")
    parser.add_argument("--base_info", type=str, required=False, default="", help="The base information to include in notifications.")
    parser.add_argument("--webhook_url", type=str, required=False, default="https://oapi.dingtalk.com/robot/send?access_token=9ad9373a15c82ad31bca9da0d92f8602432b79c3ae5975bc6160cf9ab5d82b49") 
    
    args = parser.parse_args()

    benchmark_log_monitor(benchmark_result=args.benchmark_result,
                          base_info=args.base_info,
                          webhook_url=args.webhook_url)