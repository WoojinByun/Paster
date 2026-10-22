.PHONY: test run

test:
	swift test

# 개발용 실행: debug .app 을 만들어 연다
run:
	./scripts/dev-bundle.sh
	-pkill -x Paster && sleep 1
	open build/debug/Paster.app
