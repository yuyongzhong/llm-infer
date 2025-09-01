pipeline {
    agent none
    triggers {
    GenericTrigger(
        genericVariables: [[key: 'REQUEST_JSON', value: '$', contentType: 'JSON']],
        token: "vllm_musa_build_from_mr"
    )}
    parameters {
        string(name: 'version_date', defaultValue: '2025-07-10', description: 'version_date of the software stack')
        string(name: 'ddk_url', defaultValue: '-', description: 'specify the download URL for DDK')
        string(name: 'version_base_url', defaultValue: 'https://oss.mthreads.com/release-ci/computeQA/cuda_compatible/CI/release_KUAE_2.0_for_PH1_M3D', description: 'specify the download URL for DDK')
        string(name: 'toolkit_url', defaultValue: '-', description: 'specify the download URL for MUSA Toolkit')
        string(name: 'mudnn_url', defaultValue: '-', description: 'specify the download URL for muDNN')
        string(name: 'mccl_url', defaultValue: '-', description: 'specify the download URL for MCCL')
        string(name: 'mualg_url', defaultValue: 'https://oss.mthreads.com/release-ci/torch_musa_build/muAlg.tar', description: 'specify the download URL for muAlg')
        string(name: 'muthrust_url', defaultValue: 'https://oss.mthreads.com/release-ci/torch_musa_build/muThrust.tar', description: 'specify the download URL for muThrust')
        string(name: 'triton_url', defaultValue: '-', description: 'specify the download URL for Triton')
        string(name: 'tag', defaultValue: '20250710', description: 'specify the tag for the final image')
        string(name: 'vllm_musa_img_tag', defaultValue: '-', description: 'specify the tag for the final image')
        string(name: 'pytorch_url', defaultValue: 'https://oss.mthreads.com/release-ci/torch_musa_build/pytorch_v2.5.0_source.tar.gz', description: 'specify pytorch url')
        string(name: 'vllm_musa_tag', defaultValue: 'master', description: 'specify the tag of vllm_musa')
        string(name: 'torch_whl_path', defaultValue: '-', description: 'specify pytorch url')
        booleanParam(name: 'skip_base', defaultValue: true, description: 'Skip the base step')
        booleanParam(name: 'skip_vllm_musa_build', defaultValue: false, description: 'Skip the base step')
        booleanParam(name: 'build_only', defaultValue: false, description: 'skip start test service if it is true')
        choice(name: 'node_label', choices: ['10.10.129.22', '10.10.129.25'], description: 'jenkins node')
    }
    options {
        ansiColor('xterm') // 启用 ANSI 颜色支持，选择颜色主题
    }
    stages {
        stage('ParseMRParams') {
            when {
                expression {
                    def causes = currentBuild.getBuildCauses()
                    // 判断是否包含 Generic Webhook Trigger
                    return causes.any { it.toString().contains("GenericCause") }
                }
            }
            steps {
                echo "Start parse MR params"
                script {
                    def payload = readJSON text: env.REQUEST_JSON
                    
                    // 提取关键信息
                    def mrId = payload.object_attributes?.iid
                    def sourceBranch = payload.object_attributes?.source_branch
                    def targetBranch = payload.object_attributes?.target_branch
                    def action = payload.object_attributes?.action
                    def mergeStatus = payload.object_attributes?.merge_status
                    env.ACTION = action
                    env.GIT_URL = payload.project?.git_ssh_url
                    env.SOURCE_BRANCH = sourceBranch
                    env.TARGET_BRANCH = targetBranch
                    env.MERGE_ID = mrId
                    env.PRE_MERGE_BRANCH = "pre-merge/${mrId}"
                    
                    // 打印提取的信息
                    echo "========================================="
                    echo "Merge Request ID: ${mrId}"
                    echo "源分支: ${sourceBranch}"
                    echo "目标分支: ${targetBranch}"
                    echo "操作类型: ${action}"
                    echo "Merge status: ${mergeStatus}"
                    if ("${action}" != "open") {
                        echo "Merge request open not triggered, abort pipeline"
                    }
                }
            }
        }
        stage('Pre-merge') {
            agent { 
                node {
                    label "${node_label}"
                } 
            }
            when {
                expression {
                    def causes = currentBuild.getBuildCauses()
                    def isWebhook = causes.any { it.toString().contains("GenericCause")} 
                    return isWebhook && env.ACTION == 'open' && env.TARGET_BRANCH == 'master'
                }
            }
            steps {
                echo "merge branch into the pre-merge branch"
                echo "========================================"
                script {
                    sh """
                    set -eux
                    rm -rf vllm_musa
                    git config --global --add core.sshCommand "ssh -o StrictHostKeyChecking=no"
                    git clone ${env.GIT_URL} vllm_musa
                    cd vllm_musa
                    git fetch origin ${env.SOURCE_BRANCH}:${env.SOURCE_BRANCH}
                    git push origin --delete ${env.PRE_MERGE_BRANCH} || true
                    git checkout -b ${env.PRE_MERGE_BRANCH} origin/master
                    git merge origin/${env.SOURCE_BRANCH} --no-edit
                    git push origin ${env.PRE_MERGE_BRANCH}
                    """
                }
            }
        }
        stage('Cleanup') {
            agent { 
                node {
                    label "${node_label}"
                } 
            }
            when { 
                expression { 
                    def causes = currentBuild.getBuildCauses()
                    def isWebhook = causes.any { it.toString().contains("GenericCause")} 
                    if (isWebhook) {
                        return env.ACTION == 'open' && env.TARGET_BRANCH == 'master'
                    }
                    return true
                } 
            }
            steps {
                sh 'rm -rf torch-musa-build'
                sh "echo ${env.BUILD_NUMBER}"
                //sh "docker login sh-harbor.mthreads.com"
            }
        }
        // 根据 skip_prepare 参数决定是否执行 Prepare 阶段
        stage('Prepare') {
            agent { 
                node {
                    label "${node_label}"
                } 
            }
            when { 
                expression { 
                    def causes = currentBuild.getBuildCauses()
                    def isWebhook = causes.any { it.toString().contains("GenericCause")} 
                    if (isWebhook) {
                        return env.ACTION == 'open' && env.TARGET_BRANCH == 'master' && !params.skip_prepare
                    }
                    return !params.skip_prepare
                } 
            }
            steps {
                script {
                    // 调用共享方法
                    runPrepareSteps()
                    
                    
                    // build job: "UPDATE_BUILD_ENV", parameters: [
                    //     string(name: "version_date", value: "${env.VERSION_DATE}"), 
                    //     string(name: "version_base_url", value: "${params.version_base_url}"),
                    // ], wait: true
                }
            }
        }
        stage('BuildTrainImage') {
            agent { 
                node {
                    label "${node_label}"
                } 
            }
            when { 
                expression { 
                    def causes = currentBuild.getBuildCauses()
                    def isWebhook = causes.any { it.toString().contains("GenericCause")} 
                    if (isWebhook) {
                        return env.ACTION == 'open' && env.TARGET_BRANCH == 'master'
                    }
                    return true
                } 
            }
            steps {
                script {
                    // 调用共享方法
                    runPrepareSteps()
                    echo "${params.version_base_url}"
                    dir("torch-musa-build") {
                        // 根据布尔参数决定是否跳过相应的 make 任务
                        if (!params.skip_base) {
                            sh 'make -j128 vllm_musa_base'
                        } else {
                            echo "Skipping base step"
                        }
                        if (!params.skip_vllm_musa_build) {
                            sh 'make -j128 vllm_musa'
                        } else {
                            echo "Skipping compile step"
                        }
                        sh """
                        image=
                        new_tag="registry.mthreads.com/mcconline/\$(echo $image | cut -d'/' -f3-)"
                        echo "\${new_tag}"
                        """
                        // 清理旧的docker镜像，避免磁盘空间过度占用
                        sh "/bin/bash clean_old_images.sh"
                    }
                    if (!params.build_only) {
                        echo "sh-harbor.mthreads.com/mcctest/vllm-musa-${env.GPU_TYPE}"
                        echo "${env.TAG}"
                        build job: "VLLM-MUSA-SERVER-CI", parameters: [
                            string(name: "SERVICE_HARBOR_IMAGE_URL", value: "sh-harbor.mthreads.com/mcctest/vllm-musa-${env.GPU_TYPE}"), 
                            string(name: "SERVICE_IMAGE_TAG", value: "${env.TAG}"),
                        ], wait: true
                    }
                }
            }
        }
    }
    post {
        always {
            node("${node_label}") {
                script {
                    if (env.PRE_MERGE_BRANCH && env.ACTION == 'open') {
                        sh """
                        set -eux
                        cd vllm_musa
                        git ls-remote --exit-code ${env.GIT_URL} refs/heads/${env.PRE_MERGE_BRANCH} && \
                        git push origin --delete ${env.PRE_MERGE_BRANCH}
                        """
                    }
                }
            }
        }
    }
}

