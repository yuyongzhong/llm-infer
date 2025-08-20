#!/bin/bash

# 钉钉通知功能测试脚本

echo "🔧 开始测试钉钉通知功能..."

# 测试修复后的send_post_request函数
docker exec vllm-test-0805 python3 -c "
import sys
sys.path.append('/mnt/vllm/yuyongzhong/llm-infer/test')
from acc_test.scripts.tools import send_post_request, acc_log_monitor
from datetime import datetime

webhook_url = 'https://oapi.dingtalk.com/robot/send?access_token=9ad9373a15c82ad31bca9da0d92f8602432b79c3ae5975bc6160cf9ab5d82b49'

print('🔧 测试场景1: 基础docker关键词消息')
test_message1 = f'''📋 docker评估通知测试
📅 时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
🎯 测试目的: 验证修复后的钉钉通知功能
✅ 如果收到此消息，说明基础功能正常'''

send_post_request(webhook_url, test_message1)

print('\n🔧 测试场景2: 模拟eval完成通知')
test_message2 = f'''📋 Docker Eval 运行检测
✅ 运行正常结束
📈 评估分数汇总:
📊 总体分数: 0.6500 (65.00%)
📋 类别分数详情:
   • STEM: 0.7000 (70.00%)
   • Humanities: 0.6000 (60.00%)
📄 详细报告文件: test_report.json
🕐 测试时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}'''

send_post_request(webhook_url, test_message2)

print('\n🔧 测试场景3: 模拟错误通知')
test_message3 = f'''📋 docker eval 运行检测
❌ 运行出现异常
🚨 检测出Error/Failed 错误详情见日志文件
📁 eval日志文件: /path/to/test.log
🕐 错误时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}'''

send_post_request(webhook_url, test_message3)

print('\n✅ 钉钉通知功能测试完成')
"

echo "🎉 测试完成！请检查钉钉群是否收到了3条测试消息。"
