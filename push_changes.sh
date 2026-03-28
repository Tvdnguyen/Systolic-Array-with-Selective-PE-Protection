#!/bin/bash

# Copy SYSTEM_ARCHITECTURE.md sang README.md để làm tài liệu chính trên GitHub
cp SYSTEM_ARCHITECTURE.md README.md

# Thêm tất cả các thay đổi vào staging (sẽ tuân theo file .gitignore mới)
git add .

# Yêu cầu nhập nội dung mô tả cho thay đổi (commit message)
echo "Nhập nội dung commit (hoặc nhấn Enter để dùng mặc định 'Update từ local'):"
read commit_message

if [ -z "$commit_message" ]; then
    commit_message="Update repository to only include vivado_build, Model, and README"
fi

# Thực hiện commit
git commit -m "$commit_message"

# Đẩy lên GitHub
git push origin main

echo "✅ Đã cập nhật thành công lên GitHub với cấu trúc rút gọn!"
