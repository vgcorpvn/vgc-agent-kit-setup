# VGC Agent Kit — Setup

Setup scripts cho VGC Agent Kit — bộ skills và knowledge dùng chung cho team VG Corp.

## Yêu cầu

- **Claude Code** hoặc **Codex CLI** đã cài đặt
- **GitHub PAT** — PAT (classic) với quyền `repo`, `read:org`
  - Truy cập `vgcorpvn/vgc-agent-kit` (read+write)
  - Truy cập `vgcorpvn/vgc-agent-workspace` (read+write)
- **Scout token** (optional) — GitHub PAT với quyền `repo:read`
  - Truy cập `vgcorpvn/mobile.vhandicap.com` (read-only)
  - Cần cho skill `/discover-repo`

> **2 token riêng biệt** theo nguyên tắc least privilege. GitHub PAT dùng cho `gh` CLI (API, PR) + `git` (qua `gh auth setup-git`). Scout token lưu tại `~/.vgc/config/scout-token`, skills dùng qua `GH_TOKEN=... gh api`.

## Tạo token

1. Vào https://github.com/settings/tokens → **Generate new token (classic)**
2. **GitHub PAT**: scopes `repo`, `read:org` — cho kit + workspace
3. **Scout token**: scope `repo` (hoặc fine-grained với read-only) — cho source repo
4. Đảm bảo account đã được mời vào org `vgcorpvn`

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

## Setup làm gì

1. Kiểm tra git + gh CLI
   - Windows: tự cài Git và GitHub CLI bằng `winget` nếu thiếu
   - macOS: mở Xcode Command Line Tools nếu thiếu Git, tự cài `gh` qua Homebrew nếu có
2. **GitHub PAT** → `gh auth login` → verify quyền truy cập kit + workspace
3. **`gh auth setup-git`** → đồng bộ credentials giữa git và gh (URL sạch, không nhúng token)
4. Clone `vgc-agent-kit` → `~/.vgc/agent-kit/`
5. Clone `vgc-agent-workspace` → `~/.vgc/agent-workspace/`
6. **Scout token** (optional) → verify source repo access → lưu `~/.vgc/config/scout-token`
7. Symlink skills vào agent skills directory
8. Thêm update alias

## Sau khi cài đặt

- Skills tự động available — gõ `/` để xem danh sách
- Workspace repo clone tại `~/.vgc/agent-workspace/`
- Auto-sync: kit và workspace tự pull mỗi khi agent sử dụng skill
- Update thủ công:
  - Claude Code: `vgc-agent-kit-update-claude`
  - Codex CLI: `vgc-agent-kit-update-codex`
- Publish output: dùng skill `/vgc-agent-kit-publish`

## Troubleshooting

| Vấn đề | Giải pháp |
|--------|-----------|
| "Git chưa được cài đặt" | Mac: cài Xcode Command Line Tools. Windows: tải Git for Windows |
| Windows không tự cài được Git/gh | Kiểm tra máy có `winget`. Nếu không có, cài thủ công Git for Windows và GitHub CLI rồi chạy lại setup |
| "gh auth login thất bại" | GitHub PAT không hợp lệ hoặc hết hạn. Tạo token mới |
| "GitHub PAT không đủ quyền" | Kiểm tra token có scope `repo` và account đã vào org `vgcorpvn` |
| `gh api` báo 401 nhưng `git pull` OK | Chạy lại setup — sẽ re-auth gh CLI và chạy `gh auth setup-git` |
| `/discover-repo` không hoạt động nếu không có quyền read repo | Chạy lại setup và nhập scout token cho source repo |
| Skills không hiện | Chạy update command rồi restart Claude/Codex |
| Windows: "cannot create symbolic link" | Script đã dùng Junction — nếu vẫn lỗi, bật Developer Mode |
| gh CLI không cài được | Cài thủ công: https://cli.github.com/ |
