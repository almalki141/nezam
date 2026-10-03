#!/bin/zsh
set -e
cd "$(dirname "$0")"
export PATH="$PWD/.runtime/bin:$PATH"
export PUPPETEER_EXECUTABLE_PATH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
export PUPPETEER_SKIP_DOWNLOAD=true
export npm_config_cache="$PWD/.npm-cache"

if [[ ! -x "$PWD/.runtime/bin/node" ]]; then
  echo "ملفات Node المحمولة غير موجودة. افتح المشروع في Codex ليعيد تجهيزها."
  read -k 1
  exit 1
fi
if [[ ! -x "$PUPPETEER_EXECUTABLE_PATH" ]]; then
  echo "Google Chrome غير موجود في المسار المتوقع."
  read -k 1
  exit 1
fi
if [[ ! -f .env ]]; then
  TOKEN="$(openssl rand -hex 32)"
  umask 077
  {
    echo "AUTH_TOKEN=$TOKEN"
    echo "ALLOWED_ORIGIN=https://nezam.mrrsal.com"
    echo "PORT=8787"
    echo "DATA_DIR=$PWD/data"
    echo "TLS_KEY=$PWD/certs/localhost-key.pem"
    echo "TLS_CERT=$PWD/certs/localhost-cert.pem"
  } > .env
fi
set -a
source .env
set +a

mkdir -p certs
if [[ ! -f "$TLS_KEY" || ! -f "$TLS_CERT" ]]; then
  openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 825 \
    -keyout "$TLS_KEY" -out "$TLS_CERT" -subj "/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" >/dev/null 2>&1
  chmod 600 "$TLS_KEY" "$TLS_CERT"
fi
if [[ ! -d node_modules ]]; then
  echo "تجهيز مكتبات الموصل لأول مرة…"
  npm install --omit=dev --no-audit --no-fund
fi

rm -f bridge.log
node server.js > bridge.log 2>&1 &
BRIDGE_PID=$!
cleanup(){ kill "$BRIDGE_PID" 2>/dev/null || true; }
trap cleanup EXIT INT TERM
sleep 3
if ! kill -0 "$BRIDGE_PID" 2>/dev/null; then
  echo "تعذر تشغيل الموصل:"
  tail -30 bridge.log
  exit 1
fi

echo ""
echo "================ جاهز للربط ================"
echo "رابط الموصل: https://localhost:${PORT:-8787}"
echo "الرمز السري: $AUTH_TOKEN"
echo "============================================="
echo ""
echo "في المنظومة: متابعة أعمالي ← واتساب QR"
echo "ألصق الرابط والرمز، ثم اضغط حفظ واختبار وبعدها عرض QR."
echo "اترك هذه النافذة وجهاز Mac مفتوحين حتى يستمر الإرسال."
open -na "Google Chrome" --args --user-data-dir="$PWD/.chrome-profile" --allow-insecure-localhost "https://nezam.mrrsal.com/" >/dev/null 2>&1 || true
wait "$BRIDGE_PID"
