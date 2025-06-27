import sys
import os
import time
import re
from datetime import datetime
import requests
import json


DEFAULT_WEBHOOK_URL = "https://oapi.dingtalk.com/robot/send?access_token=9ad9373a15c82ad31bca9da0d92f8602432b79c3ae5975bc6160cf9ab5d82b49"
CHECK_INTERVAL = 300

def send_post_request(url, text):
    """ 发送 POST 请求 """
    json_data = {
        "at": {"isAtAll": "true"},
        "link": {"messageUrl": "1", "picUrl": "1", "text": "1", "title": "1"},
        "text": {"content": text},
        "msgtype": "text",
        "actionCard": {
            "hideAvatar": "1",
            "btnOrientation": "1",
            "singleTitle": "1",
            "btns": [{"actionURL": "1", "title": "1"}],
            "text": "1",
            "singleURL": "1",
            "title": "1"
        }
    }
    headers = {
        "Content-Type": "application/json"
    }

    response = requests.post(url, json=json_data, headers=headers)
    return response

def find_latest_log_file():
    """查找当前目录下最新的 .log 文件"""
    log_files = [f for f in os.listdir('.') if f.endswith('.log')]
    if not log_files:
        print("错误：当前目录下没有找到 .log 文件\n")
        sys.exit(1)
    return max(log_files, key=lambda x: os.path.getmtime(x))

def report (work_dir):
    # 处理work_dir的JSON文件
    json_path = os.path.join(work_dir, "reports/deepseek/ceval.json")
    try:
        if os.path.exists(json_path):
            with open(json_path, 'r') as json_file:
                data = json.load(json_file)
                # 提取metrics数据
                metrics = data.get("metrics", {})
                print("找到ceval.json文件，metrics数据如下:")
                print(str(metrics)+"\n")
                # 添加到通知内容
                return metrics
        else:
            print(f"警告: 文件不存在: {json_path}\n")
    except Exception as e:
        print(f"解析JSON文件时出错: {e}\n")


def parse_metrics_data(metrics_data):
    """解析metrics数据结构，提取总体分数和类别分数"""
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
                    cat_name = category.get('name', ["未知"])[0]
                    cat_score = category.get('score', "未知")
                    categories[cat_name] = cat_score
            break

    return overall_score, categories

def extract_errors(file_path):
    """从日志文件中提取错误信息"""
    error_pattern = re.compile(r'( error| failed)', re.IGNORECASE)
    finish_pattern = re.compile(r' finished', re.IGNORECASE)
    work_dir_pattern = re.compile(r'"work_dir"\s*[:=]\s*[\'"](.+?)[\'"]')

    errors_found = False
    finished_found = False
    error_lines = []
    work_dir = None

    try:
        with open(file_path, 'r', encoding='utf-8') as log_file:
            for line in log_file:
                # 提取work_dir
                if work_dir is None:
                    match = work_dir_pattern.search(line)
                    if match:
                        work_dir = match.group(1)
                        print(f"找到 work_dir: {work_dir}\n")

                if finish_pattern.search(line):
                    print("找到 Finished 标记，停止监控\n")
                    finished_found = True
                    break
                if error_pattern.search(line):
                    error_lines.append(line.strip())
                    errors_found = True
                    # print(f"发现错误: {line.strip()}\n")
        if not errors_found:
            print("本次检查未发现错误\n")

    except Exception as e:
        print(f"处理文件时出错: {e}\n")
        error_lines.append(f"处理文件时出错: {e}\n")
        errors_found = True

    # 发送错误通知
    if errors_found:
        message_content = "\n".join([
            "docker eval 运行检测",
            "运行异常结束",
            "检测出Error/Failed 错误详情见 ",
            f"eval日志文件: {os.path.basename(file_path)}"
        ])
        print(message_content)
        send_post_request(DEFAULT_WEBHOOK_URL, message_content)
        print("\n已发送钉钉信息\n")

    # 发送结果通知
    if finished_found:
        metrics=report(work_dir)
        # 解析复杂的metrics结构
        overall_score, categories = parse_metrics_data(metrics)

        # 构建分数展示文本
        score_text = f"    总体分数 : {overall_score:.4f}" if isinstance(overall_score,float) else f"总体分数: {overall_score}"

        category_text = []
        for cat_name, cat_score in categories.items():
            score_str = f"{cat_score:.4f}" if isinstance(cat_score, float) else str(cat_score)
            category_text.append(f"  - {cat_name}: {score_str}")

        # 合并所有文本
        metrics_text = "\n".join([score_text, "  类别分数:", *category_text])

        # 构建通知内容
        message_content = "\n".join([
            "docker eval 运行检测",
            " 运行正常结束",
            "  评估分数汇总:",
            metrics_text.replace("\n", "\n  ")
        ])
        print(message_content)
        send_post_request(DEFAULT_WEBHOOK_URL,message_content)
        print("\n已发送钉钉信息\n")

    return errors_found or finished_found


def main():
    """主函数"""
    # 检查是否有命令行参数
    if len(sys.argv) > 1:
        file_path = sys.argv[1]
        if not os.path.isfile(file_path):
            print(f"错误：文件 '{file_path}' 不存在\n")
            sys.exit(1)
    else:
        file_path = find_latest_log_file()
        print(f"日志文件: {file_path}")

    print(f"开始监控日志文件，每 {CHECK_INTERVAL / 60} 分钟检查一次\n")

    try:
        while True:
            print(f"检查时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            if extract_errors(file_path):
                print("\n监控程序已停止\n")
                break
            time.sleep(CHECK_INTERVAL)
    except KeyboardInterrupt:
        print("\n程序已停止")


if __name__ == "__main__":
    main()