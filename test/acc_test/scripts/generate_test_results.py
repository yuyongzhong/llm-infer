#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成测试结果的脚本

注意：此脚本处理来自evalscope的日志文件，这些日志可能包含：
1. 中文测试数据集内容（如C-Eval）
2. 不同机器环境下可能产生的编码差异
3. 第三方库输出的多种字符编码

为确保兼容性，脚本会自动尝试多种编码方式读取文件。
"""

import json
import os
import re
import argparse
import yaml
from datetime import datetime
from typing import Dict, List, Any

def load_config(config_path: str) -> Dict[str, Any]:
    """加载配置文件"""
    with open(config_path, "r", encoding="utf-8", errors="ignore") as f:
        config = yaml.safe_load(f)
    # 强制将 software_version 转为字符串（预防八进制）
    base_info = config.get('basic', {}).get('base_info', {})
    if 'software_version' in base_info:
        base_info['software_version'] = str(base_info['software_version'])
    # 只在详细模式下显示调试信息
    if os.environ.get('VERBOSE', '').lower() == 'true':
        print(f"调试: 完整加载的 config: {config}")
    return config

def parse_benchmark_md(md_path: str) -> List[Dict[str, Any]]:
    """解析性能测试的Markdown结果文件"""
    if not md_path or not os.path.exists(md_path):
        print(f"⚠️ 性能测试 markdown 文件不存在或路径为空: {md_path}")
        return []
        
    results = []
    with open(md_path, "r", encoding="utf-8", errors="ignore") as f:
        lines = f.readlines()[2:]  # 跳过表头
        for line in lines:
            if line.strip():
                parts = [p.strip() for p in line.split('|')[1:-1]]
                results.append({
                    "timestamp": parts[0],
                    "concurrency": int(parts[2]),
                    "input_tokens": int(parts[3]),
                    "output_tokens": int(parts[4]),
                    "expected_input": int(parts[5]),
                    "expected_output": int(parts[6]),
                    "avg_input": float(parts[7]),
                    "avg_output": float(parts[8]),
                    "total_time": float(parts[9]),
                    "req_throughput": float(parts[10]),
                    "output_throughput": float(parts[11]),
                    "total_throughput": float(parts[12]),
                    "avg_ttft": float(parts[13]),
                    "p99_ttft": float(parts[14])
                })
    return results

def parse_accuracy_log(log_path: str, config: Dict[str, Any]) -> List[Dict[str, Any]]:
    """解析精度测试日志文件"""
    if not log_path or not os.path.exists(log_path):
        print(f"⚠️ 精度测试日志文件不存在或路径为空: {log_path}")
        return []
        
    accuracy_results = []
    
    # 尝试不同的编码方式读取文件，以处理不同机器环境下的编码问题
    encodings = ['utf-8', 'utf-8-sig', 'latin-1', 'cp1252', 'iso-8859-1', 'gbk', 'gb2312']
    log_content = None
    used_encoding = None
    
    for encoding in encodings:
        try:
            with open(log_path, "r", encoding=encoding) as f:
                log_content = f.read()
                used_encoding = encoding
                break
        except (UnicodeDecodeError, UnicodeError):
            continue
    
    if log_content is None:
        # 最后尝试用二进制模式读取，然后尝试解码
        try:
            with open(log_path, "rb") as f:
                raw_content = f.read()
                # 尝试用 chardet 检测编码（如果可用）
                try:
                    import chardet
                    detected = chardet.detect(raw_content)
                    if detected['encoding']:
                        log_content = raw_content.decode(detected['encoding'], errors='ignore')
                        used_encoding = detected['encoding']
                        print(f"✅ 使用chardet检测到编码: {detected['encoding']} (置信度: {detected['confidence']:.2f})")
                except ImportError:
                    # 如果没有chardet，使用errors='replace'强制解码
                    log_content = raw_content.decode('utf-8', errors='replace')
                    used_encoding = 'utf-8 (with replacement)'
                    print(f"⚠️ 无法确定编码，使用UTF-8并替换无效字符")
        except Exception as e:
            print(f"❌ 读取日志文件失败: {e}")
            return []
    
    if used_encoding:
        print(f"✅ 成功使用 {used_encoding} 编码读取日志文件: {log_path}")

        # 1. 从日志中提取报告文件路径
        report_path_match = re.search(
            r"Dump report to: (\./outputs/[^\s]+\.json)",
            log_content
        )

        if report_path_match:
            # 这段代码的意思是：可能日志中会有多个“Dump report to:”的匹配结果，
            # 所以需要用findall获取所有匹配到的报告文件路径，然后遍历处理每一个路径。
            report_paths = re.findall(r"Dump report to: (\./outputs/[^\s]+\.json)", log_content)
            for report_abs_path in report_paths:
                print(f"报告文件路径: {report_abs_path}")
                if os.path.exists(report_abs_path):
                    with open(report_abs_path, "r", encoding="utf-8", errors="ignore") as report_file:
                        report_data = json.load(report_file)
                        accuracy_results.append(report_data)
                else:
                    print(f"警告: 报告文件不存在: {report_abs_path}")
            print(f"报告文件路径: {report_abs_path}")
        else:
            print("警告: 未找到报告文件路径")

    return accuracy_results


def generate_test_results(
    benchmark_results: List[Dict[str, Any]],
    accuracy_results: List[Dict[str, Any]],
    config: Dict[str, Any],
    benchmark_md_path: str,
    acc_log_path: str
) -> Dict[str, Any]:
    """生成测试结果JSON结构"""
    return {
        "project_id": config.get("basic", {}).get("log_info", "default_id"),
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "model_name": config.get("basic", {}).get("model_name", "deepseek"),
        "run_mode": config.get("basic", {}).get("run_mode", "bench-then-acc"),
        "base_info": config.get("basic", {}).get("base_info", {}),
        "tests": [
            {
                "test_type": "benchmark",
                "results": benchmark_results,
                "log_path": benchmark_md_path
            },
            {
                "test_type": "accuracy",
                "datasets": accuracy_results,
                "log_path": acc_log_path
            }
        ]
    }

def main():
    """主函数"""
    # 解析命令行参数
    parser = argparse.ArgumentParser(description="Generate standardized test results JSON")
    parser.add_argument("--output-dir", required=True, help="Output directory for JSON")
    parser.add_argument("--acc-log", required=True, help="Path to accuracy log file")
    parser.add_argument("--benchmark-md", required=True, help="Path to benchmark MD file")
    parser.add_argument("--config", default="llm-infer/test/config.yaml", help="Path to config.yaml")
    args = parser.parse_args()

    # 加载配置
    config = load_config(args.config)

    # 直接从配置文件获取 base_info（简化逻辑）
    base_info = config.get('basic', {}).get('base_info', {})

    # 更新配置中的 base_info（如果需要）
    if 'basic' not in config:
        config['basic'] = {}
    config['basic']['base_info'] = base_info

    # 打印调试信息（增强版）
    print(f"使用的配置文件: {args.config}")
    print(f"加载的完整 base_info: {base_info}")  # 新增：打印整个 base_info
    print(f"最终使用的 software_version 值: {base_info.get('software_version')}")

    # 创建结果目录
    results_dir = os.path.join(args.output_dir, "results")
    os.makedirs(results_dir, exist_ok=True)

    # 时间戳
    timestamp = datetime.now().strftime('%Y%m%d_%H%M')

    # 解析性能测试结果
    benchmark_results = parse_benchmark_md(args.benchmark_md)

    # 解析精度测试结果
    accuracy_results = parse_accuracy_log(args.acc_log, config)

    # 生成测试结果JSON
    data = generate_test_results(
        benchmark_results,
        accuracy_results,
        config,
        args.benchmark_md,
        args.acc_log
    )
    
    # 只在详细模式下显示调试信息
    if os.environ.get('VERBOSE', '').lower() == 'true':
        print(f"调试: 生成的 data 中的 base_info: {data.get('base_info')}")
        print(f"调试: 生成的 data 中的 software_version: {data.get('base_info', {}).get('software_version')}")

    # 保存JSON文件
    json_path = os.path.join(results_dir, f"test_results_{timestamp}.json")
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=4)

    print(f"✅ JSON文件已生成：{json_path}")

if __name__ == "__main__":
    main()
