#!/bin/bash

# ModelScope和evalscope数据集缓存优化脚本

echo "🚀 设置evalscope数据集缓存优化..."

# 设置ModelScope缓存目录
export MODELSCOPE_CACHE="/root/.cache/modelscope"
export HF_HOME="/root/.cache/huggingface"

# 确保缓存目录存在
mkdir -p /root/.cache/modelscope/hub/datasets
mkdir -p /root/.cache/huggingface

# 显示当前缓存状态
echo "📁 缓存目录设置:"
echo "   MODELSCOPE_CACHE: $MODELSCOPE_CACHE"
echo "   HF_HOME: $HF_HOME"

# 检查已有的数据集缓存
echo ""
echo "📊 当前数据集缓存状态:"
if [ -d "/root/.cache/modelscope/hub/datasets" ]; then
    echo "   ModelScope数据集缓存:"
    ls -la /root/.cache/modelscope/hub/datasets/ 2>/dev/null | grep -E "(ceval|mmlu|math)" || echo "     无相关数据集缓存"
fi

if [ -d "/root/.cache/huggingface" ]; then
    echo "   HuggingFace数据集缓存:"
    find /root/.cache/huggingface -name "*ceval*" -o -name "*mmlu*" 2>/dev/null | head -5 || echo "     无相关数据集缓存"
fi

echo ""
echo "✅ 缓存环境设置完成！"
echo "💡 提示: 现在evalscope将优先使用本地缓存，避免重复下载数据集"
