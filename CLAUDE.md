# macOS SwiftUI App — Agent Guide

이 프로젝트의 패턴을 따르는 macOS 앱 개발 가이드. 새 프로젝트에서도 동일한 구조를 사용한다.

## 빌드

```bash
xcodegen generate && xcodebuild -project *.xcodeproj -scheme <AppName> -configuration Debug build
```

- **XCodeGen** 사용. `project.yml`이 프로젝트 설정의 소스.
- `sources: <AppName>` — 폴더 내 모든 Swift 파일 자동 포함. 새 파일 추가 후 `xcodegen generate` 필요.
- Release 빌드: `-configuration Release`

## 프로젝트 구조

```
<AppName>/
├── project.yml                  # XCodeGen 설정 (버전, 빌드설정 등)
├── <AppName>/
│   ├── Info.plist               # LSUIElement, URL Scheme 등
│   ├── <AppName>.entitlements   # 권한
│   ├── Localizable.xcstrings    # 다국어 (JSON, en/ko)
│   ├── Assets.xcassets/
│   │   ├── AppIcon.appiconset/  # 16~1024px
│   │   └── MenuBarIcon.imageset/# 18/36px, template rendering
│   ├── Models/                  # 데이터 모델
│   ├── Services/                # 비즈니스 로직, 저장소
│   └── Views/                   # SwiftUI 뷰
```

## 핵심 패턴

### 1. project.yml

```yaml
settings:
  base:
    MARKETING_VERSION: "1.0.0"
    SWIFT_VERSION: "5.9"
    MACOSX_DEPLOYMENT_TARGET: "14.0"
    ENABLE_HARDENED_RUNTIME: true
    ENABLE_APP_SANDBOX: false
    SWIFT_EMIT_LOC_STRINGS: true
    CODE_SIGN_IDENTITY: "-"
```

### 2. @Observable Store (영속 저장)

```swift
@Observable
final class ConfigStore {
    private(set) var configs: [Model] = []
    private let fileURL: URL  // ~/Library/Application Support/<AppName>/

    func add/update/delete → save()  // CRUD 후 즉시 저장
}
```
- JSON 파일 저장: `JSONEncoder` with `.prettyPrinted, .sortedKeys`, `.atomic` 쓰기
- 새 필드 추가 시 `init(from:)`에서 `decodeIfPresent` 사용 (하위 호환)

### 3. Draft 패턴 (Detail View)

```swift
@State private var draft = Model()

.onAppear { loadDraft() }
.onChange(of: id) { _, _ in loadDraft() }
.onChange(of: draft) { _, newValue in store.update(newValue) }
```
- 로컬 `@State` draft → `onChange`로 자동 저장
- 저장/취소 버튼 불필요

### 4. NavigationSplitView

```swift
NavigationSplitView {
    // sidebar: List(selection: $selection) + .tag(item.id)
} detail: {
    if let id = selection { DetailView(id: id) }
    else { ContentUnavailableView { ... } }
}
```
- 선택: `@State private var selection: UUID?`
- 삭제 시 `if selection == id { selection = nil }`

### 5. Sheet 팝업

```swift
VStack(spacing: 12) {
    HStack { Text("Title").font(.headline); Spacer() }
    // content (ScrollView, TextEditor, List 등)
    HStack { Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
}
.padding()
.frame(width: 500, height: 400)
```

### 6. Toolbar

```swift
@ToolbarContentBuilder
private var myToolbar: some ToolbarContent {
    ToolbarItem(placement: .primaryAction) { ... }  // 주요 액션
    ToolbarItem(placement: .automatic) { ... }       // 보조 액션
}
```
- `.help(String(localized: "..."))` 으로 툴팁
- `.keyboardShortcut("i", modifiers: .command)` 으로 단축키

### 7. MenuBarExtra (메뉴바 앱)

```swift
// Info.plist: LSUIElement = true
MenuBarExtra {
    MenuBarView(...)
} label: {
    Image("MenuBarIcon")
}

Window("Title", id: "main") { ... }
```
- `@Environment(\.openWindow)` + `NSApp.activate(ignoringOtherApps: true)`로 창 열기

### 8. Context Menu

```swift
.contextMenu {
    Button("Action") { ... }
    Divider()
    Button("Delete", role: .destructive) { ... }
}
```

### 9. 서비스 레이어

| 패턴 | 용도 | 예시 |
|------|------|------|
| `enum + static func` | 상태 없는 유틸 | KeychainService, ShareService, Parser |
| `@Observable class` | 상태 있는 서비스 | ConfigStore, ProcessManager |

