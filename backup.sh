#!/bin/bash
# Obsidian Vault 一键备份脚本（正确版本）
cd "$(dirname "$0")"
git add .
read -p "请输入备份备注：" msg
git commit -m "$msg"
echo "备份完成！"
