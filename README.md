# VGC Agent Kit — Setup

Setup scripts cho VGC Agent Kit — bộ skills và knowledge dùng chung cho team VG Corp.

## Yêu cầu

- **Claude Code** hoặc **Codex CLI** đã cài đặt
- **GitHub Personal Access Token A** với quyền `repo:read` cho private repo `vgc-agent-kit`
- **GitHub Personal Access Token B** với quyền `repo:read+write` cho private repo `vgc-agent-workspace`

> Token A và Token B có thể là cùng 1 token nếu token đó có đủ quyền cho cả 2 repo.

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

> Không cần Run as Administrator.

## Sau khi cài đặt

- Skills tự động available — gõ `/` để xem danh sách
- Workspace repo clone tại `~/.vgc-agent-workspace/`
- Auto-sync: kit và workspace tự pull mỗi khi agent sử dụng skill
- Update thủ công:
  - Claude Code: `vgc-agent-kit-update-claude`
  - Codex CLI: `vgc-agent-kit-update-codex`
- Publish output: dùng skill `/vgc-agent-kit-publish`

## Troubleshooting

| Vấn đề | Giải pháp |
|--------|-----------|
| "Git chưa được cài đặt" | Mac: cài Xcode Command Line Tools. Windows: tải Git for Windows |
| "Clone thất bại" | Kiểm tra token còn hạn và có quyền truy cập repo |
| Skills không hiện | Chạy update command rồi restart Claude/Codex |
| Windows: "cannot create symbolic link" | Script đã dùng Junction — nếu vẫn lỗi, bật Developer Mode |
| gh CLI không cài được | Cài thủ công: https://cli.github.com/ |
| Workspace clone thất bại | Kiểm tra Token B có quyền read+write cho `vgc-agent-workspace` |
| PR tạo thất bại | Kiểm tra `gh auth status`. Re-auth: `gh auth login` |
