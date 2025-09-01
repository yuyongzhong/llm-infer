pipeline {
    agent none

    parameters {

        string(name: 'SERVICE_HARBOR_IMAGE_URL', defaultValue: 'sh-harbor.mthreads.com/mcctest/vllm-musa-s4000:20250829-78', description: 'Harbor镜像的完整地址')
        string(name: 'SERVICE_IMAGE_TAG', defaultValue: 'v0.8.4-release', description: '镜像标签')
        string(name: 'SERVICE_NODE_LABELS', defaultValue: '10.10.129.22', description: '执行节点标签')
        booleanParam(name: 'SERVICE_FORCE_PULL', defaultValue: false, description: '是否强制拉取镜像')
        string(name: 'SERVICE_LOG_MONITOR_DURATION', defaultValue: '300', description: '日志监控持续时间（秒）')

 
        booleanParam(name: 'IS_TEST', defaultValue: true, description: '是否自动测试')

        string(
            name: 'TEST_HARBOR_IMAGE_URL',
            defaultValue: 'sh-harbor.mthreads.com/vllm-images/vllm-test-0808:test',
            description: 'Harbor镜像的完整地址，例如: sh-harbor.mthreads.com/vllm-images/vllm-test-0808:test'
        )
        string(
            name: 'TEST_IMAGE_TAG',
            defaultValue: 'test',
            description: '镜像标签，如果不指定则使用test'
        )
        string(
            name: 'TEST_NODE_LABELS',
            defaultValue: '10.10.129.22',
            description: '执行节点标签，用逗号分隔，例如: 10.10.129.22,10.10.129.25'
        )
        booleanParam(
            name: 'TEST_FORCE_PULL',
            defaultValue: false,
            description: '是否强制拉取镜像（即使本地已存在）'
        )
        booleanParam(
            name: 'TEST_RECREATE_CONTAINER',
            defaultValue: false,
            description: '是否删除并重新创建容器（即使容器已存在）'
        )
        string(
            name: 'TEST_LOG_MONITOR_DURATION',
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
        SERVICE_HARBOR_URL = "${params.SERVICE_HARBOR_IMAGE_URL}"
        SERVICE_IMAGE_TAG = "${params.SERVICE_IMAGE_TAG}"
        SERVICE_NODE_LABELS = "${params.SERVICE_NODE_LABELS}"
        SERVICE_FORCE_PULL = "${params.SERVICE_FORCE_PULL}"
        SERVICE_LOG_MONITOR_DURATION = "${params.SERVICE_LOG_MONITOR_DURATION}"
        IS_TEST = "${params.IS_TEST}"
        TEST_HARBOR_URL = "${params.TEST_HARBOR_IMAGE_URL}"
        TEST_IMAGE_TAG = "${params.TEST_IMAGE_TAG}"
        TEST_NODE_LABELS = "${params.TEST_NODE_LABELS}"
        TEST_FORCE_PULL = "${params.TEST_FORCE_PULL}"
        TEST_LOG_MONITOR_DURATION = "${params.TEST_LOG_MONITOR_DURATION}"
        VERBOSE = "${params.VERBOSE}"
    }

    stages {
        stage('参数验证') {
            agent any
            steps {
                script {
                    echo "=== 参数信息 ==="
                    echo "Harbor镜像地址: ${SERVICE_HARBOR_URL}"
                    echo "镜像标签: ${SERVICE_IMAGE_TAG}"
                    echo "强制拉取: ${SERVICE_FORCE_PULL}"
                    echo "执行节点: ${SERVICE_NODE_LABELS}"
                    echo "日志监控时间: ${SERVICE_LOG_MONITOR_DURATION} 秒"

                    if (!SERVICE_HARBOR_URL.contains('/')) {
                        error "镜像地址格式错误，应该包含仓库路径，例如: harbor.example.com/project/image:tag"
                    }
                    def nodeList = SERVICE_NODE_LABELS.split(',').collect { it.trim() }
                    echo "解析后的节点列表: ${nodeList}"
                    if (nodeList.size() == 0) {
                        error "至少需要指定一个执行节点"
                    }
                    try {
                        def monitorDuration = SERVICE_LOG_MONITOR_DURATION.toInteger()
                        if (monitorDuration < 0) error "日志监控时间不能为负数"
                        if (monitorDuration > 3600) echo "⚠️ 警告：日志监控时间超过1小时，建议不超过600秒"
                    } catch (NumberFormatException e) {
                        error "日志监控时间必须是有效的数字"
                    }
                    nodeList.each { nodeLabel ->
                        try {
                            node("${nodeLabel}") {
                                echo "✅ 节点 ${nodeLabel} 可用"
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
                    def nodeList = SERVICE_NODE_LABELS.split(',').collect { it.trim() }
                    def branches = [:]
                    nodeList.eachWithIndex { nodeLabel, index ->
                        branches["在节点 ${nodeLabel} 拉取镜像"] = {
                            node("${nodeLabel}") {
                                echo "=== 节点验证 ==="
                                def fullImageUrl = SERVICE_HARBOR_URL
                                if (!SERVICE_HARBOR_URL.contains(':')) {
                                    fullImageUrl = "${SERVICE_HARBOR_URL}:${SERVICE_IMAGE_TAG}"
                                }
                                // 检查本地镜像
                                def localImageExists = sh(
                                    script: "sudo docker images --format '{{.Repository}}:{{.Tag}}' | grep -w '${fullImageUrl}'",
                                    returnStatus: true
                                ) == 0
                                if (localImageExists) {
                                    echo "✅ 本地镜像已存在: ${fullImageUrl}"
                                    sh "sudo docker images ${fullImageUrl}"
                                    if (SERVICE_FORCE_PULL == 'true') {
                                        echo "强制拉取模式：即使本地存在也会重新拉取"
                                    } else {
                                        echo "跳过拉取：本地镜像已存在且未启用强制拉取"
                                        return
                                    }
                                }
                                // 拉取镜像
                                def maxRetries = 3
                                def retryCount = 0
                                def pullSuccess = false
                                while (retryCount < maxRetries && !pullSuccess) {
                                    try {
                                        retryCount++
                                        echo "尝试第 ${retryCount} 次拉取镜像..."
                                        sh "sudo docker pull ${fullImageUrl}"
                                        echo "镜像拉取成功！"
                                        pullSuccess = true
                                        sh "sudo docker images | grep ${fullImageUrl.split('/').last()}"
                                    } catch (Exception domainError) {
                                        echo "第 ${retryCount} 次拉取失败: ${domainError.getMessage()}"
                                        if (retryCount >= maxRetries) {
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
                    def nodeList = SERVICE_NODE_LABELS.split(',').collect { it.trim() }
                    def branches = [:]
                    nodeList.eachWithIndex { nodeLabel, index ->
                        branches["验证节点 ${nodeLabel} 镜像"] = {
                            node("${nodeLabel}") {
                                if (env.NODE_NAME != nodeLabel) {
                                    error "❌ 节点分配错误！期望: ${nodeLabel}, 实际: ${env.NODE_NAME}"
                                }
                                def fullImageUrl = SERVICE_HARBOR_URL
                                if (!SERVICE_HARBOR_URL.contains(':')) {
                                    fullImageUrl = "${SERVICE_HARBOR_URL}:${SERVICE_IMAGE_TAG}"
                                }
                                def imageExists = sh(
                                    script: "sudo docker images --format '{{.Repository}}:{{.Tag}}' | grep -w '${fullImageUrl}'",
                                    returnStatus: true
                                ) == 0
                                if (imageExists) {
                                    echo "✅ 镜像验证成功: ${fullImageUrl}"
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
                    def nodeList = SERVICE_NODE_LABELS.split(',').collect { it.trim() }
                    echo "=== 所有节点操作完成 ==="
                    echo "✅ 镜像已在以下节点成功拉取和验证:"
                    nodeList.each { node ->
                        echo "   - ${node}"
                    }
                    echo "镜像地址: ${SERVICE_HARBOR_URL}"
                }
            }
        }

        stage('部署VLLM服务并日志同步') {
            steps {
                script {
                    def nodeList   = SERVICE_NODE_LABELS.split(',').collect { it.trim() }
                    def branches   = [:]
                    def LOG_NAME   = "yyz_" + new Date().format('yyyyMMdd_HHmmss')

                    nodeList.each { nodeLabel ->
                        branches["在节点 ${nodeLabel} 部署"] = {
                            node("${nodeLabel}") {
                                def containerName = 'vllm-server-0806'
                                def imageUrl      = SERVICE_HARBOR_URL
                                if (!SERVICE_HARBOR_URL.contains(':')) {
                                    imageUrl = "${SERVICE_HARBOR_URL}:${SERVICE_IMAGE_TAG}"
                                }

                                // 停止并清理同名容器
                                sh '''
                                    CONTAINER_ID=$(sudo docker ps -a --filter "name=vllm-server-0806" --format "{{.ID}}")
                                    if [ ! -z "$CONTAINER_ID" ]; then
                                        echo "停止容器: $CONTAINER_ID"
                                        sudo docker stop $CONTAINER_ID
                                        echo "删除容器: $CONTAINER_ID"
                                        sudo docker rm $CONTAINER_ID
                                    else
                                        echo "未找到现有容器: vllm-server-0806"
                                    fi
                                '''

                                // 标准对齐的 docker run 命令
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

                                // 启动SSH服务（用于多机分布式通信）
                                sh """
                                    sudo docker exec ${containerName} service ssh start
                                """

                                // 执行启动脚本（传递 LOG_NAME 和 VERBOSE 环境变量）
                                sh """
                                    sudo docker exec -e LOG_NAME=${LOG_NAME} -e VERBOSE=${VERBOSE} ${containerName} bash /mnt/vllm/yuyongzhong/llm-infer/vllm-musa-ci/startup.sh
                                """

                                // 服务监控
                                if (SERVICE_LOG_MONITOR_DURATION.toInteger() > 0) {
                                    sh """#!/bin/bash
                                        END_TIME=\$(date -d \"+${SERVICE_LOG_MONITOR_DURATION} seconds\" +%s)
                                        CURRENT_TIME=\$(date +%s)
                                        MONITOR_INTERVAL=60  # 监控间隔调整为60秒
                                        SERVICE_READY=false
                                        
                                        while [ \$CURRENT_TIME -lt \$END_TIME ]; do
                                            REMAINING=\$((END_TIME - CURRENT_TIME))
                                            
                                            # 检查服务是否已准备就绪
                                            MONITOR_LOG="/mnt/vllm/yuyongzhong/llm-infer/vllm-musa-ci/logs/service-logs/monitor-${LOG_NAME}.log"
                                            if sudo docker exec ${containerName} test -f "\$MONITOR_LOG" 2>/dev/null; then
                                                # 检查是否有服务监听在端口上
                                                if sudo docker exec ${containerName} netstat -tlnp 2>/dev/null | grep -E ":800[01].*LISTEN" >/dev/null 2>&1; then
                                                    if [ "\$SERVICE_READY" = "false" ]; then
                                                        SERVICE_READY=true
                                                        echo ""
                                                        echo "╔════════════════════════════════════════════════════════════════════════════════╗"
                                                        printf "║ 🎉 服务就绪检测 - 服务已启动完成 %-44s ║\\n" ""
                                                        echo "╚════════════════════════════════════════════════════════════════════════════════╝"
                                                        echo ""
                                                    fi
                                                fi
                                            fi
                                            
                                            # 只在有意义的时间间隔显示监控信息
                                            if [ \$((REMAINING % MONITOR_INTERVAL)) -eq 0 ] || [ \$REMAINING -lt 30 ]; then
                                                echo ""
                                                echo "╔════════════════════════════════════════════════════════════════════════════════╗"
                                                printf "║ 📊 服务监控 - 剩余时间: %-52s ║\\n" "\$REMAINING 秒"
                                                echo "╠════════════════════════════════════════════════════════════════════════════════╣"
                                                
                                                # 检查服务监控总览
                                                if sudo docker exec ${containerName} test -f "\$MONITOR_LOG" 2>/dev/null; then
                                                    # 显示监控总览的最新状态
                                                    LATEST_MONITOR=\$(sudo docker exec ${containerName} tail -n 50 "\$MONITOR_LOG" 2>/dev/null | grep -A 25 "╔.*监控时间.*╗" | tail -30)
                                                    if [ -n "\$LATEST_MONITOR" ]; then
                                                        echo "\$LATEST_MONITOR"
                                                    else
                                                        printf "║ 📝 监控状态: %-64s ║\\n" "等待服务启动..."
                                                        # 显示服务启动进度
                                                        if sudo docker exec ${containerName} ps aux | grep -q "python.*vllm" 2>/dev/null; then
                                                            printf "║ 🔄 启动状态: %-64s ║\\n" "vLLM 进程正在运行"
                                                        else
                                                            printf "║ 🔄 启动状态: %-64s ║\\n" "正在启动 vLLM 服务..."
                                                        fi
                                                        
                                                        # 检查端口监听状态
                                                        LISTENING_PORTS=\$(sudo docker exec ${containerName} netstat -tlnp 2>/dev/null | grep -E ":800[01].*LISTEN" | wc -l)
                                                        printf "║ 🔌 端口状态: %-64s ║\\n" "监听端口数: \$LISTENING_PORTS/2"
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
                                        
                                        if [ "\$SERVICE_READY" = "true" ]; then
                                            echo "🎉 服务监控完成：服务已就绪"
                                        else
                                            echo "⏰ 监控时间结束，建议检查服务状态"
                                        fi
                                    """
                                }
                            }
                        }
                    }
                    parallel branches
                }
            }
        }
        stage('启动测试任务'){
            steps{
                script{
                    echo "IS_TEST: ${IS_TEST}"
                    if (IS_TEST) {
                        build job: "VLLM-MUSA-TEST-CI", parameters: [
                            string(name: "HARBOR_IMAGE_URL", value: TEST_HARBOR_URL), 
                            string(name: "IMAGE_TAG", value: TEST_IMAGE_TAG), 
                            string(name: "NODE_LABELS", value: TEST_NODE_LABELS), 
                            booleanParam(name: "FORCE_PULL", value: TEST_FORCE_PULL), 
                            booleanParam(name: "RECREATE_CONTAINER", value: TEST_RECREATE_CONTAINER), 
                            string(name: "LOG_MONITOR_DURATION", value: TEST_LOG_MONITOR_DURATION),
                            booleanParam(name: "VERBOSE", value: params.VERBOSE)
                        ], wait: false
                    }
                }
            }
        }
    }

    post {
        always {
            echo "=== Pipeline 执行完成 ==="
            echo "构建状态: ${currentBuild.result ?: 'SUCCESS'}"
        }
    }
}