### 10. 모델 레이어

```swift
// Enum: Codable + CaseIterable + Identifiable
enum Type: String, Codable, CaseIterable, Identifiable {
    var id: String { rawValue }
    var displayName: String { String(localized: "...") }
}

// Struct: Codable + Identifiable + Hashable
struct Model: Codable, Identifiable, Hashable {
    var id = UUID()
    // 기본값 있는 프로퍼티들
}
```

## 로컬라이제이션

- **모든** 사용자 노출 문자열: `String(localized: "English Key")`
- 파일: `Localizable.xcstrings` (JSON)
- 구조:
```json
"English Key": {
  "localizations": {
    "ko": {
      "stringUnit": { "state": "translated", "value": "한국어" }
    }
  }
}
```
- 알파벳순 정렬
- 번역 누락 시 영어가 폴백

## 네이밍

| 대상 | 규칙 | 예시 |
|------|------|------|
| 뷰 파일/타입 | `*View` | `TunnelListView.swift` |
| 행 뷰 | `*RowView` | `TunnelRowView.swift` |
| 모델 파일 | 도메인명 | `TunnelConfig.swift` |
| Store | `*Store` | `ConfigStore.swift` |
| Manager | `*Manager` | `SSHProcessManager.swift` |
| 정적 유틸 | `*Service` / `*Parser` | `KeychainService.swift` |

## 릴리즈 배포

### 1. 버전 올리기

`project.yml`에서 `MARKETING_VERSION` 수정.

```yaml
MARKETING_VERSION: "x.y.z"
```

### 2. Release 빌드

```bash
xcodegen generate && xcodebuild -project *.xcodeproj -scheme SSHTunnel -configuration Release build
```

빌드 결과물 경로: `~/Library/Developer/Xcode/DerivedData/SSHTunnel-*/Build/Products/Release/SSHTunnel.app`

### 3. DMG 생성

```bash
APP_PATH="$(find ~/Library/Developer/Xcode/DerivedData/SSHTunnel-*/Build/Products/Release/SSHTunnel.app -maxdepth 0)"
DMG_PATH="/tmp/SSHTunnel-x.y.z.dmg"
TMP_DIR="/tmp/dmg_staging"

rm -rf "$TMP_DIR" "$DMG_PATH"
mkdir -p "$TMP_DIR"
cp -R "$APP_PATH" "$TMP_DIR/"
ln -s /Applications "$TMP_DIR/Applications"
hdiutil create -volname "SSHTunnel" -srcfolder "$TMP_DIR" -ov -format UDZO "$DMG_PATH"
rm -rf "$TMP_DIR"
```

### 4. 커밋 & 푸시

```bash
git add -A && git commit -m "Bump version to x.y.z" && git push origin main
```

### 5. GitHub 릴리즈 생성

```bash
gh release create vx.y.z /tmp/SSHTunnel-x.y.z.dmg --title "vx.y.z" --notes "릴리즈 노트"
```

### 6. Homebrew cask 갱신

`brew`가 읽는 cask는 이 저장소가 아니라 **별도 저장소** `typostudio/homebrew-tap`의 `Casks/sshtunnel.rb` 하나뿐이다.
이 단계를 빼먹으면 릴리즈를 올려도 brew 사용자에게는 업데이트가 나가지 않는다. 이 저장소에 cask 사본을 두지 말 것.

```bash
TAP=/opt/homebrew/Library/Taps/typostudio/homebrew-tap
SHA=$(shasum -a 256 /tmp/SSHTunnel-x.y.z.dmg | awk '{print $1}')
sed -i '' "s/version \"[^\"]*\"/version \"x.y.z\"/; s/sha256 \"[^\"]*\"/sha256 \"$SHA\"/" "$TAP/Casks/sshtunnel.rb"
(cd "$TAP" && git add Casks/sshtunnel.rb && git commit -m "sshtunnel x.y.z" && git push origin main)
brew update && brew info sshtunnel   # "이전버전 → x.y.z" 로 뜨는지 확인
```

## 주의사항

- 새 Codable 필드 추가 시 **반드시** `decodeIfPresent`로 기본값 fallback (기존 데이터 손실 방지)
- Form 내 TextField placeholder 좌측정렬이 안 되면 `NSViewRepresentable` 사용
- 메뉴바 아이콘 크기는 SF Symbol이 아닌 이미지 에셋으로 제어
- `xcodegen generate` 후 빌드해야 새 파일 인식
- 한국어 번역은 코드 작성과 함께 추가
