# 08-4-ec2-deploy

08-3 백엔드(Spring Boot + Flyway)와 07-2 React 클라이언트, MariaDB를 **AWS EC2 한 대**에 Docker Compose로 올리는 예제입니다.

EC2에서는 소스를 빌드하지 않습니다. GitHub Actions가 Docker Hub에 올린 이미지를 **받아서 실행만** 합니다.

```
 GitHub (push)
   │  GitHub Actions: 빌드 + push
   ▼
 Docker Hub ──────────────── hub_username/boot-flyway-app, hub_username/boot-flyway-web
   │  docker compose pull
   ▼
 EC2 ─────────────────────────────────────────────────────────
 │  인터넷 ──80──▶ web(nginx) ──/api──▶ app:8080 ──▶ mariadb:3306
 │                 (정적 파일)          (Flyway)      (볼륨에 데이터)
 └─────────────────────────────────────────────────────────────
```

## 파일 구성

```
08-4-ec2-deploy/          ← README.md 만 있음
└── README.md
ec2-deploy/               ← 이 폴더만 EC2에 복사 (소스 코드 불필요)
├── compose.yaml          # web + app + mariadb, 모두 이미지로 실행
├── .env.example          # Docker Hub hub_username, 태그, DB 비밀번호
├── db/init/
│   └── 01-revoke-drop.sql  # 08-3과 같음 (boot 계정 DROP 회수)
└── setup-ec2.sh          # Docker, Compose, 스왑 설치 (처음 한 번)
```

### 08-3 compose.yaml과 달라진 점

| 항목 | 08-3 (내 PC) | 08-4 (EC2) |
|---|---|---|
| app 이미지 | `build: .` (소스로 빌드) | `image: hub_username/boot-flyway-app:latest` |
| web | 없음 | `image: hub_username/boot-flyway-web:latest`, 포트 80 |
| app 포트 | `8080:8080` 공개 | **공개 안 함** (nginx를 거쳐서만 호출) |
| DB 포트 | `127.0.0.1:3306` | 같음 (EC2 자신만 접속, 밖에서는 SSH 터널) |
| 메모리 | 제한 없음 | app `mem_limit: 768m`, JVM `MaxRAMPercentage=60` |
| 시작 순서 | mariadb → app | mariadb → app(healthy) → web |

* * *

## 0. 준비: Docker Hub에 이미지 두 개

GitHub Actions로 이미 올렸다면 Docker Hub에서 확인합니다.

- `hub_username/boot-flyway-app:latest` (08-3 `maven.yml`)
- `hub_username/boot-flyway-web:latest` (07-2 `docker.yml`)

> **CPU 종류를 맞춰야 합니다.** GitHub Actions(ubuntu-latest)는 **x86(amd64)** 이미지를 만듭니다. EC2도 **x86 인스턴스**(t3, t2 등)를 고르세요. ARM(Graviton, t4g 등)에서 실행하면 `exec format error`가 납니다. ARM을 쓰려면 아래 "ARM 인스턴스를 쓰려면"을 참고하세요.

## 1. EC2 인스턴스 만들기 (AWS 콘솔)

EC2 > 인스턴스 시작에서 다음과 같이 고릅니다.

| 항목 | 권장 값 | 이유 |
|---|---|---|
| AMI | **Amazon Linux 2023** (Ubuntu 24.04도 가능) | `setup-ec2.sh`가 둘 다 지원 |
| 아키텍처 | **64비트(x86)** | Docker Hub 이미지가 amd64 |
| 인스턴스 유형 | **t3.small** (2GB) 이상 | Spring Boot + MariaDB + nginx. t3.micro(1GB)는 스왑을 써도 느림 |
| 키 페어 | 새로 만들기 → `.pem` 다운로드 | SSH 접속용 (다시 받을 수 없으니 보관) |
| 스토리지 | gp3 **20GB** | 이미지 3개 + DB 데이터 |

**보안 그룹 (방화벽)**

| 유형 | 포트 | 소스 | 용도 |
|---|---|---|---|
| SSH | 22 | **내 IP** | 접속 (0.0.0.0/0 으로 열지 않기) |
| HTTP | 80 | 0.0.0.0/0 | 웹 화면 |

8080(app), 3306/3307(DB)은 **열지 않습니다.** compose에서도 외부에 공개하지 않았습니다.

