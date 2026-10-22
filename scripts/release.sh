#!/bin/bash
# 릴리스: 빌드 · 서명 · zip · appcast · GitHub Release 업로드 (스펙 13절).
# 사용법: scripts/release.sh X.Y.Z [--yes]      (make release VERSION=X.Y.Z)
#
# 환경 변수:
#   CONFIRM=1        업로드 전 확인 질문을 건너뛴다 (--yes 와 같음)
#   DRY_RUN=1        gh release create 직전까지만 하고 멈춘다. 결과물은 build/release/ 에 남는다
#   SIGN_IDENTITY    서명 인증서 이름 (기본 "Paster Local Signing"). ad-hoc("-")은 릴리스에 쓸 수 없다
#   ALLOW_NON_MAIN=1 테스트 전용. main 브랜치 · 깨끗한 작업 트리 · HEAD == origin/main 검사를 건너뛴다.
#                    DRY_RUN=1 과 함께일 때만 허용된다
#
# EdDSA 개인 키는 로그인 키체인에 있는 것을 generate_appcast 가 직접 읽는다.
# 이 스크립트는 개인 키를 내보내거나 출력하지 않으며 --ed-key-file 을 쓰지 않는다.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() {
    echo "error: $*" >&2
    exit 1
}

# 0. 인자 · 버전 형식 (다른 어떤 작업보다 먼저)
VERSION=""
YES="${CONFIRM:-0}"
for arg in "$@"; do
    case "$arg" in
        --yes | -y) YES=1 ;;
        -*) fail "알 수 없는 옵션: $arg (사용법: $0 X.Y.Z [--yes])" ;;
        *)
            [ -z "$VERSION" ] || fail "버전을 두 번 지정했습니다: $VERSION, $arg"
            VERSION="$arg"
            ;;
    esac
done
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail "버전은 x.y.z 형식이어야 합니다 (예: make release VERSION=0.1.0). 받은 값: '$VERSION'"
fi
if [ "$VERSION" = "0.0.0" ]; then
    fail "0.0.0 은 개발 빌드 전용입니다. VERSION 을 지정하세요 (예: make release VERSION=0.1.0)."
fi

DRY_RUN="${DRY_RUN:-0}"
ALLOW_NON_MAIN="${ALLOW_NON_MAIN:-0}"
if [ "$ALLOW_NON_MAIN" = "1" ] && [ "$DRY_RUN" != "1" ]; then
    fail "ALLOW_NON_MAIN=1 은 테스트 전용이라 DRY_RUN=1 과 함께만 쓸 수 있습니다."
fi

TAG="v$VERSION"
REPO="WoojinByun/Paster"
DOWNLOAD_PREFIX="https://github.com/$REPO/releases/download/$TAG/"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"
IDENTITY="${SIGN_IDENTITY:-Paster Local Signing}"
OUT="build/release"
ZIP_NAME="Paster-$VERSION.zip"
NOTES_SOURCE="docs/release-notes/$TAG.md"
APPCAST_TIMEOUT=120

