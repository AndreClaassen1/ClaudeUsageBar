#!/bin/bash
set -euo pipefail

IDENTITY="ClaudeUsageBar Self-Signed"
KC="$HOME/Library/Keychains/claudeusagebar-signing.keychain-db"
KCPW="cub-local-signing"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "=== 1) Selbstsigniertes Code-Signing-Zertifikat erzeugen ==="
cat > "$WORK/cert.conf" <<'EOF'
[ req ]
distinguished_name = dn
prompt = no
x509_extensions = v3
[ dn ]
CN = ClaudeUsageBar Self-Signed
[ v3 ]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF

OSSL=/usr/bin/openssl   # LibreSSL: erzeugt Apple-kompatible PKCS12 (kein OpenSSL-3-MAC)
"$OSSL" req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.conf" 2>/dev/null
"$OSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -out "$WORK/id.p12" -passout pass:temp -name "$IDENTITY" 2>/dev/null
echo "Zertifikat + Schlüssel erzeugt."

echo "=== 2) Eigenen Signier-Keychain (bekanntes Passwort) anlegen ==="
security delete-keychain "$KC" 2>/dev/null || true
security create-keychain -p "$KCPW" "$KC"
security set-keychain-settings "$KC"            # kein Auto-Lock-Timeout
security unlock-keychain -p "$KCPW" "$KC"

echo "=== 3) Identity importieren + für codesign freigeben (ohne Dialog) ==="
security import "$WORK/id.p12" -k "$KC" -P temp -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPW" "$KC" >/dev/null

echo "=== 4) Keychain in die Suchliste aufnehmen ==="
EXISTING=$(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"$//')
if ! printf '%s\n' "$EXISTING" | grep -qF "$KC"; then
  # shellcheck disable=SC2086
  security list-keychains -d user -s $EXISTING "$KC"
fi

echo "=== 5) Prüfen ==="
security find-identity -v -p codesigning | grep -F "$IDENTITY" && echo "OK: Identity gefunden" || { echo "FEHLER: Identity nicht gefunden"; exit 1; }
