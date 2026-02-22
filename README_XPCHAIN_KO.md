# XPChain Explorer v2 빠른 시작 (eIquidus 기반)

이 저장소는 `vecocoin/eiquidus-explorer`를 기반으로 XPChain에 맞춰 운영하기 위한 초기 세팅 버전입니다.

## 1) 사전 준비

- Node.js 20 LTS 권장
- MongoDB 7.x 권장
- `xpchaind` 동기화 완료

`xpchaind`는 전체 트랜잭션 조회를 위해 `txindex=1` 권장:

```conf
# xpchain.conf 예시
server=1
txindex=1
rpcuser=YOUR_RPC_USER
rpcpassword=YOUR_RPC_PASSWORD
rpcport=8762
rpcallowip=127.0.0.1
```

참고:
- XPChain P2P 기본 포트: `8798`
- XPChain RPC 기본 포트: `8762`

## 2) XPChain 기본 설정 파일 생성

```bash
cd ~/xpchain-explorer-v2
./scripts/init_xpchain_v2.sh
```

위 스크립트가 `settings.json`을 만들고 아래를 기본 반영합니다.
- 코인명/심볼: `XPChain` / `XPC`
- RPC 포트: `8762`
- 테마/타이틀 기본값
- masternodes 페이지 비활성화

그 후 `settings.json`에서 아래 항목은 반드시 실제 값으로 수정:
- `dbsettings.user`
- `dbsettings.password`
- `wallet.username`
- `wallet.password`

## 3) 설치 및 초기 동기화

```bash
npm install
npm run sync-blocks
```

필요하면 추가 동기화:

```bash
npm run sync-peers
npm run sync-markets
```

## 4) 실행

```bash
npm start
```

기본 웹 포트는 `settings.json`의 `webserver.port`를 따릅니다 (기본 3001).

## 5) 운영 권장

- PM2/systemd로 프로세스 관리
- `sync-blocks`를 cron으로 1분 주기 실행
- MongoDB 백업/모니터링(디스크, 메모리, WT 상태) 필수

---

원본 업스트림:
- https://github.com/vecocoin/eiquidus-explorer
