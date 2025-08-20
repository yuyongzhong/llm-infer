# evalscope数据集缓存配置指南

## 配置位置总览

### 1. YAML配置文件 (推荐方式)
在 `config-qwen2.yaml` 和 `config-dsv2.yaml` 中配置：

```yaml
# ========== 精度评估配置 ==========
accuracy:
  # ... 其他配置 ...
  
  # 数据集缓存配置
  dataset_cache:
    enable: true                           # 是否启用数据集缓存优化
    cache_dir: "/root/.cache/modelscope/hub/datasets"  # 数据集缓存目录
    dataset_hub: "modelscope"              # 数据集来源Hub（modelscope或huggingface）
    mem_cache: true                        # 是否启用内存缓存
```

### 2. 环境变量设置
在 `run_all.sh` 中自动从YAML配置读取并设置：

```bash
# ========= 设置数据集缓存环境变量 ========= #
export DATASET_CACHE_ENABLE=$(yq e '.accuracy.dataset_cache.enable // true' "$CONFIG_FILE")
export DATASET_CACHE_DIR=$(yq e '.accuracy.dataset_cache.cache_dir // "/root/.cache/modelscope/hub/datasets"' "$CONFIG_FILE")
export DATASET_HUB=$(yq e '.accuracy.dataset_cache.dataset_hub // "modelscope"' "$CONFIG_FILE")
export MEM_CACHE=$(yq e '.accuracy.dataset_cache.mem_cache // true' "$CONFIG_FILE")

# ModelScope和HuggingFace环境变量
export MODELSCOPE_CACHE="/root/.cache/modelscope"
export HF_HOME="/root/.cache/huggingface"
```

### 3. TaskConfig代码配置
在 `evaluate_test.py` 中动态应用配置：

```python
task_cfg = TaskConfig(
    # ... 其他配置 ...
    
    # 数据集缓存配置（从配置文件读取）
    dataset_dir=dataset_cache_dir if dataset_cache_enable else None,
    dataset_hub=dataset_hub if dataset_cache_enable else "modelscope",
    mem_cache=mem_cache if dataset_cache_enable else False,
)
```

## 配置参数说明

| 参数 | 默认值 | 说明 |
|------|-------|------|
| `enable` | `true` | 是否启用数据集缓存优化 |
| `cache_dir` | `/root/.cache/modelscope/hub/datasets` | 数据集缓存目录路径 |
| `dataset_hub` | `modelscope` | 数据集来源Hub（modelscope/huggingface） |
| `mem_cache` | `true` | 是否启用内存缓存 |

## 缓存目录结构

```
/root/.cache/
├── modelscope/
│   └── hub/
│       └── datasets/
│           └── modelscope___ceval-exam/    # C-Eval 数据集缓存
│               ├── high_school_mathematics/
│               └── logic/
└── huggingface/
    └── modules/
        └── datasets_modules/
            └── datasets/
                └── modelscope--ceval-exam/  # HuggingFace 格式缓存
```

## 使用方法

### 1. 启用缓存（默认）
```yaml
dataset_cache:
  enable: true
```

### 2. 禁用缓存
```yaml
dataset_cache:
  enable: false
```

### 3. 自定义缓存目录
```yaml
dataset_cache:
  enable: true
  cache_dir: "/custom/cache/path"
```

### 4. 使用HuggingFace Hub
```yaml
dataset_cache:
  enable: true
  dataset_hub: "huggingface"
```

## 验证缓存状态

运行缓存检查脚本：
```bash
bash /mnt/vllm/yuyongzhong/llm-infer/setup_cache.sh
```

或在容器内检查：
```bash
docker exec vllm-test-0805 ls -la /root/.cache/modelscope/hub/datasets/
```

## 优化效果

- ✅ **首次运行**: 下载并缓存数据集
- ✅ **后续运行**: 直接使用缓存，启动更快
- ✅ **内存缓存**: 进一步加速数据加载
- ✅ **离线支持**: 缓存后可离线运行
- ✅ **配置灵活**: 可通过YAML文件控制