// 定义一个共享方法，封装重复的逻辑
def runPrepareSteps() {
    sh 'rm -rf torch-musa-build'
    sh 'git config --global --add core.sshCommand "ssh -o StrictHostKeyChecking=no"'
    sh 'git clone -b daily_build_without_conda-s4000 git@sh-code.mthreads.com:/mcc-qa/torch-musa-build.git'
    if (fileExists("torch-musa-build")) {
        echo "torch-musa-build cloned successful"
    } else {
        error "failed to clone torch-musa-build"
    }
    dir("torch-musa-build") {
        sh "pip install -r requirements.txt"
        
        // 构建 prepare.py 的命令行参数
        def prepareArgs = ["--version_date", "${params.version_date}"]
        
        if (params.version_base_url != '-') {
            prepareArgs += ["--version_base_url", "${params.version_base_url}"]
        }
        // 如果用户提供了某个参数的值（且不为 '-'），则将其添加到命令行参数中
        if (params.ddk_url != '-') {
            prepareArgs += ["--ddk_url", "${params.ddk_url}"]
        }
        if (params.toolkit_url != '-') {
            prepareArgs += ["--toolkit_url", "${params.toolkit_url}"]
        }
        if (params.mudnn_url != '-') {
            prepareArgs += ["--mudnn_url", "${params.mudnn_url}"]
        }
        if (params.mccl_url != '-') {
            prepareArgs += ["--mccl_url", "${params.mccl_url}"]
        }
        if (params.mualg_url != '-') {
            prepareArgs += ["--mualg_url", "${params.mualg_url}"]
        }
        if (params.muthrust_url != '-') {
            prepareArgs += ["--muthrust_url", "${params.muthrust_url}"]
        }
        if (params.triton_url != '-') {
            prepareArgs += ["--triton_url", "${params.triton_url}"]
        }
        if (params.tag != '-') {
            prepareArgs += ["--tag", "${params.tag}"]
        }
        if (params.vllm_musa_tag != '-') {
            prepareArgs += ["--vllm_musa_tag", "${params.vllm_musa_tag}"]
        }
        if (params.vllm_musa_img_tag == '-') {
            def today = sh(script: "date +%Y%m%d-%H%M", returnStdout: true).trim()
            echo "vllm_musa_img_tag not specified, use date: ${today}"
            prepareArgs += ["--vllm_musa_img_tag", "${today}"]
        }
        if (params.vllm_musa_img_tag != '-') {
            prepareArgs += ["--vllm_musa_img_tag", "${params.vllm_musa_img_tag}"]
        }
        if (params.torch_whl_path != '-') {
            prepareArgs += ["--torch_whl_path", "${params.torch_whl_path}"]
        }
        prepareArgs += ["--build_number", "${env.BUILD_NUMBER}"]
        prepareArgs += ["--pytorch_url", "https://oss.mthreads.com/release-ci/torch_musa_build/pytorch_v2.5.0_kineto_v2.0.1_source.tar.gz"]
        
        // 调用 prepare.py 并传递参数
        sh "python3 -u prepare.py ${prepareArgs.join(' ')}"
        
        def version_info_content = readFile "environment.mk"

        // 打印原始内容以验证读取是否正确
        echo "Original content of version_info.mk:"
        echo version_info_content
        
        def lines = version_info_content.split("\n")

        // 定义一个函数来解析属性文件
        def properties = [:]
        
        // 使用 for 循环逐行处理
        for (int i = 0; i < lines.size(); i++) {
            def line = lines[i]
            // 打印每一行以调试
            echo "Processing line ${i + 1}: ${line}"
            
            // 忽略空行和注释行（以 # 开头）
            if (line.trim() && !line.trim().startsWith('#')) {
                def parts = line.split('=')
                if (parts.length == 2) {
                    def key = parts[0].trim()
                    def value = parts[1].trim()
                    if (key && value) {
                        properties[key] = value
                    } else {
                        echo "Skipping invalid line: ${line}"
                    }
                } else {
                    echo "Skipping malformed line: ${line}"
                }
            }
        }

        // 将解析后的数据赋值给环境变量
        env.VERSION_DATE = properties['VERSION_DATE']
        env.TAG = properties['TAG_VLLM_MUSA']
        env.DDK_URL = properties['DDK_URL']
        env.GPU_TYPE = properties['GPU_TYPE']
        env.VLLM_MUSA_TAG = properties['TAG_VLLM_MUSA']
        env.SH_IMG_NAME_VLLM_MUSA = properties['SH_IMG_NAME_VLLM_MUSA']
    
        // 打印输出以验证结果
        echo "VERSION_DATE: ${env.VERSION_DATE}"
        echo "VLLM_MUSA_TAG: ${env.VLLM_MUSA_TAG}"
        echo "SH_IMG_NAME_VLLM_MUSA: ${env.SH_IMG_NAME_VLLM_MUSA}"
        echo "TAG: ${env.TAG}"
    }
}
