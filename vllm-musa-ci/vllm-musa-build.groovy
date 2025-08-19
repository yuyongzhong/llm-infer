pipeline {
    agent none
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
        booleanParam(name: 'build_only', defaultValue: true, description: 'skip start test service if it is true')
    }
    options {
        ansiColor('xterm') // 启用 ANSI 颜色支持，选择颜色主题
    }
    stages {
        stage('Cleanup') {
            agent { 
                node {
                    label '10.10.129.22'
                } 
            }
            steps {
                sh 'rm -rf torch-musa-build'
                sh "echo ${env.BUILD_NUMBER}"
                sh "docker login sh-harbor.mthreads.com"
            }
        }
        // 根据 skip_prepare 参数决定是否执行 Prepare 阶段
        stage('Prepare') {
            when {
                expression { return !params.skip_prepare }
            }
            agent { 
                node {
                    label '10.10.129.22'
                } 
            }
            steps {
                script {
                    // 调用共享方法
                    runPrepareSteps()
                    
                    
                    build job: "UPDATE_BUILD_ENV", parameters: [
                        string(name: "version_date", value: "${env.VERSION_DATE}"), 
                        string(name: "version_base_url", value: "${params.version_base_url}"),
                    ], wait: true
                }
            }
        }
        stage('BuildTrainImage') {
            agent { 
                node {
                    label '10.10.129.22'
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
            def today = sh(script: "date +%Y%m%d", returnStdout: true).trim()
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
    
        // 打印输出以验证结果
        echo "VERSION_DATE: ${env.VERSION_DATE}"
        echo "TAG: ${env.TAG}"
    }
}
