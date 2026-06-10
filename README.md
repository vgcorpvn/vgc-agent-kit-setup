# VGC Agent Kit — Setup

Setup scripts cho VGC Agent Kit — bộ skills và knowledge dùng chung cho team VG Corp.

## Yêu cầu

- **Claude Code** hoặc **Codex CLI** đã cài đặt
- **GitHub Personal Access Token** với quyền `repo:read` cho private repo `vgc-agent-kit`

## Cài đặt cho Claude Code

### Mac / Linux

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/vgcorpvn/vgc-agent-kit-setup/main/vgc-agent-kit-setup-claude.sh)
```

### Windows (PowerShell)

```powershell
powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/vgcorpvn/vgc-agent-kit-setup/main/vgc-agent-kit-setup-claude.ps1 | iex"
```

> Khởi động lại Claude Code sau khi setup. Gõ `/` để xem danh sách skills.

## Cài đặt cho Codex CLI

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

- Skills tự động available — gõ `/` để xem danh sách
- Auto-update chạy mỗi ngày lúc 9h sáng
- Update thủ công:
  - Claude Code: `vgc-agent-kit-update-claude`
  - Codex CLI: `vgc-agent-kit-update-codex`

## Troubleshooting

| Vấn đề | Giải pháp |
|--------|-----------|
| "Git chưa được cài đặt" | Mac: cài Xcode Command Line Tools. Windows: tải Git for Windows |
| "Clone thất bại" | Kiểm tra token còn hạn và có quyền truy cập repo |
| Skills không hiện | Chạy update command rồi restart Claude/Codex |
| Windows: "cannot create symbolic link" | Script đã dùng Junction — nếu vẫn lỗi, bật Developer Mode |
| Claude: plugin không load | Kiểm tra `~/.claude/plugins/installed_plugins.json` có entry `vgc-agent-kit@local` |
