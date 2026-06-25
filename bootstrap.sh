#!/usr/bin/env bash
#
# bootstrap.sh — set up the Neovim (NvChad) environment from this dotfiles repo
# on a fresh machine. Idempotent: safe to re-run.
#
# What it does:
#   1. Installs system prerequisites (neovim 0.11+, git, curl, ripgrep, fd,
#      a C toolchain, node, python3) via brew (macOS) or apt (Debian/Ubuntu).
#   2. Installs a Nerd Font (macOS only; warns elsewhere).
#   3. Symlinks  <repo>/nvim  ->  ~/.config/nvim  (backing up anything there).
#   4. Installs all plugins at the exact versions pinned in lazy-lock.json.
#   5. Installs the LSP servers + formatter this config uses, via Mason.
#
# Usage:  ./bootstrap.sh
#
set -euo pipefail

# ---------------------------------------------------------------------------
# paths & helpers
# ---------------------------------------------------------------------------
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NVIM_SRC="$REPO_DIR/nvim"
NVIM_DST="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"

# Mason packages = the servers enabled in lua/configs/lspconfig.lua
# (html, cssls, clangd, pylsp, ruff, terraformls) + lua_ls + the stylua formatter.
MASON_TOOLS=(
  lua-language-server
  stylua
  clangd
  html-lsp
  css-lsp
  python-lsp-server
  ruff
  terraform-ls
)

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m  %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m  %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

[ -d "$NVIM_SRC" ] || die "Could not find nvim config at $NVIM_SRC"

# ---------------------------------------------------------------------------
# Neovim 0.11+ on Linux: apt is too old, so grab the official prebuilt release.
# ---------------------------------------------------------------------------
nvim_is_recent() {
  have nvim || return 1
  local v maj min
  v="$(nvim --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)"
  maj="${v%%.*}"; min="${v##*.}"
  [ "$maj" -gt 0 ] || { [ "$maj" -eq 0 ] && [ "$min" -ge 11 ]; }
}

install_neovim_linux() {
  if nvim_is_recent; then
    log "Using existing Neovim ($(nvim --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1))."
    return
  fi
  have nvim && warn "System Neovim is older than 0.11 — installing the latest official build."

  local arch asset
  case "$(uname -m)" in
    x86_64|amd64)  arch="x86_64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) die "No prebuilt Neovim for arch $(uname -m); install neovim 0.11+ manually and re-run." ;;
  esac
  asset="nvim-linux-${arch}.tar.gz"

  local dest="$HOME/.local" tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp:-}"' RETURN
  mkdir -p "$dest/bin"
  log "Downloading Neovim ($asset) from GitHub releases…"
  curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/${asset}" -o "$tmp/$asset" \
    || die "Failed to download Neovim from GitHub."
  tar -xzf "$tmp/$asset" -C "$dest"
  ln -sf "$dest/nvim-linux-${arch}/bin/nvim" "$dest/bin/nvim"
  export PATH="$dest/bin:$PATH"
  log "Neovim installed to $dest/bin/nvim"
  warn "Add \"$dest/bin\" to your PATH permanently (e.g. in ~/.bashrc) if it isn't already."
}

# ---------------------------------------------------------------------------
# 1. system packages
# ---------------------------------------------------------------------------
install_system_packages() {
  case "$(uname -s)" in
    Darwin)
      if ! have brew; then
        die "Homebrew not found. Install it first: https://brew.sh"
      fi
      # Xcode command line tools provide the C compiler + make for treesitter.
      if ! xcode-select -p >/dev/null 2>&1; then
        log "Installing Xcode command line tools (follow the GUI prompt)…"
        xcode-select --install || true
        warn "Re-run this script once the Xcode CLT install finishes."
      fi
      log "Installing packages with Homebrew…"
      brew install neovim git curl ripgrep fd node python3
      log "Installing a Nerd Font (JetBrainsMono)…"
      brew install --cask font-jetbrains-mono-nerd-font || \
        warn "Nerd Font install failed — install one manually and set it in your terminal."
      ;;
    Linux)
      if have apt-get; then
        log "Installing packages with apt…"
        sudo apt-get update
        # Note: NOT installing apt's 'neovim' — Ubuntu/Debian ship a version
        # older than the 0.11 this config requires. install_neovim_linux below
        # pulls the latest official build instead.
        sudo apt-get install -y git curl tar ripgrep fd-find build-essential nodejs npm python3 python3-pip
        # Debian ships fd as 'fdfind'; expose it as 'fd' for telescope.
        if have fdfind && ! have fd; then
          mkdir -p "$HOME/.local/bin"
          ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
          warn "Linked fdfind -> ~/.local/bin/fd (ensure ~/.local/bin is on PATH)."
        fi
        install_neovim_linux
        warn "Install a Nerd Font manually and select it in your terminal: https://www.nerdfonts.com"
      else
        die "Unsupported Linux distro (no apt-get). Install deps manually: neovim 0.11+, git curl ripgrep fd a C compiler node python3."
      fi
      ;;
    *)
      die "Unsupported OS: $(uname -s). Install the prerequisites manually."
      ;;
  esac
}