> **고정 IP (선택):** 인스턴스를 중지했다가 다시 시작하면 퍼블릭 IP가 바뀝니다. 계속 같은 주소를 쓰려면 EC2 > 탄력적 IP를 할당해 인스턴스에 연결하세요. 공인 IPv4 주소와 인스턴스 요금은 AWS 요금 페이지에서 확인하고, 실습이 끝나면 인스턴스를 중지하거나 종료하세요.

## 2. 파일 복사 + SSH 접속 (내 PC)

```bash
# 키 파일 권한 (Git Bash, Mac, Linux)
chmod 400 ./keys/my-key.pem

# 이 폴더를 EC2로 복사 (Amazon Linux 사용자: ec2-user, Ubuntu: ubuntu)
# scp는 SSH 연결을 이용해 파일을 다른 컴퓨터로 복사하는 명령입니다(secure copy). 내 PC에 있는 폴더를 EC2 서버로 보내는 데 씁니다. 
# Windows의 Git #Bash와 PowerShell에도 기본으로 들어 있습니다.
scp -i ./keys/my-key.pem -r ec2-deploy ec2-user@<EC2 퍼블릭 IP>:~/

# 접속
ssh -i ./keys/my-key.pem ec2-user@<EC2 퍼블릭 IP>
```

> Windows PowerShell에서 `.pem` 권한 오류가 나면 Git Bash에서 실행하는 것이 가장 간단합니다.

## 3. Docker 설치 (EC2, 처음 한 번)

```bash
cd ~/ec2-deploy
file setup-ec2.sh                 # "with CRLF line terminators" 가 보이면 이 경우
sed -i 's/\r$//' setup-ec2.sh     # CRLF → LF 로 변환
bash setup-ec2.sh
exit                      # docker 그룹 적용을 위해 다시 접속
```

`setup-ec2.sh`가 하는 일은 다음과 같습니다.
- Docker 설치. Amazon Linux 2023의 `dnf`에는 Docker는 있지만 Compose 플러그인은 없어서 GitHub 릴리스에서 따로 설치합니다.
- 스왑 2GB 추가 (메모리가 부족해서 컨테이너가 죽는 것을 방지)
- `docker` 그룹 추가 (sudo 없이 실행)

## 4. .env 작성 + 실행 (EC2)

```bash
ssh -i ./keys/my-key.pem ec2-user@<EC2 퍼블릭 IP>
cd ~/ec2-deploy

cp .env.example .env
chmod 600 .env            # 나만 읽을 수 있게
nano .env                 # DOCKERHUB_USERNAME, 비밀번호 입력 (저장: Ctrl+O, 종료: Ctrl+X)

docker compose config     # 치환 결과 확인 (image 이름에 내 hub_username가 들어갔는지)
docker compose pull       # 이미지 3개 받기
docker compose up -d      # 실행
docker compose ps         # mariadb → app → web 순서로 healthy/Up 확인
docker compose logs -f app   # Flyway 로그 확인 (Ctrl+C 로 빠져나오기)
```

처음 실행하면 앱 로그에 다음이 보입니다.
```
Successfully applied 3 migrations to schema `boot_db`, now at version v3
```

## 5. 확인

| 주소 | 기대 결과 |
|---|---|
| `http://<EC2 퍼블릭 IP>/` | React 메모 화면, 배지 `앱 UP` `DB UP` |
| `http://<EC2 퍼블릭 IP>/api/memos` | V2가 넣은 첫 메모 (JSON) |
| `http://<EC2 퍼블릭 IP>/actuator/health` | `"status":"UP"` |
| `http://<EC2 퍼블릭 IP>:8080/api/memos` | **접속 안 됨** (정상, 외부에 공개하지 않음) |

* * *

## 새 버전 배포

코드를 고쳐 main에 push하면 GitHub Actions가 새 `latest`를 올립니다. EC2에서는 아래만 실행하면 됩니다.

```bash
cd ~/ec2-deploy
docker compose pull          # 바뀐 이미지만 새로 받음
docker compose up -d         # 바뀐 서비스만 다시 시작 (DB 데이터 유지)
docker image prune -f        # 이전 이미지 정리 (디스크 절약)
```

- Flyway가 새 마이그레이션(V4...)만 자동으로 적용합니다.
- 특정 버전으로 고정하거나 되돌리려면 `.env`의 `APP_TAG=v1`처럼 태그를 지정하고 `docker compose up -d`를 실행합니다.

## DB 접속 (내 PC의 DBeaver)

