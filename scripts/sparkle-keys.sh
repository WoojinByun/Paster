#!/bin/bash
# 최초 1회: Sparkle EdDSA 키를 만든다 (개인 키는 로그인 키체인, 공개 키는 Resources/sparkle-public-key.txt).
# 여러 번 실행해도 안전하다: 키가 이미 있으면 generate_keys 가 새로 만들지 않고 기존 키를 그대로 쓴다.
set -euo pipefail

SPARKLE_BIN="${SPARKLE_BIN:-.build/artifacts/sparkle/Sparkle/bin}"
GENERATE_KEYS="${GENERATE_KEYS:-$SPARKLE_BIN/generate_keys}"
KEY_FILE="${KEY_FILE:-Resources/sparkle-public-key.txt}"

if [ ! -x "$GENERATE_KEYS" ]; then
    echo "generate_keys 를 찾을 수 없습니다: $GENERATE_KEYS ('swift package resolve' 를 먼저 실행하세요)" >&2
    exit 1
fi

# 키가 없으면 생성하고(키체인 접근 허용 창이 뜰 수 있음), 있으면 기존 키의 공개 키만 출력한다.
"$GENERATE_KEYS"

# 공개 키만 다시 조회한다. 실패하면 기존 파일을 건드리지 않는다.
PUBLIC_KEY="$("$GENERATE_KEYS" -p | tr -d '[:space:]')"

# Ed25519 공개 키 = 32바이트 -> base64 44자 (마지막이 '=')
if ! printf '%s' "$PUBLIC_KEY" | grep -Eq '^[A-Za-z0-9+/]{43}=$'; then
    echo "공개 키 형식이 올바르지 않습니다 (base64 44자 기대): '$PUBLIC_KEY'" >&2
    echo "$KEY_FILE 은 변경하지 않았습니다." >&2
    exit 1
fi

mkdir -p "$(dirname "$KEY_FILE")"
printf '%s\n' "$PUBLIC_KEY" > "$KEY_FILE"

echo "공개 키: $PUBLIC_KEY"
echo ""
echo "다음 단계:"
echo "  1. 공개 키를 $KEY_FILE 에 저장했습니다. 이 파일을 커밋하세요."
echo "  2. 개인 키를 반드시 백업하세요 (저장소 밖, 비밀번호 관리자 등에 보관):"
echo "       $SPARKLE_BIN/generate_keys -x <파일>"
echo "     개인 키를 잃으면 기존 사용자에게 업데이트를 배포할 수 없습니다. 개인 키는 절대 커밋하지 마세요."
