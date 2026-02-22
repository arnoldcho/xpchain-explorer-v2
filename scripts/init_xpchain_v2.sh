#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS_TEMPLATE="${ROOT_DIR}/settings.json.template"
SETTINGS_FILE="${ROOT_DIR}/settings.json"

if [[ ! -f "${SETTINGS_TEMPLATE}" ]]; then
  echo "settings.json.template not found: ${SETTINGS_TEMPLATE}"
  exit 1
fi

if [[ -f "${SETTINGS_FILE}" && "${1:-}" != "--force" ]]; then
  echo "settings.json already exists. Use --force to overwrite."
  exit 0
fi

cp "${SETTINGS_TEMPLATE}" "${SETTINGS_FILE}"

perl -0777 -i -pe '
  s/"user": "eiquidus"/"user": "xpchain_explorer"/g;
  s/"password": "Nd\^p2d77ceBX!L"/"password": "CHANGE_ME_MONGO_PASSWORD"/g;
  s/"database": "explorerdb"/"database": "xpchain_explorer_v2"/g;

  s/"port": 51573/"port": 8762/g;
  s/"username": "exorrpc"/"username": "CHANGE_ME_RPC_USER"/g;
  s/"password": "sSTLyCkrD94Y8&9mr\^m6W\^Mk367Vr!!K"/"password": "CHANGE_ME_RPC_PASSWORD"/g;

  s/"name": "Exor"/"name": "XPChain"/g;
  s/"symbol": "EXOR"/"symbol": "XPC"/g;
  s/"theme": "Exor"/"theme": "Flatly"/g;
  s/"page_title": "eIquidus"/"page_title": "XPChain Block Explorer"/g;
  s/\{ "symbol": "exor", "id": "exor" \}/\{ "symbol": "xpc", "id": "xpchain" \}/g;
  s/"favicon32": "favicon-32\.png"/"favicon32": "img\/branding\/favicon-32.png"/g;
  s/"favicon128": "favicon-128\.png"/"favicon128": "img\/branding\/favicon-128.png"/g;
  s/"favicon180": "favicon-180\.png"/"favicon180": "img\/branding\/favicon-180.png"/g;
  s/"favicon192": "favicon-192\.png"/"favicon192": "img\/branding\/favicon-192.png"/g;
  s#"logo": "/img/logo\.png"#"logo": "/img/branding/xpchain-logo.png"#g;
  s#"home_link_logo": "/img/header-logo\.png"#"home_link_logo": "/img/branding/xpchain-header-logo.png"#g;
  s/("masternodes_panel"\s*:\s*\{[\s\S]*?"enabled"\s*:\s*)true/$1false/s;
  s#"powered_by_text"\s*:\s*"[^"]*"#"powered_by_text": "<a class=\x27nav-link poweredby\x27 href=\x27https://github.com/arnoldcho/xpchain-explorer-v2\x27 target=\x27_blank\x27>XPChain Explorer v{explorer_version}</a>"#g;

  s/("masternodes_page"\s*:\s*\{\s*\/\/ enabled: Enable\/disable the masternodes page \(true\/false\)\s*\/\/          If set to false, the masternodes page will be completely inaccessible\s*"enabled"\s*:\s*)true/$1false/s;
' "${SETTINGS_FILE}"

echo "Created: ${SETTINGS_FILE}"
echo "Next steps:"
echo "1) Edit settings.json credentials (Mongo/RPC)"
echo "2) npm install"
echo "3) npm run sync-blocks"
echo "4) npm start"
