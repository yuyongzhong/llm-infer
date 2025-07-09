import os
import re
import glob
from datetime import datetime


def get_latest_date_dir(base_dir: str) -> str:
    """获取指定目录下日期最新的子目录"""
    if not os.path.exists(base_dir):
        print(f"目录不存在: {base_dir}")
        return ""

    # 获取所有子目录并按日期排序
    date_dirs = [d for d in os.listdir(base_dir) if os.path.isdir(os.path.join(base_dir, d))]
    if not date_dirs:
        print(f"目录为空: {base_dir}")
        return ""

    # 尝试解析日期格式（假设目录名是日期格式）
    def parse_date(d):
        try:
            # 尝试常见的日期格式，根据实际情况调整
            return datetime.strptime(d, "%Y%m%d")
        except ValueError:
            # 如果不是日期格式，使用修改时间
            return datetime.fromtimestamp(os.path.getmtime(os.path.join(base_dir, d)))

    # 按日期排序，最新的在前
    date_dirs.sort(key=parse_date, reverse=True)
    return os.path.join(base_dir, date_dirs[0])


def get_file_names(dir_path: str) -> list:
    """获取指定目录下的文件名（按时间排序，排除最新的）"""
    if not os.path.exists(dir_path):
        print(f"目录不存在: {dir_path}")
        return []

    # 获取所有文件并按修改时间排序
    files = glob.glob(os.path.join(dir_path, "*"))
    files.sort(key=os.path.getmtime)

    # 排除最新的文件
    if len(files) <= 1:
        return []

    # 获取文件名并去除前缀
    file_names = [os.path.basename(f) for f in files[:-1]]
    file_names = [name.replace("ceval_", "") for name in file_names if name.startswith("ceval_")]
    file_names = [os.path.splitext(name)[0] for name in file_names]
    return file_names


def update_subset_list(ceval_path: str, items_to_remove: list) -> bool:
    """更新ceval.py文件中的subset_list列表"""
    if not os.path.exists(ceval_path):
        print(f"文件不存在: {ceval_path}")
        return False

    try:
        # 读取文件内容
        with open(ceval_path, 'r', encoding='utf-8') as f:
            content = f.read()

        # 使用正则表达式找到subset_list
        pattern = r'(subset_list\s*=\s*\[\s*)(.*?)(\s*\])'
        match = re.search(pattern, content, re.DOTALL)

        if not match:
            print("未找到subset_list定义")
            return False

        # 提取当前列表内容
        current_items = match.group(2)
        lines = [line.strip() for line in current_items.split('\n')]

        # 过滤掉需要移除的项
        new_lines = []
        for line in lines:
            # 提取列表项（处理引号）
            item_match = re.search(r'[\'"](.*?)[\'"]', line)
            if item_match:
                item = item_match.group(1)
                if item in items_to_remove:
                    continue
            new_lines.append(line)

        # 构建新的列表内容
        new_content = content[:match.start(2)] + '\n'.join(new_lines) + content[match.end(2):]

        # 写回文件
        with open(ceval_path, 'w', encoding='utf-8') as f:
            f.write(new_content)

        print(f"已更新subset_list，移除了 {len(items_to_remove)} 个项")
        return True

    except Exception as e:
        print(f"更新文件时出错: {e}")
        return False


def main():
    current_dir = os.getcwd()
    outputs_dir = os.path.join(current_dir, "outputs")

    # 获取最新日期目录
    latest_date_dir = get_latest_date_dir(outputs_dir)
    if not latest_date_dir:
        return

    # 获取预测文件路径
    predictions_dir = os.path.join(latest_date_dir, "predictions", "deepseek")

    # 获取文件名称列表
    file_names = get_file_names(predictions_dir)
    if not file_names:
        print("没有需要处理的文件")
        return

    print(f"需要从subset_list中移除的项: {file_names}")

    # 更新ceval.py文件
    ceval_path = os.path.join(current_dir, "tasks", "ceval.py")
    if update_subset_list(ceval_path, file_names):
        print("操作完成")
    else:
        print("操作失败")


if __name__ == "__main__":
    main()