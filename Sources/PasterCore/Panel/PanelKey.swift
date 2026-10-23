/// 리듀서 입력. 키 입력과 마우스 클릭을 함께 다룬다.
public enum PanelKey: Equatable, Sendable {
    case up
    case down
    case left
    case right
    case enter
    case shiftEnter
    case cmdEnter
    /// ⌘1~9 (1부터 시작)
    case cmdNumber(Int)
    case cmdP
    case optCmdUp
    case optCmdDown
    /// PageUp (fn+↑) / PageDown (fn+↓): `PanelState.pageSize` 행씩 이동
    case pageUp
    case pageDown
    /// Home (fn+←) / End (fn+→): 맨 처음 / 맨 끝 항목
    case home
    case end
    case cmdDelete
    /// ⌘, : 설정 창 열기
    case cmdComma
    case escape
    /// 글자 입력 · ⌫ 등 검색창 편집 키
    case textInput
    case click(PanelColumn, Int)
    case doubleClick(PanelColumn, Int)
}

/// 리듀서 출력 중 상태 변경 외의 동작.
public enum PanelEffect: Equatable, Sendable {
    /// 이벤트를 소비하지 않고 검색창으로 흘려보낸다.
    case passThrough
    case paste(PanelColumn, index: Int, mode: PasteMode)
    /// ⌘P: 고정 / 해제
    case togglePin(PanelColumn, index: Int)
    case movePinned(index: Int, direction: MoveDirection)
    case delete(PanelColumn, index: Int)
    case close
    /// ⌘, : 패널을 닫고 설정 창을 연다
    case openSettings
}
