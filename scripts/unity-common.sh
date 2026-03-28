#!/usr/bin/env bash
# unity-common.sh — Unity 脚本公共函数
# 被 unity-compile-smart.sh, unity-check.sh, unity-test.sh, unity-compile.sh 共享
#
# 使用方式: source "$(dirname "$0")/unity-common.sh"
# 前提: 调用方必须先设置 PROJECT_DIR 变量

# ── 检测 Unity Editor 是否为当前项目打开 ──
is_editor_open_for_project() {
    local lock_file="$PROJECT_DIR/Temp/UnityLockfile"

    # 1) 最可靠：锁文件被进程持有
    if [ -f "$lock_file" ] && command -v lsof >/dev/null 2>&1; then
        if lsof "$lock_file" >/dev/null 2>&1; then
            return 0
        fi
    fi

    # 2) 进程参数包含 projectPath
    if command -v pgrep >/dev/null 2>&1; then
        if pgrep -af "/Unity.app/Contents/MacOS/Unity" | grep -F -- "-projectPath $PROJECT_DIR" >/dev/null 2>&1; then
            return 0
        fi
    fi

    # 3) 弱信号：存在锁文件 + 最近有 compile_status 更新 + 系统有 Unity 进程
    local status_file="$PROJECT_DIR/Temp/compile_status.json"
    if [ -f "$lock_file" ] && [ -f "$status_file" ] && command -v pgrep >/dev/null 2>&1; then
        if pgrep -af "/Unity.app/Contents/MacOS/Unity" >/dev/null 2>&1; then
            local now mtime age
            now="$(date +%s)"
            mtime="$(stat -f %m "$status_file" 2>/dev/null || echo 0)"
            age=$((now - mtime))
            if [ "$age" -le 300 ]; then
                return 0
            fi
        fi
    fi

    return 1
}

# ── 查找 Unity Editor 可执行文件路径 ──
find_unity() {
    # 1. 环境变量
    if [ -n "${UNITY_PATH:-}" ] && [ -f "$UNITY_PATH" ]; then
        echo "$UNITY_PATH"
        return
    fi

    # 2. 直接安装
    local direct="/Applications/Unity/Unity.app/Contents/MacOS/Unity"
    if [ -f "$direct" ]; then
        echo "$direct"
        return
    fi

    # 3. Unity Hub（按版本查找）
    local hub_base="/Applications/Unity/Hub/Editor"
    if [ -d "$hub_base" ]; then
        local project_version=""
        local version_file="$PROJECT_DIR/ProjectSettings/ProjectVersion.txt"
        if [ -f "$version_file" ]; then
            project_version=$(grep "m_EditorVersion:" "$version_file" | sed 's/.*: //')
        fi

        if [ -n "$project_version" ] && [ -f "$hub_base/$project_version/Unity.app/Contents/MacOS/Unity" ]; then
            echo "$hub_base/$project_version/Unity.app/Contents/MacOS/Unity"
            return
        fi

        local latest=$(ls -1 "$hub_base" 2>/dev/null | sort -V | tail -1)
        if [ -n "$latest" ] && [ -f "$hub_base/$latest/Unity.app/Contents/MacOS/Unity" ]; then
            echo "$hub_base/$latest/Unity.app/Contents/MacOS/Unity"
            return
        fi
    fi

    echo ""
}

# ── 查找 tykit 的 unity-eval.sh（兼容 PackageCache 和嵌入包） ──
find_unity_eval() {
    # 优先搜嵌入包
    local embedded="$PROJECT_DIR/Packages/com.tyk.tykit/Scripts~/unity-eval.sh"
    if [ -f "$embedded" ]; then
        echo "$embedded"
        return
    fi

    # 回退搜 PackageCache
    find "$PROJECT_DIR/Library/PackageCache" -name "unity-eval.sh" -path "*/com.tyk.tykit*" 2>/dev/null | head -1
}

# ── 获取 tykit 端口 ──
get_eval_port() {
    local json_file="$PROJECT_DIR/Temp/eval_server.json"
    if [ -f "$json_file" ]; then
        python3 -c "import json; print(json.load(open('$json_file'))['port'])" 2>/dev/null
    fi
}
