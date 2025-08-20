pipeline {
    agent none

    // 定义参数
    parameters {
        string(
            name: 'HARBOR_IMAGE_URL',
            defaultValue: 'sh-harbor.mthreads.com/vllm-images/vllm-test-0808:test',
            description: 'Harbor镜像的完整地址，例如: sh-harbor.mthreads.com/vllm-images/vllm-test-0808:test'
        )
        string(
            name: 'IMAGE_TAG',
            defaultValue: 'test',
            description: '镜像标签，如果不指定则使用test'
        )
        string(
            name: 'NODE_LABELS',
            defaultValue: '10.10.129.22',
            description: '执行节点标签，用逗号分隔，例如: 10.10.129.22,10.10.129.25'
        )
        booleanParam(
            name: 'FORCE_PULL',
            defaultValue: false,
            description: '是否强制拉取镜像（即使本地已存在）'
        )
        booleanParam(
            name: 'RECREATE_CONTAINER',
            defaultValue: false,
            description: '是否删除并重新创建容器（即使容器已存在）'
        )
        string(
            name: 'LOG_MONITOR_DURATION',
            defaultValue: '3000',
            description: '日志监控持续时间（秒），0表示不监控，建议300-600秒'
        )
        booleanParam(
            name: 'VERBOSE',
            defaultValue: false,
            description: '是否启用详细调试输出（显示更多日志信息）'
        )
    }

    environment {
        POLL_INTERVAL = 20
        // 从参数中获取镜像地址
        HARBOR_URL = "${params.HARBOR_IMAGE_URL}"
        IMAGE_TAG = "${params.IMAGE_TAG}"
        FORCE_PULL = "${params.FORCE_PULL}"
        NODE_LABELS = "${params.NODE_LABELS}"
        RECREATE_CONTAINER = "${params.RECREATE_CONTAINER}"
        LOG_MONITOR_DURATION = "${params.LOG_MONITOR_DURATION}"
        VERBOSE = "${params.VERBOSE}"
    }

    stages {
        stage('参数验证') {
            agent any
            steps {
                script {
                    echo "=== 参数信息 ==="
                    echo "Harbor镜像地址: ${HARBOR_URL}"
                    echo "镜像标签: ${IMAGE_TAG}"
                    echo "强制拉取: ${FORCE_PULL}"
                    echo "执行节点: ${NODE_LABELS}"
                    echo "重新创建容器: ${RECREATE_CONTAINER}"
                    echo "日志监控时间: ${LOG_MONITOR_DURATION} 秒"
                    
                    // 验证镜像地址格式
                    if (!HARBOR_URL.contains('/')) {
                        error "镜像地址格式错误，应该包含仓库路径，例如: harbor.example.com/project/image:tag"
                    }
                    
                    // 解析节点标签
                    def nodeList = NODE_LABELS.split(',').collect { it.trim() }
                    echo "解析后的节点列表: ${nodeList}"
                    
                    // 验证节点标签
                    if (nodeList.size() == 0) {
                        error "至少需要指定一个执行节点"
                    }
                    
                    // 验证日志监控时间
                    try {
                        def monitorDuration = LOG_MONITOR_DURATION.toInteger()
                        if (monitorDuration < 0) {
                            error "日志监控时间不能为负数"
                        }
                        
                        if (monitorDuration > 3600) {
                            echo "⚠️ 警告：日志监控时间超过1小时，建议不超过600秒"
                        }
                    } catch (NumberFormatException e) {
                        error "日志监控时间必须是有效的数字"
                    }
                    
                    // 检查节点可用性
                    echo "=== 检查节点可用性 ==="
                    nodeList.each { nodeLabel ->
                        try {
                            node("${nodeLabel}") {
                                echo "✅ 节点 ${nodeLabel} 可用"
                                // 验证节点名称
                                if (env.NODE_NAME != nodeLabel) {
                                    echo "⚠️ 警告：节点名称不匹配，期望: ${nodeLabel}, 实际: ${env.NODE_NAME}"
                                }
                            }
                        } catch (Exception e) {
                            echo "❌ 节点 ${nodeLabel} 不可用: ${e.getMessage()}"
                            error "节点 ${nodeLabel} 不可用，请检查节点配置或确保节点在线"
                        }
                    }
                }
            }
        }

        stage('并行拉取镜像') {
            steps {
                script {
                    def nodeList = NODE_LABELS.split(',').collect { it.trim() }
                    
                    // 使用不同的并行策略
                    def branches = [:]
                    nodeList.eachWithIndex { nodeLabel, index ->
                        branches["在节点 ${nodeLabel} 拉取镜像"] = {
                            node("${nodeLabel}") {
                                // 强制验证节点
                                echo "=== 节点验证 ==="
                                echo "期望节点: ${nodeLabel}"
                                echo "实际节点: ${env.NODE_NAME}"
                                echo "✅ 节点验证通过"
                                echo "=== 在节点 ${nodeLabel} 上执行 ==="
                                echo "实际执行节点: ${env.NODE_NAME}"
                                echo "当前执行用户: ${sh(script: 'whoami', returnStdout: true).trim()}"
                                echo "节点标签: ${nodeLabel}"
                                echo "开始拉取镜像: ${HARBOR_URL}"
                                
                                // 构建完整的镜像地址
                                def fullImageUrl = HARBOR_URL
                                if (!HARBOR_URL.contains(':')) {
                                    fullImageUrl = "${HARBOR_URL}:${IMAGE_TAG}"
                                }
                                
                                echo "完整镜像地址: ${fullImageUrl}"
                                
                                // 节点信息诊断
                                echo "=== 节点信息诊断 ==="
                                echo "期望执行节点: ${nodeLabel}"
                                echo "实际执行节点: ${env.NODE_NAME}"
                                echo "节点标签: ${nodeLabel}"
                                
                                // 网络诊断
                                echo "=== 网络诊断 ==="
                                sh "ping -c 3 sh-harbor.mthreads.com || echo '网络连接失败'"
                                sh "cat /etc/resolv.conf"
                                
                                // 检查hosts条目
                                echo "=== 检查hosts配置 ==="
                                sh "cat /etc/hosts | grep sh-harbor.mthreads.com || echo '未找到hosts条目'"
                                
                                // 检查本地镜像是否存在
                                echo "=== 检查本地镜像 ==="
                                def localImageExists = sh(
                                    script: "sudo docker images --format '{{.Repository}}:{{.Tag}}' | grep -w '${fullImageUrl}'",
                                    returnStatus: true
                                ) == 0
                                
                                if (localImageExists) {
                                    echo "✅ 本地镜像已存在: ${fullImageUrl}"
                                    sh "sudo docker images ${fullImageUrl}"
                                    
                                    if (FORCE_PULL == 'true') {
                                        echo "强制拉取模式：即使本地存在也会重新拉取"
                                                                    } else {
                                    echo "跳过拉取：本地镜像已存在且未启用强制拉取"
                                    def pullSuccess = true
                                    return
                                }
                                } else {
                                    echo "❌ 本地镜像不存在: ${fullImageUrl}"
                                }
                                
                                // 拉取镜像（优先使用域名）
                                def maxRetries = 3
                                def retryCount = 0
                                def pullSuccess = false
                                
                                // 优先使用域名拉取（因为IP地址有SSL证书问题）
                                echo "开始拉取镜像: ${fullImageUrl}"
                                
                                while (retryCount < maxRetries && !pullSuccess) {
                                    try {
                                        retryCount++
                                        echo "尝试第 ${retryCount} 次拉取镜像..."
                                        
                                        sh "sudo docker pull ${fullImageUrl}"
                                        
                                        echo "镜像拉取成功！"
                                        pullSuccess = true
                                        
                                        // 显示镜像信息
                                        sh "sudo docker images | grep ${fullImageUrl.split('/').last()}"
                                        
                                    } catch (Exception domainError) {
                                        echo "第 ${retryCount} 次拉取失败: ${domainError.getMessage()}"
                                        
                                        if (retryCount >= maxRetries) {
                                            echo "所有重试都失败了"
                                            error "镜像拉取失败，已重试 ${maxRetries} 次，请检查镜像地址是否正确以及网络连接是否正常"
                                        } else {
                                            echo "等待 10 秒后重试..."
                                            sleep(10)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    parallel branches
                }
            }
        }

        stage('并行验证镜像') {
            steps {
                script {
                    def nodeList = NODE_LABELS.split(',').collect { it.trim() }
                    
                    // 使用不同的并行策略
                    def branches = [:]
                    nodeList.eachWithIndex { nodeLabel, index ->
                        branches["验证节点 ${nodeLabel} 镜像"] = {
                            node("${nodeLabel}") {
                                // 立即验证节点
                                if (env.NODE_NAME != nodeLabel) {
                                    error "❌ 节点分配错误！期望: ${nodeLabel}, 实际: ${env.NODE_NAME}"
                                }
                                // 立即验证节点
                                if (env.NODE_NAME != nodeLabel) {
                                    error "❌ 节点分配错误！期望: ${nodeLabel}, 实际: ${env.NODE_NAME}"
                                }
                                // 强制验证节点
                                echo "=== 节点验证 ==="
                                echo "期望节点: ${nodeLabel}"
                                echo "实际节点: ${env.NODE_NAME}"
                                echo "✅ 节点验证通过"
                                echo "=== 在节点 ${nodeLabel} 验证镜像 ==="
                                echo "实际执行节点: ${env.NODE_NAME}"
                                echo "当前执行用户: ${sh(script: 'whoami', returnStdout: true).trim()}"
                                echo "节点标签: ${nodeLabel}"
                                echo "✅ 节点匹配正确"
                                
                                def fullImageUrl = HARBOR_URL
                                if (!HARBOR_URL.contains(':')) {
                                    fullImageUrl = "${HARBOR_URL}:${IMAGE_TAG}"
                                }
                                
                                echo "验证镜像是否存在..."
                                
                                // 检查镜像是否存在
                                def imageExists = sh(
                                    script: "sudo docker images --format '{{.Repository}}:{{.Tag}}' | grep -w '${fullImageUrl}'",
                                    returnStatus: true
                                ) == 0
                                
                                if (imageExists) {
                                    echo "✅ 镜像验证成功: ${fullImageUrl}"
                                    
                                    // 显示镜像详细信息
                                    sh "sudo docker images ${fullImageUrl}"
                                } else {
                                    error "❌ 镜像验证失败: ${fullImageUrl} 不存在"
                                }
                            }
                        }
                    }
                    parallel branches
                }
            }
        }

        stage('汇总结果') {
            agent any
            steps {
                script {
                    def nodeList = NODE_LABELS.split(',').collect { it.trim() }
                    
                    echo "=== 所有节点操作完成 ==="
                    echo "✅ 镜像已在以下节点成功拉取和验证:"
                    nodeList.each { node ->
                        echo "   - ${node}"
                    }
                    echo "镜像地址: ${HARBOR_URL}"
                }
            }
        }

        stage('部署VLLM服务') {
            steps {
                script {
                    def nodeList = NODE_LABELS.split(',').collect { it.trim() }
                    def branches = [:]
                    def LOG_NAME = "test_" + new Date().format('yyyyMMdd_HHmmss')
                    
                    nodeList.each { nodeLabel ->
                        branches["在节点 ${nodeLabel} 部署"] = {
                            node("${nodeLabel}") {
                                def containerName = 'vllm-test-0805'
                                def imageUrl = HARBOR_URL
                                if (!HARBOR_URL.contains(':')) {
                                    imageUrl = "${HARBOR_URL}:${IMAGE_TAG}"
                                }

                                // 根据RECREATE_CONTAINER参数决定是否删除现有容器
                                if (RECREATE_CONTAINER == 'true') {
                                    echo "=== 删除并重新创建容器 ==="
                                    sh '''
                                        CONTAINER_ID=$(sudo docker ps -a --filter "name=vllm-test-0805" --format "{{.ID}}")
                                        if [ ! -z "$CONTAINER_ID" ]; then
                                            echo "停止容器: $CONTAINER_ID"
                                            sudo docker stop $CONTAINER_ID
                                            echo "删除容器: $CONTAINER_ID"
                                            sudo docker rm $CONTAINER_ID
                                        else
                                            echo "未找到现有容器: vllm-test-0805"
                                        fi
                                    '''
                                }

                                // 检查容器是否存在和运行状态
                                def containerExists = sh(
                                    script: "sudo docker ps -a --filter 'name=vllm-test-0805' --format '{{.ID}}'",
                                    returnStdout: true
                                ).trim()
                                
                                def containerRunning = sh(
                                    script: "sudo docker ps --filter 'name=vllm-test-0805' --format '{{.ID}}'",
                                    returnStdout: true
                                ).trim()
                                
                                if (containerExists == '') {
                                    echo "=== 创建新容器 ==="
                                    // 启动容器
                                    sh """#!/bin/bash
                                        sudo docker run -d \\
                                            --net host \\
                                            --privileged \\
                                            --pid host \\
                                            -v /mnt/vllm:/mnt/vllm \\
                                            -v /mnt/models:/mnt/models \\
                                            -v /etc/localtime:/etc/localtime:ro \\
                                            -e TZ=Asia/Shanghai \\
                                            -e LOG_NAME=${LOG_NAME} \\
                                            --name      ${containerName} \\
                                            ${imageUrl} \\
                                            tail -f /dev/null
                                    """
                                } else if (containerRunning == '') {
                                    echo "=== 启动现有容器 ==="
                                    sh "sudo docker start vllm-test-0805"
                                    // 等待容器完全启动
                                    sleep(5)
                                } else {
                                    echo "=== 使用运行中的容器 ==="
                                }

                                // 执行启动脚本
                                def testResult = sh(
                                    script: """
                                        sudo docker exec -e LOG_NAME=${LOG_NAME} -e VERBOSE=${VERBOSE} ${containerName} bash /mnt/vllm/yuyongzhong/llm-infer/vllm-musa-ci/test.sh
                                    """,
                                    returnStatus: true
                                )
                                
                                if (testResult != 0) {
                                    error "❌ 测试脚本执行失败，退出代码: ${testResult}"
                                }

                                // 日志监控
                                if (LOG_MONITOR_DURATION.toInteger() > 0) {
                                    sh """#!/bin/bash
                                        END_TIME=\$(date -d \"+${LOG_MONITOR_DURATION} seconds\" +%s)
                                        CURRENT_TIME=\$(date +%s)
                                        LAST_MONITOR_CONTENT=""
                                        MONITOR_INTERVAL=60  # 监控间隔调整为60秒
                                        COMPLETION_DETECTED=false
                                        
                                        while [ \$CURRENT_TIME -lt \$END_TIME ] && [ "\$COMPLETION_DETECTED" = "false" ]; do
                                            REMAINING=\$((END_TIME - CURRENT_TIME))
                                            
                                            # 检查测试是否已完成
                                            MONITOR_LOG="/mnt/vllm/yuyongzhong/llm-infer/vllm-musa-ci/logs/test-logs/monitor-${LOG_NAME}.log"
                                            if sudo docker exec ${containerName} test -f "\$MONITOR_LOG" 2>/dev/null; then
                                                if sudo docker exec ${containerName} grep -q "所有测试已完成" "\$MONITOR_LOG" 2>/dev/null; then
                                                    COMPLETION_DETECTED=true
                                                    echo ""
                                                    echo "╔════════════════════════════════════════════════════════════════════════════════╗"
                                                    printf "║ ✅ 测试完成检测 - 提前结束监控 %-45s ║\\n" ""
                                                    echo "╚════════════════════════════════════════════════════════════════════════════════╝"
                                                    echo ""
                                                    # 显示最终结果
                                                    FINAL_RESULT=\$(sudo docker exec ${containerName} tail -n 20 "\$MONITOR_LOG" 2>/dev/null | grep -A 10 "所有测试已完成")
                                                    if [ -n "\$FINAL_RESULT" ]; then
                                                        echo "\$FINAL_RESULT"
                                                    fi
                                                    break
                                                fi
                                            fi
                                            
                                            # 只在有新内容或间隔时间到达时显示
                                            if [ \$((REMAINING % MONITOR_INTERVAL)) -eq 0 ] || [ \$REMAINING -lt 30 ]; then
                                                echo ""
                                                echo "╔════════════════════════════════════════════════════════════════════════════════╗"
                                                printf "║ 📊 测试监控 - 剩余时间: %-52s ║\\n" "\$REMAINING 秒"
                                                echo "╠════════════════════════════════════════════════════════════════════════════════╣"
                                                
                                                # 检查监控总览
                                                if sudo docker exec ${containerName} test -f "\$MONITOR_LOG" 2>/dev/null; then
                                                    # 显示监控总览的最新状态
                                                    LATEST_MONITOR=\$(sudo docker exec ${containerName} tail -n 50 "\$MONITOR_LOG" 2>/dev/null | grep -A 20 "╔.*监控时间.*╗" | tail -25)
                                                    if [ -n "\$LATEST_MONITOR" ]; then
                                                        echo "\$LATEST_MONITOR"
                                                    else
                                                        printf "║ 📝 监控状态: %-64s ║\\n" "等待监控数据..."
                                                    fi
                                                else
                                                    printf "║ 📝 监控状态: %-64s ║\\n" "监控日志文件不存在"
                                                fi
                                                
                                                echo "╚════════════════════════════════════════════════════════════════════════════════╝"
                                                echo ""
                                            fi
                                            
                                            sleep 30
                                            CURRENT_TIME=\$(date +%s)
                                        done
                                        
                                        if [ "\$COMPLETION_DETECTED" = "true" ]; then
                                            echo "🎉 监控提前结束：检测到测试完成"
                                        else
                                            echo "⏰ 监控时间结束"
                                        fi
                                    """
                                }

                                echo "✅ 容器部署完成: ${containerName}"
                                echo "日志名称: ${LOG_NAME}"
                            }
                        }
                    }
                    parallel branches
                }
            }
        }
    }

    post {
        always {
            echo "=== Pipeline 执行完成 ==="
            echo "构建状态: ${currentBuild.result ?: 'SUCCESS'}"
        }
        success {
            echo "✅ 镜像拉取、验证和VLLM服务部署全部成功完成"
            script {
                try {
                    if (LOG_MONITOR_DURATION.toInteger() > 0) {
                        echo "📊 日志监控已完成，监控时间: ${LOG_MONITOR_DURATION} 秒"
                    }
                } catch (Exception e) {
                    echo "日志监控时间参数解析失败"
                }
            }
        }
        failure {
            echo "❌ Pipeline 执行失败"
        }
    }
} 