pipeline {
    agent none

    parameters {

        string(name: 'SERVICE_HARBOR_IMAGE_URL', defaultValue: 'sh-harbor.mthreads.com/vllm-images/vllm-musa-qy2-py310:v0.8.4-release', description: 'Harbor镜像的完整地址')
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
                                        -e LOG_NAME=${LOG_NAME} \\
                                        --name      ${containerName} \\
                                        ${imageUrl} \\
                                        tail -f /dev/null
                                """

                                // 执行启动脚本（传递 LOG_NAME 环境变量）
                                sh """
                                    sudo docker exec -e LOG_NAME=${LOG_NAME} ${containerName} bash /mnt/vllm/yuyongzhong/llm-infer/vllm-musa-ci/startup.sh
                                """

                                // 日志监控示例
                                if (SERVICE_LOG_MONITOR_DURATION.toInteger() > 0) {
                                    sh """#!/bin/bash
                                        END_TIME=\$(date -d \"+${SERVICE_LOG_MONITOR_DURATION} seconds\" +%s)
                                        CURRENT_TIME=\$(date +%s)
                                        while [ \$CURRENT_TIME -lt \$END_TIME ]; do
                                            REMAINING=\$((END_TIME - CURRENT_TIME))
                                            echo "=== 日志监控 (\$REMAINING 秒剩余) ==="
                                            sudo docker exec ${containerName} tail -n 10 /mnt/vllm/yuyongzhong/llm-infer/vllm-musa-ci/logs/service-logs/deepseek-${LOG_NAME}.log 2>/dev/null || echo "DeepSeek日志文件不存在"
                                            sudo docker exec ${containerName} tail -n 10 /mnt/vllm/yuyongzhong/llm-infer/vllm-musa-ci/logs/service-logs/qwen-${LOG_NAME}.log 2>/dev/null || echo "Qwen日志文件不存在"
                                            sudo docker exec ${containerName} tail -n 10 /mnt/vllm/yuyongzhong/llm-infer/vllm-musa-ci/logs/service-logs/monitor-${LOG_NAME}.log 2>/dev/null || echo "监控日志文件不存在"
                                            sleep 30
                                            CURRENT_TIME=\$(date +%s)
                                        done
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
                            string(name: "LOG_MONITOR_DURATION", value: TEST_LOG_MONITOR_DURATION)
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