# VGC Agent Kit — Setup

Setup scripts cho VGC Agent Kit — bộ skills và knowledge dùng chung cho team VG Corp.

## Yêu cầu

- **Codex CLI** đã cài đặt ([hướng dẫn](https://github.com/openai/codex))
- **GitHub Personal Access Token** với quyền `repo:read` cho private repo `vgc-agent-kit`

## Cài đặt

### Mac / Linux

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/vgcorpvn/vgc-agent-kit-setup/main/vgc-agent-kit-setup-codex.sh)
```

### Windows (PowerShell)

```powershell
powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/vgcorpvn/vgc-agent-kit-setup/main/vgc-agent-kit-setup-codex.ps1 | iex"
```

> Không cần Run as Administrator. Scheduled task (auto-update) sẽ bỏ qua nếu không có quyền Admin.

## Sau khi cài đặt

- Skills tự động available trong Codex CLI — gõ `/` để xem danh sách
- Auto-update chạy mỗi ngày lúc 9h sáng
- Update thủ công: chạy `vgc-agent-kit-update-codex` trong terminal

## Troubleshooting

| Vấn đề | Giải pháp |
|--------|-----------|
| "Git chưa được cài đặt" | Mac: cài Xcode Command Line Tools. Windows: tải Git for Windows |
| "Clone thất bại" | Kiểm tra token còn hạn và có quyền truy cập repo |
| Skills không hiện trong Codex | Chạy `vgc-agent-kit-update-codex` rồi restart Codex |
| Windows: "cannot create symbolic link" | Script đã dùng Junction thay vì Symlink — nếu vẫn lỗi, bật Developer Mode trong Settings |