# x.y.z 두 개를 숫자로 비교: $1 > $2 이면 참
semver_gt() {
    local a b i
    IFS=. read -r -a a <<< "$1"
    IFS=. read -r -a b <<< "$2"
    for i in 0 1 2; do
        if ((10#${a[i]} > 10#${b[i]})); then return 0; fi
        if ((10#${a[i]} < 10#${b[i]})); then return 1; fi
    done
    return 1
}

# 1. 릴리스 안전장치 (빌드 전에 전부 확인)
if [ "$ALLOW_NON_MAIN" = "1" ]; then
    echo "warning: ALLOW_NON_MAIN=1 (테스트 전용): 브랜치 · 작업 트리 · origin/main 검사를 건너뜁니다." >&2
else
    BRANCH="$(git symbolic-ref --quiet --short HEAD || true)"
    if [ "$BRANCH" != "main" ]; then
        fail "릴리스는 main 브랜치에서만 할 수 있습니다 (현재: '${BRANCH:-detached HEAD}').
       빌드 번호(CFBundleVersion = git rev-list --count HEAD)는 main 에서만 단조 증가합니다."
    fi
    if ! git diff --quiet || ! git diff --cached --quiet; then
        fail "커밋하지 않은 변경이 있습니다. 커밋하거나 되돌린 뒤 다시 실행하세요."
    fi
fi

echo "==> origin 에서 최신 정보 가져오는 중 (git fetch)"
git fetch origin --tags --quiet || fail "git fetch origin 이 실패했습니다. 네트워크와 원격 저장소 접근을 확인하세요."

if [ "$ALLOW_NON_MAIN" != "1" ]; then
    HEAD_SHA="$(git rev-parse HEAD)"
    ORIGIN_SHA="$(git rev-parse --verify --quiet origin/main || true)"
    if [ "$HEAD_SHA" != "$ORIGIN_SHA" ]; then
        fail "HEAD($HEAD_SHA) 가 origin/main(${ORIGIN_SHA:-없음}) 과 다릅니다.
       push 하지 않은 커밋이 있거나 pull 이 필요합니다. 'git status' 로 확인하세요."
    fi
fi

if git rev-parse --verify --quiet "refs/tags/$TAG" >/dev/null; then
    fail "태그 $TAG 가 로컬에 이미 있습니다. 더 높은 버전을 지정하세요."
fi
if [ -n "$(git ls-remote --tags origin "refs/tags/$TAG")" ]; then
    fail "태그 $TAG 가 origin 에 이미 있습니다. 더 높은 버전을 지정하세요."
fi

if ! gh auth status >/dev/null 2>&1; then
    fail "gh 가 GitHub 에 로그인되어 있지 않습니다. 'gh auth login' 을 먼저 실행하세요."
fi
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    fail "GitHub 에 $TAG 릴리스가 이미 있습니다."
fi

# 기존 릴리스 태그(로컬 · 원격 태그 + GitHub 릴리스) 중 가장 높은 버전보다 커야 한다
LATEST_RELEASE="$(gh release list --repo "$REPO" --limit 1 --exclude-drafts --exclude-pre-releases \
    --json tagName --jq '.[0].tagName // ""')" ||
    fail "GitHub 릴리스 목록을 가져오지 못했습니다 (gh release list)."
HIGHEST=""
while IFS= read -r tag; do
    [[ "$tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]] || continue
    candidate="${BASH_REMATCH[1]}"
    if [ -z "$HIGHEST" ] || semver_gt "$candidate" "$HIGHEST"; then
        HIGHEST="$candidate"
    fi
done < <(
    git tag -l 'v*'
    git ls-remote --tags --refs origin 'v*' | sed 's#.*refs/tags/##'
    echo "$LATEST_RELEASE"
)
if [ -n "$HIGHEST" ] && ! semver_gt "$VERSION" "$HIGHEST"; then
    fail "새 버전 $VERSION 이 기존 최신 릴리스 v$HIGHEST 보다 높아야 합니다."
fi

if [ "$IDENTITY" = "-" ]; then
    fail "릴리스는 ad-hoc 서명(SIGN_IDENTITY=-)으로 할 수 없습니다. 'Paster Local Signing' 인증서를 쓰세요."
fi
if ! security find-identity -v -p codesigning | grep -qF "\"$IDENTITY\""; then
    fail "코드 서명 인증서 '$IDENTITY' 가 키체인에 없습니다. 먼저 'make cert' 를 실행하세요.
       업데이트가 동작하려면 이전 릴리스와 같은 인증서여야 합니다 (백업에서 복원)."
fi

if [ ! -x "$SPARKLE_BIN/generate_appcast" ]; then
    echo "==> Sparkle 도구가 없어 swift package resolve 실행"
    swift package resolve
    [ -x "$SPARKLE_BIN/generate_appcast" ] || fail "$SPARKLE_BIN/generate_appcast 를 찾을 수 없습니다."
fi

# 2~4. release 빌드, Paster.app 조립, 서명 (bundle.sh)
echo "==> 빌드 · 서명: $VERSION"
VERSION="$VERSION" SIGN_IDENTITY="$IDENTITY" ./scripts/bundle.sh release
APP="build/Paster.app"
BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
[ "$BUILT_VERSION" = "$VERSION" ] || fail "빌드된 앱 버전($BUILT_VERSION) 이 $VERSION 과 다릅니다."

# 5. zip (스테이징 디렉터리 build/release/)
rm -rf "$OUT"
mkdir -p "$OUT"
ZIP="$OUT/$ZIP_NAME"
ditto -c -k --keepParent "$APP" "$ZIP"

# zip 을 풀어 서명이 유효한지 확인
VERIFY_DIR="$(mktemp -d)"
trap 'rm -rf "$VERIFY_DIR"' EXIT
ditto -x -k "$ZIP" "$VERIFY_DIR"
codesign --verify --deep --strict "$VERIFY_DIR/Paster.app" || fail "zip 에서 푼 Paster.app 의 서명이 유효하지 않습니다."

# 릴리스 노트: docs/release-notes/vX.Y.Z.md 가 있으면 그것, 없으면 직전 태그 이후 커밋 제목.
# zip 과 같은 이름의 .md 를 generate_appcast 가 읽어 appcast 항목에 넣는다.
NOTES="$OUT/Paster-$VERSION.md"
if [ -f "$NOTES_SOURCE" ]; then
    cp "$NOTES_SOURCE" "$NOTES"
else
    {
        echo "# Paster $VERSION"
        echo
        if [ -n "$HIGHEST" ] && git rev-parse --verify --quiet "refs/tags/v$HIGHEST" >/dev/null; then
            git log --no-merges --pretty='- %s' "v$HIGHEST..HEAD"
        else
            echo "- 첫 공개 릴리스"
        fi
    } > "$NOTES"
fi

# 직전 릴리스의 appcast.xml 을 이어 붙인다 (이력 유지). generate_appcast 는 디렉터리에 있는 appcast.xml 을
# 재사용해 새 항목만 추가한다. 이전 항목의 다운로드 URL 은 각자의 릴리스 zip 을 그대로 가리킨다.
if [ -n "$LATEST_RELEASE" ]; then
    if gh release view "$LATEST_RELEASE" --repo "$REPO" --json assets --jq '.assets[].name' | grep -qx appcast.xml; then
        echo "==> 이전 appcast.xml 내려받는 중 ($LATEST_RELEASE)"
        gh release download "$LATEST_RELEASE" --repo "$REPO" --pattern appcast.xml --dir "$OUT" ||
            fail "$LATEST_RELEASE 의 appcast.xml 을 내려받지 못했습니다."
    else
        echo "warning: $LATEST_RELEASE 에 appcast.xml 이 없어 새 appcast 를 만듭니다." >&2
    fi
fi

# 6. appcast: 로그인 키체인의 EdDSA 개인 키로 서명 (키체인 접근 허용 창이 뜰 수 있다)
echo "==> generate_appcast"
APPCAST_STATUS=0
if command -v timeout >/dev/null 2>&1; then
    timeout "$APPCAST_TIMEOUT" "$SPARKLE_BIN/generate_appcast" \
        --download-url-prefix "$DOWNLOAD_PREFIX" \
        --embed-release-notes \
        --maximum-versions 0 \
        "$OUT" || APPCAST_STATUS=$?
else
    "$SPARKLE_BIN/generate_appcast" \
        --download-url-prefix "$DOWNLOAD_PREFIX" \
        --embed-release-notes \
        --maximum-versions 0 \
        "$OUT" || APPCAST_STATUS=$?
fi
if [ "$APPCAST_STATUS" -eq 124 ]; then
    fail "generate_appcast 가 ${APPCAST_TIMEOUT}초 안에 끝나지 않았습니다.
       키체인 접근 허용 창이 떠 있다면 로그인 암호를 입력하고 '항상 허용' 을 누른 뒤 다시 실행하세요."
elif [ "$APPCAST_STATUS" -ne 0 ]; then
    fail "generate_appcast 가 실패했습니다 (종료 코드 $APPCAST_STATUS). 'make sparkle-keys' 로 키가 키체인에 있는지 확인하세요."
fi
APPCAST="$OUT/appcast.xml"
[ -f "$APPCAST" ] || fail "$APPCAST 가 만들어지지 않았습니다."

# 새 항목 검사
ITEM="$(awk -v build="$BUILD_NUMBER" '
    /<item>/ { buf = ""; inside = 1 }
    inside { buf = buf $0 "\n" }
    /<\/item>/ { inside = 0; if (buf ~ "<sparkle:version>" build "</sparkle:version>") printf "%s", buf }
' "$APPCAST")"
[ -n "$ITEM" ] || fail "appcast 에 빌드 $BUILD_NUMBER 항목이 없습니다."
grep -qF "url=\"$DOWNLOAD_PREFIX$ZIP_NAME\"" <<< "$ITEM" || fail "appcast 항목의 다운로드 URL 이 $DOWNLOAD_PREFIX$ZIP_NAME 이 아닙니다."
grep -q 'sparkle:edSignature="' <<< "$ITEM" || fail "appcast 항목에 sparkle:edSignature 가 없습니다."
grep -qF "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" <<< "$ITEM" ||
    fail "appcast 항목의 shortVersionString 이 $VERSION 이 아닙니다."

# 요약
ZIP_SIZE="$(stat -f %z "$ZIP")"
ZIP_SHA="$(shasum -a 256 "$ZIP" | awk '{ print $1 }')"
ITEM_COUNT="$(grep -c '<item>' "$APPCAST" || true)"
cat <<EOF

================ 릴리스 요약 ================
버전          $VERSION ($TAG)
빌드 번호     $BUILD_NUMBER
커밋          $(git rev-parse HEAD)
zip           $ZIP ($ZIP_SIZE bytes)
SHA-256       $ZIP_SHA
appcast 항목  $ITEM_COUNT 개 (이전 릴리스: ${LATEST_RELEASE:-없음})
---------------- 새 appcast 항목 ----------------
$ITEM
---------------- 릴리스 노트 ($NOTES) ----------------
$(cat "$NOTES")
=============================================

EOF

if [ "$DRY_RUN" = "1" ]; then
    echo "DRY_RUN=1: gh release create 를 실행하지 않았습니다. 결과물: $OUT/"
    exit 0
fi

# 7. 확인 후 GitHub Release 생성 (공개 저장소에 바로 올라간다)
if [ "$YES" != "1" ]; then
    if [ ! -t 0 ]; then
        fail "확인 입력을 받을 수 없습니다 (터미널 아님). 확인했다면 CONFIRM=1 또는 --yes 로 다시 실행하세요."
    fi
    read -r -p "$TAG 를 https://github.com/$REPO 에 공개 릴리스합니다. 계속할까요? [y/N] " answer
    if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
        echo "취소했습니다. 결과물은 $OUT/ 에 남아 있습니다."
        exit 1
    fi
fi

gh release create "$TAG" "$ZIP" "$APPCAST" \
    --repo "$REPO" \
    --target "$(git rev-parse HEAD)" \
    --title "Paster $VERSION" \
    --notes-file "$NOTES" \
    --latest

echo "릴리스 완료: https://github.com/$REPO/releases/tag/$TAG"
