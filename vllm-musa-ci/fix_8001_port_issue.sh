#!/bin/bash

# 解决8001端口(Qwen)频繁失效问题的方案

echo "🔧 8001端口频繁失效问题解决方案"
echo "========================================"

echo "📋 问题分析:"
echo "1. GPU内存不足 - Qwen需要38.34GB，但只有13.95GB可用"
echo "2. 资源竞争 - DeepSeek和Qwen同时争抢GPU资源"
echo "3. 启动时序 - Qwen启动时DeepSeek已占用大量内存"
echo ""

echo "🎯 解决方案:"
echo ""
echo "方案1: 降低Qwen内存使用 (推荐)"
echo "  - gpu-memory-utilization: 0.8 → 0.5"
echo "  - max-model-len: 8000 → 4000"
echo "  - tensor-parallel-size: 4 → 2"
echo ""

echo "方案2: 调整GPU分配"
echo "  - DeepSeek: GPU 0,1 → GPU 0"
echo "  - Qwen: GPU 2,3,4,5 → GPU 1,2,3"
echo ""

echo "方案3: 顺序启动 + 内存监控"
echo "  - 等待DeepSeek完全稳定后再启动Qwen"
echo "  - 增加内存检查和自动重试机制"
echo ""

echo "方案4: 添加服务监控和自动重启"
echo "  - 检测端口状态，自动重启失效服务"
echo "  - 实现健康检查和故障转移"

echo ""
echo "🔍 推荐实施顺序:"
echo "1. 立即调整Qwen内存配置(方案1)"
echo "2. 增加启动监控(方案3)"
echo "3. 实现服务监控(方案4)"
echo "4. 如问题持续，考虑GPU重分配(方案2)"
