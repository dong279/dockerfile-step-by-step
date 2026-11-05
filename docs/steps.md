# 단계별 설명

[← README](../README.md)

각 단계의 파일 구성과 핵심 내용입니다. 명령은 **해당 단계 폴더 안에서** 실행합니다. 자세한 명령은 각 폴더의 `실행방법.txt` 또는 `README.md`에 있습니다.

| 구분 | 단계 |
|---|---|
| 기본 | [01](#01-nginx-single-html) · [02](#02-nginx-static-files) · [03](#03-node-basic) · [04](#04-node-healthcheck) · [05](#05-python-fastapi) · [06](#06-java-multistage) |
| 프론트엔드 | [07-1](#07-1-react-vite) · [07-2](#07-2-react-memo-flyway) |
| 백엔드 | [08-1](#08-1-springboot-maven) · [08-2](#08-2-springboot-mariadb) · [08-3](#08-3-springboot-flyway-dockercompose) |
| 배포 | [08-4](#08-4-ec2-deploy) |
| LLM | [09](#09-langchain-uv) · [10](#10-langchain-rag-uv) · [10-ec2](#10-ec2-deploy) |

---

### 01-nginx-single-html

[📁 폴더](../01-nginx-single-html)

HTML 파일 하나를 Nginx로 서비스합니다. Dockerfile의 가장 기본 구조인 **베이스 이미지 선택 → 파일 복사 → 실행 명령** 세 줄을 익힙니다.

- 파일: `Dockerfile`, `index.html`
- 핵심: Nginx를 `daemon off;`로 **포그라운드** 실행해야 컨테이너가 유지되는 이유

```bash
docker build -t my-simple-website .
docker run -d -p 8087:80 --name my-web my-simple-website
```

### 02-nginx-static-files

[📁 폴더](../02-nginx-static-files)

HTML, CSS, 이미지 폴더처럼 **여러 파일**을 함께 서비스합니다.

- 파일: `Dockerfile`, `index.html`, `style.css`, `images/`
- 핵심: `WORKDIR`로 기준 폴더를 정하고 `.`으로 복사하기, `EXPOSE`는 문서화일 뿐 실제로 포트를 열지 않는다는 점

### 03-node-basic

[📁 폴더](../03-node-basic)

Express로 만든 Node.js 웹 서버입니다. 처음으로 이미지 안에서 **패키지를 설치**합니다.

- 파일: `Dockerfile`, `app.js`, `package.json`
- 핵심: `package.json`을 먼저 복사하고 `npm install`한 뒤 소스를 복사하는 **의존성 캐싱 패턴**, `ENV`로 환경 변수 설정

### 04-node-healthcheck

[📁 폴더](../04-node-healthcheck) · [📄 README](../04-node-healthcheck/README.md)

03단계에 **헬스체크**를 추가해, Docker가 앱이 실제로 응답하는지 주기적으로 확인하게 합니다.

- 파일: `Dockerfile`, `app.js`, `healthcheck.js`, `package.json`, `.dockerignore`
- 핵심: `Up`과 `healthy`의 차이, 헬스체크 출력은 `docker logs`가 아니라 `docker inspect`로 확인, `.dockerignore`로 `node_modules` 제외

### 05-python-fastapi

[📁 폴더](../05-python-fastapi)

Python FastAPI 앱을 pip로 설치하고 uvicorn으로 실행합니다.

- 파일: `Dockerfile`, `requirements.txt`, `app/main.py`
- 핵심: `--host 0.0.0.0`으로 실행해야 컨테이너 밖에서 접속 가능 (`127.0.0.1`이면 접속 불가)

### 06-java-multistage

[📁 폴더](../06-java-multistage)

외부 라이브러리 없이 JDK 내장 기능만으로 만든 Java 웹 서버입니다. 처음으로 **멀티 스테이지 빌드**를 사용합니다.

- 파일: `Dockerfile`, `Main.java`
- 핵심: JDK로 컴파일하고 결과물(`.class`)만 가벼운 JRE 이미지로 옮겨 최종 이미지 크기 줄이기

---

### 07-1-react-vite

[📁 폴더](../07-1-react-vite)

Vite로 만든 React 앱을 빌드해 Nginx로 서비스합니다. 06단계의 멀티 스테이지를 **프론트엔드**에 적용합니다.

- 파일: `Dockerfile`, `nginx.conf`, `package.json`, `vite.config.js`, `index.html`, `src/`, `.dockerignore`
- 핵심: Node로 빌드 → 정적 파일만 Nginx로, SPA 새로고침 404를 막는 `try_files` 설정, 빌드 단계에서는 `--omit=dev`를 쓰면 안 되는 이유

### 07-2-react-memo-flyway

[📁 폴더](../07-2-react-memo-flyway) · [📄 README](../07-2-react-memo-flyway/README.md) · [GitHub: React_Flyway_GitActions](https://github.com/vega2krookies5/React_Flyway_GitActions)

08-3 메모 API를 사용하는 React 클라이언트입니다. 07-1의 정적 사이트에 **서버 연결(프록시)**과 **이미지 배포**를 더합니다.

- 파일: `Dockerfile`, `nginx/default.conf.template`, `vite.config.js`, `.env.development`, `src/api/memoApi.js`, `src/components/`, `.github/workflows/docker.yml`
- 핵심:
  - React는 항상 자기 주소의 `/api`로만 요청하고, **프록시**가 서버로 전달 → CORS 설정 불필요
  - 개발은 Vite 프록시(`vite.config.js`), 배포는 nginx(`proxy_pass`)가 같은 역할, 경로는 바꾸지 않고 그대로 전달
  - nginx 템플릿의 `${BACKEND_URL}`을 **컨테이너 시작 시** 주입 → 같은 이미지를 로컬과 EC2에서 그대로 사용
  - `docker run --network boot-flyway_default`로 08-3 compose의 `app`에 연결
  - main에 push하면 GitHub Actions가 `boot-flyway-web` 이미지를 Docker Hub에 업로드

```bash
npm install && npm run dev                                   # 개발: http://localhost:5173
docker build -t hubusername/boot-flyway-web:latest .         # 배포 이미지 확인
docker run -d --name boot-flyway-web --network boot-flyway_default -e BACKEND_URL=http://app:8080 -p 3000:80 hubusername/boot-flyway-web:latest
```

단계별 배포 문서: [1. 로컬 개발](../07-2-react-memo-flyway/docs/01-local-dev.md) · [2. Docker 로컬](../07-2-react-memo-flyway/docs/02-docker-local.md) · [3. GitHub Actions](../07-2-react-memo-flyway/docs/03-github-actions.md) · [4. EC2 배포](../07-2-react-memo-flyway/docs/04-ec2-deploy.md) · [문제 해결](../07-2-react-memo-flyway/docs/05-troubleshooting.md)

---

### 08-1-springboot-maven

[📁 폴더](../08-1-springboot-maven) · [📄 README](../08-1-springboot-maven/README.md)

Spring Boot 앱을 Maven으로 빌드해 JRE로 실행합니다.

- 파일: `Dockerfile`, `pom.xml`, `src/main/java/...`, `src/main/resources/application.properties`, `.dockerignore`
- 핵심: `mvn dependency:go-offline`으로 의존성 캐싱, `CMD` 대신 `ENTRYPOINT`를 써서 실행 옵션 덧붙이기, Actuator `/actuator/health`로 헬스체크

### 08-2-springboot-mariadb

[📁 폴더](../08-2-springboot-mariadb) · [📄 README](../08-2-springboot-mariadb/README.md)

08-1단계 앱에 MariaDB를 붙인 메모 API입니다. 처음으로 **앱 컨테이너와 DB 컨테이너를 함께** 실행합니다.
Dockerfile보다 `docker run` 옵션이 핵심이라 08단계의 확장편으로 두었습니다.

- 파일: `Dockerfile`, `pom.xml`, `src/`, `db/init/01-revoke-drop.sql`, `.env.example`, `.dockerignore`
- 핵심:
  - 컨테이너 안의 `localhost`는 자기 자신이라 DB에 닿지 않음 → `docker network`로 연결하고 **컨테이너 이름**으로 접속
  - 볼륨(`-v`)으로 컨테이너를 지워도 DB 데이터 유지
  - 환경 변수로 DB와 계정 자동 생성, 초기화 SQL로 DROP 권한 회수 (볼륨이 비어 있을 때 한 번만)

```bash
docker network create boot-net
# MariaDB → 앱 순서로 실행 (자세한 옵션은 실행방법.txt)
```

### 08-3-springboot-flyway-dockercompose

[📁 폴더](../08-3-springboot-flyway-dockercompose) · [📄 README](../08-3-springboot-flyway-dockercompose/README.md) · [GitHub: SpringBoot_Flyway_GitActions](https://github.com/vega2krookies5/SpringBoot_Flyway_GitActions)

08-2와 같은 앱을 **Docker Compose**로 실행하고, 테이블을 **Flyway** 마이그레이션으로 관리합니다.
08-2에서 명령 여러 개와 실행 순서로 맞추던 것을 `compose.yaml` 파일 하나로 정리하고, GitHub Actions로 이미지를 배포합니다.

- 파일: `compose.yaml`, `Dockerfile`, `pom.xml`, `src/main/resources/db/migration/V1~V3__...sql`, `db/init/01-revoke-drop.sql`, `.env.example`, `.github/workflows/maven.yml`
- 핵심:
  - `depends_on: condition: service_healthy`로 MariaDB가 준비된 뒤 앱을 자동으로 시작
  - 테이블은 Flyway SQL 파일로만 변경, JPA는 `ddl-auto=validate`로 검사만
  - 적용된 마이그레이션은 수정하지 않고 새 버전(V3 수정 시각, V4...)으로 추가
  - API 경로는 `/api/memos` (`@RequestMapping`), 상태 확인은 `/actuator/health`
  - `./db/init` 상대 경로가 그대로 동작해 Git Bash, PowerShell 명령이 같아짐
  - 앱 컨테이너에는 root 비밀번호를 전달하지 않음 (`environment:` + `${...}` 치환)
  - main에 push하면 GitHub Actions가 `boot-flyway-app` 이미지를 Docker Hub에 업로드

```bash
docker compose up -d --build
docker compose logs -f app                 # Flyway 마이그레이션 로그 (V1~V3)
curl http://localhost:8080/api/memos
```

---

### 08-4-ec2-deploy

[📁 폴더](../08-4-ec2-deploy) · [📄 README](../08-4-ec2-deploy/README.md) · [📄 EC2 배포 단계별 문서](../07-2-react-memo-flyway/docs/04-ec2-deploy.md)

07-2(web)와 08-3(app) 이미지, MariaDB 공식 이미지를 **AWS EC2 한 대**에서 Docker Compose로 실행합니다. EC2에서는 소스를 빌드하지 않고 Docker Hub 이미지를 **받아서 실행만** 합니다.

- 파일: `compose.yaml`, `.env.example`, `db/init/01-revoke-drop.sql`, `setup-ec2.sh`
- 핵심:
  - `build:` 없이 `image:`만 사용 → EC2에는 소스, Node, JDK 불필요
  - 외부에 여는 포트는 web의 **80** 하나, app(8080)과 DB(3306)는 Docker 내부 네트워크에서만 통신
  - 보안 그룹은 22(내 IP), 80만 허용 (CORS와 마찬가지로 컨테이너끼리의 통신은 보안 그룹을 거치지 않음)
  - `setup-ec2.sh`: Docker, Compose 플러그인, 스왑 2GB (Amazon Linux 2023은 `dnf`에 Compose가 없음)
  - 시작 순서 mariadb(healthy) → app(healthy) → web, 작은 인스턴스용 `mem_limit`
  - 인스턴스: Amazon Linux 2023 (kernel-6.18), **x86**, t3.small 이상 권장
  - 고정 주소는 탄력적 IP, 실습이 끝나면 **릴리스**해야 요금이 멈춤

```bash
# 내 PC
scp -i ./keys/my-key.pem -r ./ec2-deploy ec2-user@<EC2 IP>:~/     # 끝의 :~/ 필수
# EC2
cd ~/ec2-deploy && bash setup-ec2.sh                               # 처음 한 번, 다시 접속
docker compose pull && docker compose up -d
```

브라우저에서는 `http://<EC2 IP>`처럼 **`http://`를 직접 입력**합니다 (생략하면 Chrome이 https로 접속해 시간 초과).

> `ec2-deploy/` 폴더는 08-4를 복사해 실제 EC2에 올린 폴더입니다. 실제 비밀번호가 든 `.env`가 있으니 Git에 올리지 않도록 주의하세요.

---

### 09-langchain-uv

[📁 폴더](../09-langchain-uv) · [📄 README](../09-langchain-uv/README.md)

LangChain으로 Groq 모델을 호출하는 FastAPI 서버입니다. 의존성을 **uv**로 관리합니다.

- 파일: `Dockerfile`, `pyproject.toml`, `uv.lock`, `010_FastAPI_Basic.py`, `010_FastAPI_stream_test.html`, `.env.example`, `.dockerignore`
- 핵심: `uv sync --locked`로 정확한 버전 설치, **API 키를 이미지에 넣지 않고** `docker run --env-file .env`로 전달, slim 이미지에서 Python으로 헬스체크

### 10-langchain-rag-uv

[📁 폴더](../10-langchain-rag-uv) · [📄 README](../10-langchain-rag-uv/README.md)

PDF를 업로드하면 문서 내용을 근거로 답변하는 RAG Gradio 앱입니다 (FAISS + OpenAI `gpt-6-luna`, 임베딩 `text-embedding-3-small`).

- 파일: `Dockerfile`, `pyproject.toml`, `uv.lock`, `04main_rag_faiss_gradio_openai.py`, `.env.example`, `.dockerignore`
- 핵심:
  - 접속 주소와 포트가 코드에 고정된 앱을 **환경 변수로 바꿔** 로컬과 Docker 양쪽에서 동작하게 수정
  - `PYTHONUNBUFFERED=1`로 `print()` 로그를 `docker logs`에 바로 표시
  - 모델 교체: Upstage Solar → OpenAI (`langchain-openai`, `OPENAI_API_KEY`), GPT-6 추론 모델은 `reasoning_effort="none"`일 때만 `temperature` 사용 가능
  - 하이브리드 검색: 벡터(FAISS) + 키워드(BM25, 한국어 두 글자 단위)를 합쳐 법령처럼 용어가 중요한 문서에서도 정답 청크를 찾음
  - 버전 호환 문제: Gradio 6.9 미만 (gradio-pdf 호환), Python 3.12 기준
  - 로그인: `APP_USERNAME`, `APP_PASSWORD`가 있으면 Gradio 로그인 화면 사용 (외부 공개 시 필수)

### 10-ec2-deploy

[📁 폴더](../10-ec2-deploy) · [📄 README](../10-ec2-deploy/README.md)

10단계 RAG 앱을 AWS EC2에 배포합니다. 08-4(메모 앱)와 같은 방식이지만 **외부 유료 API 키를 쓰는 앱**이라는 점이 다릅니다.

- 파일: `compose.yaml`, `.env.example`, `setup-ec2.sh`
- 핵심:
  - 이미지(`langchain-rag-app`)는 GitHub Actions 또는 `docker buildx --platform linux/amd64 --push`로 Docker Hub에 올림
  - OpenAI 키는 이미지에 넣지 않고 EC2의 `.env`(권한 600)로만 전달
  - 인터넷에 공개되므로 **로그인 필수**, OpenAI 플랫폼에서 **월 사용 한도** 설정
  - 이 앱만 올리면 `HOST_PORT=80`, 메모 앱과 같은 EC2면 `HOST_PORT=7860` + 보안 그룹 7860

```bash
scp -i ./keys/my-key.pem -r ./10-ec2-deploy ec2-user@<EC2 IP>:~/
# EC2
cd ~/10-ec2-deploy && cp .env.example .env && chmod 600 .env && nano .env
docker compose pull && docker compose up -d
```

---

[← README](../README.md)
