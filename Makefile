VERSION ?= 0.0.0
DEV_APP := build/debug/Paster.app
DEV_BIN := $(CURDIR)/$(DEV_APP)/Contents/MacOS/Paster
INSTALLED_BIN := /Applications/Paster.app/Contents/MacOS/Paster

.PHONY: cert app install test run icon sparkle-keys release

# 최초 1회: 자체 서명 인증서 "Paster Local Signing" (로그인 암호 입력 필요)
cert:
	./scripts/make-cert.sh

# build/Paster.app (release) 빌드 + 서명
app:
	VERSION=$(VERSION) ./scripts/bundle.sh release

# /Applications 로 복사하고 실행. 설치된 Paster 만 종료한다 (make run 으로 띄운 개발 빌드는 건드리지 않음)
install: app
	@pkill -f "^$(INSTALLED_BIN)$$" && sleep 1 || true
	rm -rf /Applications/Paster.app
	ditto build/Paster.app /Applications/Paster.app
	open /Applications/Paster.app

test:
	swift test

# 개발용 실행: debug 빌드를 같은 인증서로 서명해 build/debug/Paster.app 으로 연다.
# 이 체크아웃의 개발 빌드만 종료한다 (/Applications 에 설치한 Paster 는 건드리지 않음)
run:
	VERSION=$(VERSION) ./scripts/bundle.sh debug
	@pkill -f "^$(DEV_BIN)$$" && sleep 1 || true
	open $(DEV_APP)

# 아이콘을 바꿨을 때: Resources/AppIcon.svg -> Resources/AppIcon.icns
icon:
	./scripts/make-icon.sh

# 최초 1회: Sparkle EdDSA 키 생성 (개인 키는 로그인 키체인, 공개 키는 Resources/sparkle-public-key.txt)
sparkle-keys:
	swift package resolve
	./scripts/sparkle-keys.sh

# 공개 릴리스: main 에서 build/release/ 에 zip · appcast.xml 을 만들고 확인 후 GitHub Release 로 올린다.
#   make release VERSION=x.y.z            요약을 보여 주고 y 입력 후 업로드
#   make release VERSION=x.y.z DRY_RUN=1  업로드 직전까지만 (결과물은 build/release/)
#   make release VERSION=x.y.z CONFIRM=1  확인 질문 생략
release:
	./scripts/release.sh $(VERSION)