# ---------------------------------------------------------------------------
# verify neovim is recent enough (config uses vim.lsp.enable / vim.uv → 0.11+)
# ---------------------------------------------------------------------------
check_nvim_version() {
  have nvim || die "nvim not on PATH after install."
  local ver
  ver="$(nvim --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)"
  local major="${ver%%.*}" minor="${ver##*.}"
  if [ "$major" -eq 0 ] && [ "$minor" -lt 11 ]; then
    die "Neovim $ver is too old; this config needs 0.11+. Upgrade neovim and re-run."
  fi
  log "Neovim $ver detected."
}

# ---------------------------------------------------------------------------
# 3. symlink the config
# ---------------------------------------------------------------------------
link_config() {
  if [ -L "$NVIM_DST" ] && [ "$(readlink "$NVIM_DST")" = "$NVIM_SRC" ]; then
    log "~/.config/nvim already linked to this repo."
    return
  fi
  if [ -e "$NVIM_DST" ] || [ -L "$NVIM_DST" ]; then
    local backup="${NVIM_DST}.backup.$(date +%Y%m%d%H%M%S)"
    warn "Existing $NVIM_DST found — moving it to $backup"
    mv "$NVIM_DST" "$backup"
  fi
  mkdir -p "$(dirname "$NVIM_DST")"
  ln -s "$NVIM_SRC" "$NVIM_DST"
  log "Linked $NVIM_DST -> $NVIM_SRC"
}

# ---------------------------------------------------------------------------
# 4. install plugins at the pinned versions
# ---------------------------------------------------------------------------
install_plugins() {
  log "Installing plugins (lazy.nvim restore @ lazy-lock.json)…"
  # First headless start bootstraps lazy.nvim + clones every plugin;
  # 'restore' then pins them to the exact commits in lazy-lock.json.
  nvim --headless "+Lazy! restore" +qa 2>&1 | tail -n 3 || \
    warn "Plugin install reported issues — open nvim and run :Lazy sync to inspect."
}

# ---------------------------------------------------------------------------
# 5. install Mason LSP servers + formatter (with a blocking wait)
# ---------------------------------------------------------------------------
install_mason_tools() {
  log "Installing language servers & formatter via Mason: ${MASON_TOOLS[*]}"
  local helper
  helper="$(mktemp -t mason-install.XXXXXX.lua)"
  trap 'rm -f "${helper:-}"' RETURN

  {
    printf 'local want = {'
    for t in "${MASON_TOOLS[@]}"; do printf ' "%s",' "$t"; done
    printf ' }\n'
    cat <<'LUA'
local ok, registry = pcall(require, "mason-registry")
if not ok then io.stderr:write("mason-registry unavailable\n"); vim.cmd("cq") end

local done = false
registry.refresh(function() done = true end)
vim.wait(60000, function() return done end, 100)

local pending = {}
for _, name in ipairs(want) do
  local got, pkg = pcall(registry.get_package, name)
  if got then
    if pkg:is_installed() then
      print(name .. ": already installed")
    else
      print(name .. ": installing…")
      pkg:install()
      pending[name] = true
    end
  else
    io.stderr:write("unknown mason package: " .. name .. "\n")
  end
end

vim.wait(600000, function()
  for name in pairs(pending) do
    if registry.get_package(name):is_installed() then pending[name] = nil end
  end
  return next(pending) == nil
end, 1000)

if next(pending) ~= nil then
  for name in pairs(pending) do io.stderr:write("did NOT finish: " .. name .. "\n") end
  vim.cmd("cq")
else
  print("All Mason tools installed.")
  vim.cmd("qa")
end
LUA
  } > "$helper"

  nvim --headless -c "luafile $helper" 2>&1 | tail -n 20 || \
    warn "Some Mason tools failed — open nvim and run :Mason to install them manually."
}

# ---------------------------------------------------------------------------
# post-install notes for things that can't be automated safely
# ---------------------------------------------------------------------------
post_notes() {
  echo
  log "Done. A few things to finish by hand:"
  if ! have claude; then
    echo "  • claudecode.nvim talks to the Claude Code CLI, which is not installed."
    echo "    Install it: https://docs.claude.com/claude-code  (then it's used via <leader>ac)"
  else
    echo "  • Claude Code CLI found ✓ (claudecode.nvim ready)"
  fi
  echo "  • Make sure your terminal font is set to a Nerd Font, or icons render as boxes."
  echo "  • Open nvim and run  :checkhealth  to verify everything."
}

# ---------------------------------------------------------------------------
main() {
  install_system_packages
  check_nvim_version
  link_config
  install_plugins
  install_mason_tools
  post_notes
}

main "$@"
