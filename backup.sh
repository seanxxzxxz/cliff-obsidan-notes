#!/bin/bash
cd "$(dirname "$0")"

# 自动给所有空目录添加 .gitkeep，确保空文件夹能被 Git 同步
find . -type d -empty -not -path "./.git/*" -exec touch {}/.gitkeep \;

# 原有备份逻辑
git add .
read -p "请输入备份备注：" msg
git commit -m "$msg"
git push origin main
echo "✅ 备份完成！已同步到 GitHub 云端（含空目录）"

