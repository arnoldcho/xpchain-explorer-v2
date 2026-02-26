# XPChain Explorer v2 운영 런북 (KOR)

이 문서는 `explorer.xpchain.co.kr` 기준으로 실제 구축/운영하면서 정리한 절차를 모은 운영용 가이드입니다.

## 1. 구성 요약

- Explorer 앱: `xpchain-explorer-v2` (Node.js/Express)
- 프로세스 관리: PM2 + systemd
- 리버스 프록시/SSL: Nginx + Certbot
- DB: MongoDB 7.x
- 체인 노드: `xpchaind` (`txindex=1` 권장)
- 도메인: `explorer.xpchain.co.kr`

### 1.1 현재 운영 확정값

- PM2 systemd 서비스: `pm2-arnold`
- Cron 로그 경로: `/home/arnold/xpchain-explorer-v2/logs/cron-sync-blocks.log`, `/home/arnold/xpchain-explorer-v2/logs/cron-sync-peers.log`
- 공급량 계산 모드: `settings.json > sync.supply = "TXOUTSET"`

## 2. 서버 기본 준비

### 2.1 패키지/도구

```bash
sudo apt update
sudo apt install -y git curl build-essential nginx ufw
```

Node.js 20, MongoDB 7 설치 후 버전 확인:

```bash
node -v
npm -v
mongod --version
```

### 2.2 방화벽

```bash
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw allow 3001/tcp
sudo ufw enable
sudo ufw status
```

## 3. XPChain 노드 설정

`~/.xpchain/xpchain.conf` 예시:

```conf
server=1
daemon=1
txindex=1
rpcuser=YOUR_RPC_USER
rpcpassword=YOUR_RPC_PASSWORD
rpcallowip=127.0.0.1
rpcport=8762
```

노드 실행 및 확인:

```bash
cd ~/XPChain
./xpchaind -daemon
./xpchain-cli getblockchaininfo
./xpchain-cli getnetworkinfo | grep connections
```

피어 0일 때 수동 연결 예시:

```bash
./xpchain-cli addnode "158.247.214.189:8798" "onetry"
./xpchain-cli getpeerinfo | head
```

동기화 모니터링:

```bash
watch -n 10 "~/XPChain/xpchain-cli getblockchaininfo | egrep 'blocks|headers|verificationprogress|initialblockdownload'"
```

## 4. Explorer 설치

```bash
cd ~
git clone https://github.com/arnoldcho/xpchain-explorer-v2.git
cd xpchain-explorer-v2
npm install
./scripts/init_xpchain_v2.sh
```

`settings.json`에서 최소 필수 수정:

- `dbsettings.user`
- `dbsettings.password`
- `wallet.username`
- `wallet.password`
- `webserver.port` (기본 3001)

## 5. MongoDB 사용자/권한

```bash
mongosh
```

```javascript
use xpchain_explorer_v2
db.createUser({
  user: "xpchain",
  pwd: "STRONG_PASSWORD",
  roles: [{ role: "readWrite", db: "xpchain_explorer_v2" }]
})
exit
```

## 6. 초기 인덱싱/동기화

초기 적재:

```bash
npm run sync-blocks
```

대용량 적재 시(스택/메모리 확장):

```bash
node --max-old-space-size=4096 --stack-size=20000 scripts/sync.js index update
```

피어 동기화:

```bash
npm run sync-peers
```

## 7. 앱 실행 (PM2)

기본 실행:

```bash
pm2 start npm --name xpchain-explorer-v2 -- start
pm2 save
pm2 status
```

현재 운영 프로세스(예시):

- App: `xpchain-explorer-v2` (`online`)
- Module: `pm2-logrotate` (`online`)

### 7.1 부팅 자동시작(systemd)

환경에 따라 기본 `pm2 startup` 결과가 `inactive (dead)`가 될 수 있어 아래 형태 권장.

`/etc/systemd/system/pm2-arnold.service` 핵심:

```ini
[Service]
Type=simple
User=arnold
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=PM2_HOME=/home/arnold/.pm2
Restart=always
RestartSec=5
ExecStart=/usr/lib/node_modules/pm2/bin/pm2 resurrect --no-daemon
ExecReload=/usr/lib/node_modules/pm2/bin/pm2 reload all
ExecStop=/usr/lib/node_modules/pm2/bin/pm2 kill
```

적용:

