# 📚 技术文档索引

## 🎯 核心功能文档

### 🔧 缓存优化
- **[CACHE_CONFIG_GUIDE.md](./CACHE_CONFIG_GUIDE.md)** - 数据集缓存配置用户指南
  - 配置方法和参数说明
  - YAML配置示例
  - 使用教程

- **[CACHE_OPTIMIZATION.md](./CACHE_OPTIMIZATION.md)** - 缓存优化技术原理
  - 技术实现细节
  - 性能优化效果
  - 高级优化策略

### 🐛 调试与监控
- **[vllm-musa-ci/VERBOSE参数完整适配总结.md](./vllm-musa-ci/VERBOSE参数完整适配总结.md)** - VERBOSE调试参数完整实现
  - Jenkins Pipeline配置
  - 脚本调试功能
  - 使用方法说明

### 📱 通知系统
- **[test/钉钉通知优化说明.md](./test/钉钉通知优化说明.md)** - 钉钉通知系统优化
  - 通知格式美化
  - 模型检测功能
  - 错误提示优化

### 🔍 问题诊断
- **[vllm-musa-ci/8001端口问题分析报告.md](./vllm-musa-ci/8001端口问题分析报告.md)** - 8001端口服务问题分析
- **[vllm-musa-ci/错误处理机制改进总结.md](./vllm-musa-ci/错误处理机制改进总结.md)** - 错误处理机制改进

## 🚀 快速上手

### 新用户推荐阅读顺序
1. **[README.md](./README.md)** - 项目总览
2. **[CACHE_CONFIG_GUIDE.md](./CACHE_CONFIG_GUIDE.md)** - 缓存配置
3. **[test/钉钉通知优化说明.md](./test/钉钉通知优化说明.md)** - 通知设置
4. **[vllm-musa-ci/VERBOSE参数完整适配总结.md](./vllm-musa-ci/VERBOSE参数完整适配总结.md)** - 调试功能

### 开发者推荐阅读顺序
1. **[CACHE_OPTIMIZATION.md](./CACHE_OPTIMIZATION.md)** - 技术架构
2. **[vllm-musa-ci/错误处理机制改进总结.md](./vllm-musa-ci/错误处理机制改进总结.md)** - 错误处理
3. **[vllm-musa-ci/8001端口问题分析报告.md](./vllm-musa-ci/8001端口问题分析报告.md)** - 故障排查

## 📋 文档维护说明

### 最近更新
- ✅ 2025-08-20: 删除重复的VERBOSE环境变量使用说明.md
- ✅ 2025-08-20: 优化CACHE_OPTIMIZATION.md技术内容
- ✅ 2025-08-20: 统一缓存配置到所有config文件

### 文档职责分工
- **用户指南类**: 重点讲解配置和使用方法
- **技术说明类**: 重点讲解实现原理和架构
- **问题诊断类**: 重点记录问题分析和解决方案
- **总结报告类**: 重点记录开发过程和完成情况

### 避免重复原则
- 每个文档应有明确的目标受众
- 相同内容不在多个文档中重复
- 通过交叉引用避免内容冗余
