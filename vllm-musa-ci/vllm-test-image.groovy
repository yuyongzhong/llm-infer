pipeline {
    agent none  // 不指定全局代理，各阶段自行指定节点

    // 定义参数（保持与后续流程的参数兼容性）
    parameters {
        string(
            name: 'NODE_LABELS',
            defaultValue: '10.10.129.22',
            description: '执行构建的节点标签，默认使用10.10.129.22'
        )
        string(
            name: 'GIT_REPO',
            defaultValue: 'https://sh-code.mthreads.com/mcc-qa/llm-infer.git',
            description: '代码仓库地址'
        )
        string(
            name: 'HARBOR_REGISTRY',
            defaultValue: 'sh-harbor.mthreads.com',
            description: 'Harbor仓库地址'
        )
        string(
            name: 'HARBOR_PROJECT',
            defaultValue: 'vllm-images',
            description: 'Harbor项目名称'
        )
        string(
            name: 'IMAGE_TAG',
            defaultValue: 'test',
            description: '镜像标签，默认test'
        )
    }

    environment {
        // 定义环境变量，统一管理路径和名称
        WORKSPACE_DIR = '/mnt/vllm/llm-infer'  // 代码存放路径
        IMAGE_SAVE_PATH = '/mnt/vllm/images'         // 镜像保存路径
        // 从参数映射关键变量（使用params前缀）
        BUILD_NODE = "${params.NODE_LABELS}"
        HARBOR_FULL_REGISTRY = "${params.HARBOR_REGISTRY}/${params.HARBOR_PROJECT}"
    }

    stages {
        stage('参数初始化与验证') {
            agent { node("${BUILD_NODE}") }  // 在指定构建节点执行
            steps {
                script {
                    echo "=== 流程初始化 ==="
                    // 获取当天日期（格式：MMdd，如0807）
                    env.DAY_DATE = new Date().format('MMdd')
                    // 定义镜像核心名称（含日期）
                    env.IMAGE_BASE_NAME = "vllm-test-${DAY_DATE}"
                    // 完整镜像名称（本地构建）
                    env.LOCAL_IMAGE = "${IMAGE_BASE_NAME}:${params.IMAGE_TAG}"  // 使用params.IMAGE_TAG
                    // Harbor目标镜像名称
                    env.HARBOR_IMAGE = "${HARBOR_FULL_REGISTRY}/${IMAGE_BASE_NAME}:${params.IMAGE_TAG}"
                    // 镜像保存文件名
                    env.IMAGE_SAVE_FILE = "${IMAGE_SAVE_PATH}/${IMAGE_BASE_NAME}-${params.IMAGE_TAG}.image"

                    echo "=== 构建参数确认 ==="
                    echo "构建节点: ${BUILD_NODE}"
                    echo "代码仓库: ${params.GIT_REPO} " 
                    echo "当天日期: ${DAY_DATE}"
                    echo "本地镜像名称: ${LOCAL_IMAGE}"
                    echo "Harbor目标镜像: ${HARBOR_IMAGE}"
                    echo "镜像保存路径: ${IMAGE_SAVE_FILE}"

                    // 验证节点可用性
                    echo "=== 验证节点可用性 ==="
                    if (env.NODE_NAME != BUILD_NODE) {
                        error "节点分配错误！期望节点: ${BUILD_NODE}, 实际节点: ${env.NODE_NAME}"
                    }

                    // 检查基础路径是否存在
                    echo "=== 检查基础目录 ==="
                    sh "mkdir -p ${WORKSPACE_DIR} || true"  // 确保代码目录存在
                    sh "mkdir -p ${IMAGE_SAVE_PATH} || true"  // 确保镜像保存目录存在
                    echo "基础目录检查通过"
                }
            }
        }

        stage('拉取代码与构建镜像') {
            agent { node("${BUILD_NODE}") }
            steps {
                script {
                    echo "=== 拉取代码 ==="
                    
                    sh """cd ${WORKSPACE_DIR}
                    git pull https://zhenhai.zhang-ext:moer123%21%40%23@sh-code.mthreads.com/mcc-qa/llm-infer.git """  
                    
                    echo "=== 构建Docker镜像 ==="
                    // 进入代码目录执行构建
                    sh """
                        cd ${WORKSPACE_DIR}
                        docker build -t ${LOCAL_IMAGE} -f Dockerfile ./
                    """
                    
                    // 验证镜像是否构建成功
                    echo "=== 验证镜像构建结果 ==="
                    def imageExists = sh(
                        script: "docker images --format '{{.Repository}}:{{.Tag}}' | grep -w '${LOCAL_IMAGE}'",
                        returnStatus: true
                    ) == 0
                    if (!imageExists) {
                        error "❌ 镜像构建失败，本地未找到镜像: ${LOCAL_IMAGE}"
                    }
                    echo "✅ 镜像构建成功: ${LOCAL_IMAGE}"
                    sh "docker images ${LOCAL_IMAGE}"  // 展示镜像信息
                }
            }
        }

        stage('保存镜像到本地') {
            agent { node("${BUILD_NODE}") }
            steps {
                script {
                    echo "=== 保存镜像到本地路径 ==="
                    // 执行镜像保存命令
                    sh "docker save -o ${IMAGE_SAVE_FILE} ${LOCAL_IMAGE}"
                    
                    // 验证镜像文件是否存在
                    echo "=== 验证镜像保存结果 ==="
                    def fileExists = sh(
                        script: "test -f ${IMAGE_SAVE_FILE}",
                        returnStatus: true
                    ) == 0
                    if (!fileExists) {
                        error "❌ 镜像保存失败，未找到文件: ${IMAGE_SAVE_FILE}"
                    }
                    // 检查文件大小（确保不是空文件）
                    sh "du -h ${IMAGE_SAVE_FILE}"  // 展示文件大小
                    echo "✅ 镜像保存成功: ${IMAGE_SAVE_FILE}"
                }
            }
        }

        stage('推送镜像到Harbor') {
            agent { node("${BUILD_NODE}") }
            steps {
                script {
                    echo "=== 标记镜像 ==="
                    sh "docker tag ${LOCAL_IMAGE} ${HARBOR_IMAGE}"
                    echo "=== 登录Harbor仓库 ==="
                    sh "docker login ${params.HARBOR_REGISTRY} "  
             
                    echo "=== 推送镜像到Harbor ==="
                    // 推送镜像（添加重试机制，应对网络波动）
                    def maxRetries = 3
                    def retryCount = 0
                    def pushSuccess = false
                    
                    while (retryCount < maxRetries && !pushSuccess) {
                        try {
                            retryCount++
                            echo "尝试第 ${retryCount} 次推送镜像..."
                            sh "docker push ${HARBOR_IMAGE}"
                            pushSuccess = true
                        } catch (Exception e) {
                            echo "第 ${retryCount} 次推送失败: ${e.getMessage()}"
                            if (retryCount >= maxRetries) {
                                error "❌ 镜像推送失败，已重试 ${maxRetries} 次"
                            }
                            sleep(10)  // 等待10秒后重试
                        }
                    }

                    echo "✅ 镜像推送成功: ${HARBOR_IMAGE}"
                }
            }
        }

        stage('验证推送结果') {
            agent { node("${BUILD_NODE}") }
            steps {
                script {
                    echo "=== 验证Harbor镜像存在性 ==="
                    
                    // 重新登录（确保凭据有效）
                    sh "docker login ${params.HARBOR_REGISTRY} "  // 使用params.HARBOR_REGISTRY
                    // 检查远程镜像清单
                    def manifestCheck = sh(
                        script: "docker manifest inspect ${HARBOR_IMAGE} > /dev/null 2>&1",
                        returnStatus: true
                    ) == 0
                    
                    if (!manifestCheck) {
                        error "❌ Harbor仓库中未找到镜像: ${HARBOR_IMAGE}"
                    }
                   
                    echo "✅ Harbor镜像验证成功: ${HARBOR_IMAGE}"
                }
            }
        }
    }

    post {
        success {
            echo "🎉 镜像构建与推送流程全部成功完成"
            echo "关键信息汇总："
            echo "  构建日期: ${DAY_DATE}"
            echo "  本地镜像: ${LOCAL_IMAGE}"
            echo "  镜像保存文件: ${IMAGE_SAVE_FILE}"
            echo "  Harbor镜像地址: ${HARBOR_IMAGE}"  
        }
        failure {
            echo "❌ 镜像构建与推送流程执行失败，请检查日志排查问题"
        }
    }
}