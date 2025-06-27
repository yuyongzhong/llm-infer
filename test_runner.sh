#!/bin/bash

set -e

IMAGE_NAME="inference-test-image"
CONTAINER_NAME="inference_test_container"
LOCAL_RESULTS_DIR="local_test_results_$(date +%Y%m%d%H%M)"

# 默认参数
BUILD_IMAGE=0
RUN_CONTAINER=0
ENTER_CONTAINER=0   #  新增：是否进入容
RUN_PERFORMANCE_TEST=0
RUN_ACCURACY_TEST=0
REMOVE_CONTAINER_AFTER=0

# 帮助信息
usage() {
    echo "Usage: $0 [-b] [-d] [-p] [-a] [-r] [-i]"
    echo "  -b    构建 Docker 镜像（如果本地没有也会自动构建）"
    echo "  -d    启动容器"
    echo "  -i    启动后进入容器交互模式"
    echo "  -p    执行性能测试"
    echo "  -a    执行精度测试"
    echo "  -r    测试完成后移除容器"
    exit 1
}

# 参数解析
while getopts "bdpari" opt; do
    case ${opt} in
        b ) BUILD_IMAGE=1 ;;
        d ) RUN_CONTAINER=1 ;;
        p ) RUN_PERFORMANCE_TEST=1 ;;
        a ) RUN_ACCURACY_TEST=1 ;;
        r ) REMOVE_CONTAINER_AFTER=1 ;;
        i ) ENTER_CONTAINER=1 ;;   
        * ) usage ;;
    esac
done

if [ $OPTIND -eq 1 ]; then usage; fi

mkdir -p "$LOCAL_RESULTS_DIR"

# 判断镜像是否存在
image_exists=$(docker images -q "$IMAGE_NAME")

if [ "$BUILD_IMAGE" -eq 1 ] || [ -z "$image_exists" ]; then
    echo "🔧 正在构建镜像 $IMAGE_NAME..."
    docker build -t "$IMAGE_NAME" .
    echo "✅ 镜像构建完成"
else
    echo "✅ 已存在镜像 $IMAGE_NAME，跳过构建"
fi

# 启动容器（后台运行）
container_exists=$(docker ps -aq -f name="$CONTAINER_NAME")

if [ "$RUN_CONTAINER" -eq 1 ]; then
    if [ -n "$container_exists" ]; then
        echo "⚠️ 容器 \"$CONTAINER_NAME\" 已存在，正在停止并删除..."
        docker stop "$CONTAINER_NAME" && docker rm "$CONTAINER_NAME"
    fi

    echo "🚀 正在后台启动容器 \"$CONTAINER_NAME\"..."
    docker run -d \
        --net host \
        --privileged \
        --pid host \
        --ipc host \
        --name "$CONTAINER_NAME" \
        -v "$(pwd):/workspace/host_machine" \
        "$IMAGE_NAME"
else
    if [ -z "$(docker ps -q -f name="$CONTAINER_NAME")" ]; then
        echo "❌ 容器未运行，且未指定启动容器 (-d)，无法继续！"
        exit 1
    else
        echo "✅ 使用已启动的容器 \"$CONTAINER_NAME\""
    fi
fi


# 是否进入容器交互
if [ "$ENTER_CONTAINER" -eq 1 ]; then
    echo "🧭 进入容器交互模式（按 Ctrl+D 退出）..."
    docker exec -it "$CONTAINER_NAME" bash
fi

# 执行测试逻辑
if [ "$RUN_PERFORMANCE_TEST" -eq 1 ]; then
    echo "📌 执行性能测试..."
    docker exec "$CONTAINER_NAME" bash run_performance_test.sh
    echo "✅ 性能测试完成"
fi

if [ "$RUN_ACCURACY_TEST" -eq 1 ]; then
    echo "📌 执行精度测试..."
    docker exec "$CONTAINER_NAME" bash run_accuracy_test.sh
    echo "✅ 精度测试完成"
fi

# 清理容器
if [ "$REMOVE_CONTAINER_AFTER" -eq 1 ]; then
    echo "🧹 测试完成，正在移除容器..."
    docker stop "$CONTAINER_NAME" && docker rm "$CONTAINER_NAME"
    echo "✅ 容器已移除"
else
    echo "⏳ 测试完成，容器继续保留运行"
fi

echo "📂 测试结果已保存至目录: $LOCAL_RESULTS_DIR"
