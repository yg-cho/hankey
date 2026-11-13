# HanKey

한영 전환 키를 바꾸는 macOS 메뉴바 앱. Caps Lock 한영 전환이 빠른 입력에서 누락되는 문제를 없앤다.

## 동작 방식

1. 메뉴에서 고른 키를 HID 단계에서 F18 로 바꾼다 (`hidutil` `UserKeyMapping`). 권한 요청과 지연이 없다.
2. 시스템 단축키 "이전 입력 소스 선택"을 F18 로 연결한다. 전환 자체는 macOS 가 한다.
3. "사용 안 함"을 고르거나 종료하면 키 매핑과 단축키를 원래 값으로 되돌린다.

### 누르는 즉시 전환

macOS 는 이 단축키를 키를 **뗄 때** 처리한다. 그래서 전환 키를 떼기 전에 다음 글자를 치면 이전 언어로 찍힌다. 메뉴의 "누르는 즉시 전환 켜기…"로 손쉬운 사용 권한을 주면, 앱이 키 누름을 받아 단축키를 대신 짧게 눌러 주므로 누른 직후 전환된다. 권한이 없으면 뗄 때 전환되는 기본 방식으로 동작한다.

ad-hoc 서명이라 앱을 다시 빌드하면 권한을 다시 줘야 한다. `HANKEY_SIGN_ID=<인증서 해시> ./scripts/build-app.sh` 로 서명하면 유지된다.

고를 수 있는 키: Caps Lock, 오른쪽 Command · Option · Shift · Control. 고른 키의 원래 기능은 앱이 켜져 있는 동안 사라진다.

## 빌드 · 설치

```bash
./scripts/build-app.sh            # dist/HanKey.app
./scripts/build-app.sh --install  # /Applications/HanKey.app 으로 복사
swift test                        # 단위 테스트
```

"로그인 시 실행"은 `/Applications` 에 설치한 뒤 켠다. 재부팅하면 키 매핑이 풀리므로 로그인 때 앱이 다시 걸어 준다.

## 진단

```bash
/Applications/HanKey.app/Contents/MacOS/HanKey --status
```

현재 키 매핑과 단축키 연결 여부를 출력한다. 아무것도 바꾸지 않는다.

## 연결이 안 될 때

메뉴에 "시스템 단축키 연결 안 됨"이 보이면 "다시 연결"을 누른다. 그래도 안 되면 키보드 설정 › 키보드 단축키 › 입력 소스 › "이전 입력 소스 선택"을 누르고 고른 키를 눌러 직접 등록한다.

스펙: [docs/spec.md](docs/spec.md)

## 라이선스

MIT