DB 포트는 인터넷에 열려 있지 않습니다. **SSH 터널**로 접속합니다.

```bash
# 내 PC에서 실행 (창을 열어 두는 동안 터널 유지)
ssh -i my-key.pem -N -L 3307:127.0.0.1:3307 ec2-user@<EC2 퍼블릭 IP>
```

DBeaver에서는 `localhost:3307`, 계정 `boot`, DB `boot_db`로 접속합니다. 또는 DBeaver 연결 설정의 SSH 탭에 EC2 주소와 `.pem`을 넣어도 됩니다.

EC2 안에서 바로 확인할 수도 있습니다.
```bash
docker compose exec mariadb mariadb -uboot -p boot_db -e "SELECT * FROM flyway_schema_history;"
```

## 재부팅되면?

`restart: unless-stopped`와 `systemctl enable docker` 덕분에 EC2를 재부팅해도 컨테이너가 자동으로 다시 시작됩니다. DB 데이터는 `boot-flyway_mariadb-data` 볼륨에 남습니다.

> `docker compose down -v`는 **DB 데이터까지 삭제**합니다. 운영 서버에서는 쓰지 마세요.

## 백업 (간단한 방법)

```bash
# EC2에서 덤프 → 내 PC로 복사
docker compose exec -T mariadb sh -c 'mariadb-dump -uroot -p"$MARIADB_ROOT_PASSWORD" boot_db' > backup.sql
# (내 PC) scp -i my-key.pem ec2-user@<IP>:~/08-4-ec2-deploy/backup.sql .
```

* * *

## 문제 해결

| 증상 | 원인 | 해결 |
|---|---|---|
| 브라우저에서 접속이 안 됨 (시간 초과) | 보안 그룹에 80 없음 | 인바운드 규칙에 HTTP 80 추가 |
| SSH 접속 시간 초과 | 보안 그룹 22의 "내 IP"가 바뀜 (와이파이 변경 등) | 인바운드 규칙의 SSH 소스를 현재 내 IP로 수정 |
| `pull access denied` | `.env`의 `DOCKERHUB_USERNAME` 오타, 또는 Docker Hub 저장소가 Private | hub_username 확인, Private 이면 EC2에서 `docker login` |
| `exec format error` | ARM 인스턴스에 x86 이미지 | x86 인스턴스 사용, 또는 아래 ARM 설정 |
| app이 계속 재시작 | DB 비밀번호 불일치, 메모리 부족 | `docker compose logs app`, `free -h` 확인 |
| app이 `Killed` / exit code 137 | 메모리 부족 (OOM) | 스왑 확인(`swapon --show`), 인스턴스 키우기 |
| `.env`를 바꿨는데 DB 계정이 그대로 | 볼륨이 이미 초기화됨 (최초 1회만 적용) | 실습 서버라면 `docker compose down -v` 후 다시 `up` (**데이터 삭제**) |
| 화면은 뜨는데 `앱 연결 안 됨` | app이 아직 시작 중이거나 실패 | `docker compose ps`, `docker compose logs app` |
| `docker: permission denied` | docker 그룹 적용 전 | `exit` 후 다시 SSH 접속 |

## ARM 인스턴스를 쓰려면 (선택)

두 GitHub Actions 파일의 Buildx 단계 앞에 QEMU를 추가하고, `build-push-action`에 `platforms`를 넣으면 x86과 ARM 이미지를 함께 만듭니다. 빌드 시간은 늘어납니다.

```yaml
      - name: Set up QEMU
        if: github.event_name == 'push'
        uses: docker/setup-qemu-action@v3

      # ... (Buildx, Login 은 그대로)

      - name: Build & push Docker image
        uses: docker/build-push-action@v6
        with:
          platforms: linux/amd64,linux/arm64
          # ... (나머지 그대로)
```

## 다음 단계

| 하고 싶은 것 | 방법 |
|---|---|
| 도메인 + HTTPS | 도메인을 EC2 IP에 연결하고, nginx 앞에 Caddy 또는 Certbot(Let's Encrypt) 추가, 보안 그룹에 443 |
| push하면 EC2에 자동 배포 | GitHub Actions 마지막에 SSH로 접속해 `docker compose pull && up -d` 실행 |
| DB를 따로 관리 | MariaDB 컨테이너 대신 Amazon RDS for MariaDB, app의 `DB_HOST`만 RDS 주소로 변경 (Flyway가 테이블 생성) |