```bash
pm2 save
sudo systemctl daemon-reload
sudo systemctl enable --now pm2-arnold
systemctl status pm2-arnold --no-pager
pm2 status
```

## 8. Nginx + HTTPS

`/etc/nginx/sites-available/xpchain-explorer-v2` 예시:

```nginx
server {
    server_name explorer.xpchain.co.kr;

    location / {
        limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;
        limit_req zone=api_limit burst=30 nodelay;
        limit_conn addr_conn 30;

        proxy_pass http://127.0.0.1:3001;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

        proxy_connect_timeout 10s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        send_timeout 60s;
    }

    listen 443 ssl;
    ssl_certificate /etc/letsencrypt/live/explorer.xpchain.co.kr/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/explorer.xpchain.co.kr/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
}

server {
    listen 80;
    server_name explorer.xpchain.co.kr;
    return 301 https://$host$request_uri;
}
```

검증/적용:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

## 9. Cron 운영

권장 주기:

- 블록 동기화: 1분
- 피어 동기화: 5분

```cron
*/1 * * * * cd /home/arnold/xpchain-explorer-v2 && flock -n /tmp/xpc-sync.lock node --stack-size=20000 scripts/sync.js index update >> /home/arnold/xpchain-explorer-v2/logs/cron-sync-blocks.log 2>&1
*/5 * * * * cd /home/arnold/xpchain-explorer-v2 && flock -n /tmp/xpc-peers.lock node --stack-size=20000 scripts/sync.js peers >> /home/arnold/xpchain-explorer-v2/logs/cron-sync-peers.log 2>&1
```

`flock -n`은 이전 작업이 아직 실행 중이면 새 실행을 건너뛰어 동기화 작업 중복 실행을 방지합니다.

현재 운영 crontab에 포함된 백업/정리 작업(예시):

```cron
# Daily 03:00 - MongoDB backup (gzip archive)
0 3 * * * mkdir -p /home/arnold/backups/mongo && mongodump --db xpchain_explorer_v2 --gzip --archive=/home/arnold/backups/mongo/xpchain_explorer_v2-$(date +\%F).archive.gz >> /home/arnold/backups/backup.log 2>&1

# Daily 03:20 - Lightweight wallet backup (wallet.dat + xpchain.conf)
20 3 * * * mkdir -p /home/arnold/backups/xpchain-lite && tar -czf /home/arnold/backups/xpchain-lite/xpchain-lite-$(date +\%F).tar.gz /home/arnold/.xpchain/wallet.dat /home/arnold/.xpchain/xpchain.conf >> /home/arnold/backups/backup.log 2>&1

# Weekly Sunday 04:00 - Full ~/.xpchain backup
0 4 * * 0 mkdir -p /home/arnold/backups/xpchain-full && tar -czf /home/arnold/backups/xpchain-full/xpchain-full-$(date +\%F).tar.gz /home/arnold/.xpchain >> /home/arnold/backups/backup.log 2>&1

# Delete MongoDB backups older than 14 days
40 4 * * * find /home/arnold/backups/mongo -type f -name '*.archive.gz' -mtime +14 -delete >> /home/arnold/backups/backup.log 2>&1
```

## 10. 백업 정책 (예시)

수동 백업:

```bash
mongodump --db xpchain_explorer_v2 --out ~/backups/mongo/manual-$(date +%F)
tar -czf ~/backups/xpchain/xpchain-core-$(date +%F).tar.gz ~/.xpchain
```

자동 백업 + 정리(예시):

```cron
# 매일 03:10 MongoDB 백업
10 3 * * * mkdir -p /home/arnold/backups/mongo && mongodump --db xpchain_explorer_v2 --out /home/arnold/backups/mongo/auto-$(date +\%F) >> /home/arnold/logs/backup-mongo.log 2>&1
# 14일 초과 MongoDB 백업 삭제
40 3 * * * find /home/arnold/backups/mongo -maxdepth 1 -type d -name 'auto-*' -mtime +14 -exec rm -rf {} \; >> /home/arnold/logs/backup-mongo.log 2>&1

# 매일 03:20 체인 데이터 백업
20 3 * * * mkdir -p /home/arnold/backups/xpchain && tar -czf /home/arnold/backups/xpchain/xpchain-core-$(date +\%F).tar.gz /home/arnold/.xpchain >> /home/arnold/logs/backup-xpchain.log 2>&1
# 7일 초과 체인 백업 삭제
50 3 * * * find /home/arnold/backups/xpchain -maxdepth 1 -type f -name 'xpchain-core-*.tar.gz' -mtime +7 -delete >> /home/arnold/logs/backup-xpchain.log 2>&1
```

