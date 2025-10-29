#!/bin/sh
set -e

HTML_ROOT="/usr/share/nginx/html"
CONFIG_DIR="$HTML_ROOT/config"
mkdir -p "$CONFIG_DIR"

# If API_BASE_URL not provided, leave it empty so frontend falls back to window.location.origin
API_BASE=${API_BASE_URL:-}

# Escape the value for safe JS embedding (simple quote + backslash handling)
ESCAPED_API_BASE=$(printf '%s' "$API_BASE" | sed 's/\\/\\\\/g; s/"/\\"/g')
if [ -n "$API_BASE" ]; then
	JS_VALUE="\"$ESCAPED_API_BASE\""
else
	JS_VALUE='""'
fi

cat > "$CONFIG_DIR/api-base.js" <<EOF
// Generated at container start
window.API_BASE_URL = ${JS_VALUE};
EOF

echo "[entrypoint] Wrote config/api-base.js with API_BASE_URL='${API_BASE}'"

exec "$@"
