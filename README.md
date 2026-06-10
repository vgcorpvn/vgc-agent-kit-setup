# VGC Agent Kit — Setup

Setup scripts cho VGC Agent Kit — bộ skills và knowledge dùng chung cho team VG Corp.

## Yêu cầu

- **Codex CLI** đã cài đặt ([hướng dẫn](https://github.com/openai/codex))
- **GitHub Personal Access Token** với quyền `repo:read` cho private repo `vgc-agent-kit`

## Cài đặt

### Mac / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/vgcorp-tech/vgc-agent-kit-setup/main/vgc-agent-kit-setup-codex.sh | bash
```

### Windows (PowerShell — Run as Administrator)

```powershell
irm https://raw.githubusercontent.com/vgcorp-tech/vgc-agent-kit-setup/main/vgc-agent-kit-setup-codex.ps1 | iex
```

## Sau khi cài đặt

- Skills tự động available trong Codex CLI — gõ `/` để xem danh sách
- Auto-update chạy mỗi ngày lúc 9h sáng
- Update thủ công: chạy `vgc-agent-kit-update-codex` trong terminal

## Tạo GitHub Token

1. Vào https://github.com/settings/tokens
2. Click "Generate new token (classic)"
3. Chọn scope: `repo` (Full control of private repositories)
4. Copy token và paste khi script hỏi

## Troubleshooting

| Vấn đề | Giải pháp |
|--------|-----------|
| "Git chưa được cài đặt" | Mac: cài Xcode Command Line Tools. Windows: tải Git for Windows |
| "Clone thất bại" | Kiểm tra token còn hạn và có quyền truy cập repo |
| Skills không hiện trong Codex | Chạy `vgc-agent-kit-update-codex` rồi restart Codex |
| Windows: "cannot create symbolic link" | Chạy PowerShell as Administrator |
