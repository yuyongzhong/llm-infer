#!/bin/bash

echo "🔍 验证数据集缓存配置是否统一..."
echo ""

# 检查的配置文件列表
CONFIG_FILES=(
    "config.yaml"
    "config-dsv2.yaml" 
    "config-qwen2.yaml"
    "../build-test-images/llm-infer/test/config.yaml"
    "../build-test-images/llm-infer/test/config-dsv2.yaml"
    "../build-test-images/llm-infer/test/config-qwen2.yaml"
)

echo "📋 检查的配置文件:"
for config in "${CONFIG_FILES[@]}"; do
    if [ -f "$config" ]; then
        echo "✅ $config"
    else
        echo "❌ $config (不存在)"
    fi
done
echo ""

# 检查每个配置文件的dataset_cache配置
for config in "${CONFIG_FILES[@]}"; do
    if [ -f "$config" ]; then
        echo "📄 $config:"
        echo "  enable: $(yq e '.accuracy.dataset_cache.enable // "未设置"' "$config")"
        echo "  cache_dir: $(yq e '.accuracy.dataset_cache.cache_dir // "未设置"' "$config")"
        echo "  dataset_hub: $(yq e '.accuracy.dataset_cache.dataset_hub // "未设置"' "$config")"
        echo "  mem_cache: $(yq e '.accuracy.dataset_cache.mem_cache // "未设置"' "$config")"
        echo ""
    fi
done

echo "🎯 验证完成！如果所有配置项都显示相同值，则配置统一成功。"