## 11. 로그/모니터링

```bash
pm2 status
pm2 logs --lines 100
pm2 monit

# PM2 로그 용량 확인
du -sh ~/.pm2/logs

# Nginx 접근 상위 IP
sudo awk '{print $1}' /var/log/nginx/access.log | sort | uniq -c | sort -nr | head

# 특정 API 호출 상위 IP
sudo grep '/api/getrawtransaction' /var/log/nginx/access.log | awk '{print $1}' | sort | uniq -c | sort -nr | head
```

## 12. 자주 겪는 이슈

### 12.1 `GET /api/getrawtransaction ... code -8`

원인: 빈 `txid` 또는 잘못된 형식 요청 유입.

현 상태:
- `/api/getrawtransaction?txid=`는 400으로 방어 처리됨.

### 12.2 `GET /api/getrawtransaction ... code -5`

원인:
- 유효한 64자리 hex 형식이지만 체인/멤풀에 존재하지 않는 `txid` 조회(스캐너/봇 트래픽에서 흔함).

현 상태:
- `code -5`는 서버 내부 오류가 아니라 "미존재 tx"로 간주.
- API는 404(JSON)로 응답하도록 처리해 에러 로그 노이즈를 줄임.

운영 팁:
- Nginx access log에서 상위 IP 확인 후 rate limit 또는 차단 적용.

### 12.3 `connect() failed (111: Connection refused) while connecting to upstream`

원인: 앱(3001)이 죽었거나 재시작 중.

조치:

```bash
ss -lntp | grep 3001
pm2 status
pm2 restart 0
curl -I http://127.0.0.1:3001
```

### 12.4 `RPC timeout of 5000ms exceeded`

원인: 노드 부하/지연, RPC 응답 지연.

조치:
- 노드와 Explorer 분리 운영
- 동기화 작업 시간대 분리
- Nginx timeout 및 rate limit 조정

### 12.5 Sass deprecation warning

- 현재는 경고이며 실행에는 큰 영향 없음
- 추후 Sass 3.0 이전에 theme scss 함수(`lighten/darken`) 정리 필요

### 12.6 `getmoneysupply`가 0으로 표시됨

원인:
- 코어 버전에서 `getinfo`가 제거되었는데 `sync.supply`가 `GETINFO`로 설정된 경우.

조치:

```bash
# settings.json
"sync": {
  "supply": "TXOUTSET"
}

# 적용(공급량 재계산/저장)
cd ~/xpchain-explorer-v2
node --stack-size=20000 scripts/sync.js index update
```

검증:

```bash
curl http://127.0.0.1:3001/ext/getmoneysupply
~/XPChain/xpchain-cli gettxoutsetinfo | jq .total_amount
```

### 12.6 Network Hashrate 차트 첫 점만 비정상적으로 낮음

원인:
- `networkhistories`의 가장 오래된 레코드 1건에 단위가 섞인 낮은 `nethash` 값이 저장된 경우.

조치(해당 레코드 삭제):

```javascript
mongosh
use xpchain_explorer_v2
db.networkhistories.find({}, {blockindex:1, nethash:1, _id:0}).sort({blockindex:1}).limit(10)
db.networkhistories.deleteOne({ blockindex: <문제_블록높이>, nethash: <문제_값> })
```

참고:
- `network_history.max_saved_records`(기본 120)로 오래된 레코드는 순차적으로 제거됩니다.

## 13. XPChain 커스터마이징 반영 파일

- 주요 UI 스타일: `public/css/custom.scss`
- 기본 설정 템플릿: `settings.json.template`
- 기본 설정 코드: `lib/settings.js`
- 공통 레이아웃/메타: `views/layout.pug`
- Movement 뷰: `views/movement.pug`

## 14. 배포 체크리스트

1. `git pull`
2. `npm install` (의존성 변경 시)
3. `pm2 restart 0`
4. `pm2 save`
5. `sudo nginx -t && sudo systemctl reload nginx`
6. 브라우저 강력 새로고침 (`Ctrl+Shift+R`)

## 15. 참고

- Repository: https://github.com/arnoldcho/xpchain-explorer-v2
- Upstream: https://github.com/vecocoin/eiquidus-explorer
