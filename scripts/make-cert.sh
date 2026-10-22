#!/bin/bash
# 최초 1회: 자체 서명 코드서명 인증서 "Paster Local Signing" 을 로그인 키체인에 만든다.
# 마지막 단계(add-trusted-cert)에서 macOS 가 로그인 암호를 묻는다 (대화형).
set -euo pipefail

NAME="Paster Local Signing"
KEYCHAIN="${KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
OPENSSL="${OPENSSL:-openssl}"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "인증서 '$NAME' 가 이미 있습니다."
    security find-identity -p codesigning "$KEYCHAIN" | grep "$NAME" || true
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<CNF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $NAME
[ ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.cnf"

# OpenSSL 3 이상의 기본 p12 암호화(AES/PBKDF2)는 security import 가 읽지 못하므로 -legacy 를 쓴다.
# macOS 기본 /usr/bin/openssl (LibreSSL) 은 원래 legacy 형식이라 옵션이 필요 없다.
LEGACY_FLAG=""
case "$("$OPENSSL" version)" in
    OpenSSL*) LEGACY_FLAG="-legacy" ;;
esac
P12_PASSWORD="$(uuidgen)"
"$OPENSSL" pkcs12 -export $LEGACY_FLAG -name "$NAME" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/cert.p12" -passout "pass:$P12_PASSWORD"

security import "$WORK/cert.p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign

echo "코드서명용으로 신뢰 설정을 추가합니다. macOS 가 로그인 암호를 물으면 입력하세요."
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

security find-identity -v -p codesigning "$KEYCHAIN" | grep "$NAME"
