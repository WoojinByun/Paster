#!/bin/bash
# 최초 1회: 자체 서명 코드서명 인증서 "Paster Local Signing" 을 로그인 키체인에 만든다.
# 마지막 단계(add-trusted-cert)에서 macOS 가 로그인 암호를 묻는다 (대화형).
set -euo pipefail

NAME="Paster Local Signing"
KEYCHAIN="${KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
OPENSSL="${OPENSSL:-openssl}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 신뢰된 유효 인증서가 이미 있으면 끝.
if security find-identity -v -p codesigning "$KEYCHAIN" | grep "$NAME" >/dev/null; then
    echo "인증서 '$NAME' 가 이미 있습니다."
    security find-identity -v -p codesigning "$KEYCHAIN" | grep "$NAME"
    exit 0
fi

trust_cert() {
    echo "코드서명용으로 신뢰 설정을 추가합니다. macOS 가 로그인 암호를 물으면 입력하세요."
    security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"
}

finish() {
    if ! security find-identity -v -p codesigning "$KEYCHAIN" | grep "$NAME"; then
        echo "인증서가 아직 신뢰되지 않았습니다. 'make cert'를 다시 실행하고 암호 창에서 허용하세요." >&2
        exit 1
    fi
    exit 0
}

# 가져오기만 하고 신뢰 단계(암호 창)를 취소한 경우: 인증서를 다시 만들지 않고 신뢰만 다시 설정한다.
if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "인증서 '$NAME' 는 이미 가져왔지만 신뢰되지 않았습니다. 신뢰 설정을 다시 적용합니다."
    security find-certificate -c "$NAME" -p "$KEYCHAIN" > "$WORK/cert.pem"
    trust_cert
    finish
fi

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

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 7300 \
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

trust_cert
finish
