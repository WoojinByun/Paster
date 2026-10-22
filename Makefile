.PHONY: cert test run icon

# 최초 1회: 자체 서명 인증서 "Paster Local Signing" (로그인 암호 입력 필요)
cert:
	./scripts/make-cert.sh

test:
	swift test

# 개발용 실행: debug .app 을 만들어 연다
run:
	./scripts/dev-bundle.sh
	-pkill -x Paster && sleep 1
	open build/debug/Paster.app

# 아이콘을 바꿨을 때: Resources/AppIcon.svg -> Resources/AppIcon.icns
icon:
	./scripts/make-icon.sh
