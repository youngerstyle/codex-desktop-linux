#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="${1:-codex-app}"

mkdir -p \
    "$app_dir/content/webview" \
    "$app_dir/resources/node-runtime/bin" \
    "$app_dir/resources/plugins/openai-bundled/.agents/plugins" \
    "$app_dir/resources/plugins/openai-bundled/plugins/computer-use/.codex-plugin" \
    "$app_dir/resources/plugins/openai-bundled/plugins/computer-use/bin" \
    "$app_dir/resources/plugins/openai-bundled/plugins/computer-use/assets"

cat > "$app_dir/resources/plugins/openai-bundled/.agents/plugins/marketplace.json" <<'JSON'
{
  "plugins": [
    {
      "name": "computer-use",
      "source": {
        "source": "local",
        "path": "./plugins/computer-use"
      },
      "policy": {
        "installation": "AVAILABLE",
        "authentication": "ON_INSTALL"
      },
      "category": "Productivity"
    }
  ]
}
JSON

cat > "$app_dir/resources/plugins/openai-bundled/plugins/computer-use/.codex-plugin/plugin.json" <<'JSON'
{
  "name": "computer-use",
  "version": "0.1.2-linux-alpha2",
  "mcpServers": "./.mcp.json",
  "interface": {
    "displayName": "Computer Use",
    "category": "Productivity",
    "logo": "./assets/app-icon.png"
  }
}
JSON

cat > "$app_dir/resources/plugins/openai-bundled/plugins/computer-use/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "computer-use": {
      "command": "./bin/codex-computer-use-linux",
      "args": ["mcp"],
      "cwd": "."
    }
  }
}
JSON

for binary in codex-computer-use-linux codex-computer-use-cosmic; do
    printf '%s\n' '#!/usr/bin/env bash' 'echo "computer-use fixture"' > "$app_dir/resources/plugins/openai-bundled/plugins/computer-use/bin/$binary"
    chmod +x "$app_dir/resources/plugins/openai-bundled/plugins/computer-use/bin/$binary"
done
: > "$app_dir/resources/plugins/openai-bundled/plugins/computer-use/assets/app-icon.png"

printf '%s\n' '#!/usr/bin/env bash' 'echo "codex desktop fixture"' > "$app_dir/start.sh"
chmod +x "$app_dir/start.sh"

printf '%s\n' '<!doctype html><title>Codex fixture</title>' > "$app_dir/content/webview/index.html"

for binary in node npm npx; do
    cat > "$app_dir/resources/node-runtime/bin/$binary" <<'SCRIPT'
#!/usr/bin/env bash
case "$(basename "$0")" in
    node) echo v22.22.2 ;;
    *) echo 10.9.7 ;;
esac
SCRIPT
    chmod +x "$app_dir/resources/node-runtime/bin/$binary"
done
