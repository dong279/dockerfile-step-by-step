# dockerfile-step-by-step

정적 HTML 한 장부터 DB 연동 백엔드, LLM RAG 앱, 그리고 **AWS EC2 배포**까지, **단계별로 Dockerfile 작성법을 익히는 실습 저장소**입니다.
각 단계는 앞 단계에서 배운 내용 위에 새 개념을 하나씩 더하도록 구성했습니다.

## 문서

| 문서 | 내용 |
|---|---|
| [단계별 설명](./docs/steps.md) | 01~10단계 각 폴더의 파일 구성, 핵심 내용, 실행 명령 |
| [Dockerfile 명령어 정리](./docs/dockerfile-instructions.md) | `FROM`, `COPY`, `RUN`, `ENV`, `HEALTHCHECK`, `CMD`, `ENTRYPOINT`, 멀티 스테이지 빌드, `.dockerignore` |
| [docker 명령어 정리](./docs/docker-commands.md) | `docker build`, `run`, `ps`, `logs`, `exec`, `inspect`, `rmi`, 네트워크, 볼륨, 정리 명령, 문제 해결 |
| **배포: 프론트엔드** [07-2 README](./07-2-react-memo-flyway/README.md) | 전체 배포 흐름 그림, 프록시(Vite, nginx) 흐름 그림 |
| 　└ [1. 로컬 개발 서버](./07-2-react-memo-flyway/docs/01-local-dev.md) | `npm run dev` + Vite 프록시로 서버와 연결 |
| 　└ [2. Docker로 로컬 테스트](./07-2-react-memo-flyway/docs/02-docker-local.md) | 배포와 같은 이미지를 `docker build` / `docker run`으로 확인 |
| 　└ [3. GitHub Actions → Docker Hub](./07-2-react-memo-flyway/docs/03-github-actions.md) | main에 push하면 `boot-flyway-web` 이미지 자동 빌드, 업로드 |
| 　└ [4. AWS EC2 배포](./07-2-react-memo-flyway/docs/04-ec2-deploy.md) | EC2 생성, 보안 그룹, `scp`, `docker compose pull` / `up`, 탄력적 IP |
| 　└ [문제 해결](./07-2-react-memo-flyway/docs/05-troubleshooting.md) | 404, 502, 연결 시간 초과, 메모리 부족 등 |
| **배포: 백엔드** [08-3 README](./08-3-springboot-flyway-dockercompose/README.md) | 메모 API(`/api/memos`), Flyway, GitHub Actions(`maven.yml`) → `boot-flyway-app` 이미지 |
| **배포: EC2 실행 파일** [08-4 README](./08-4-ec2-deploy/README.md) | EC2에서 web + app + mariadb를 함께 실행하는 `compose.yaml`, `setup-ec2.sh` |
| **배포: RAG 앱** [10-ec2-deploy README](./10-ec2-deploy/README.md) | PDF 질의응답 Gradio 앱을 EC2에 배포 (로그인 필수, OpenAI 키는 `.env`로만) |
| **Kubernetes: 메모 앱** [11 README](./11-k8s-memo-3tier/README.md) | Pod → Deployment → Service → ConfigMap → Secret → PVC 단계별 3티어 배포 (minikube, GKE) |
| **Kubernetes: RAG 앱** [12 README](./12-k8s-rag/README.md) | RAG 앱을 minikube, GKE에 배포, `sessionAffinity`, GCP Secret Manager 연동 |

배포 단계(07-2, 08-3)는 GitHub 저장소로도 분리되어 있습니다.

| 폴더 | GitHub 저장소 | Docker Hub 이미지 |
|---|---|---|
| `07-2-react-memo-flyway` | [React_Flyway_GitActions](https://github.com/vega2krookies5/React_Flyway_GitActions) | `hubusername/boot-flyway-web` |
| `08-3-springboot-flyway-dockercompose` | [SpringBoot_Flyway_GitActions](https://github.com/vega2krookies5/SpringBoot_Flyway_GitActions) | `hubusername/boot-flyway-app` |

## 저장소 구조

```
dockerfile-step-by-step/
├── README.md                              ← 지금 보는 문서 (전체 안내)
├── .gitignore
├── docs/
│   ├── steps.md                           ← 단계별 설명
│   ├── dockerfile-instructions.md         ← Dockerfile 명령어 정리
│   └── docker-commands.md                 ← docker 명령어 정리
├── 01-nginx-single-html/
├── 02-nginx-static-files/
├── 03-node-basic/
├── 04-node-healthcheck/
├── 05-python-fastapi/
├── 06-java-multistage/
├── 07-1-react-vite/                       ← React 정적 사이트 (Node → Nginx)
├── 07-2-react-memo-flyway/                ← [배포] 메모 클라이언트 (React + nginx 프록시)
│   ├── README.md                          ← 배포 흐름, 프록시 그림
│   ├── docs/                              ← 배포 단계별 문서 (01~05)
│   ├── Dockerfile, nginx/, vite.config.js, src/
│   └── .github/workflows/docker.yml       ← Docker Hub push
├── 08-1-springboot-maven/                 ← Spring Boot 기본
├── 08-2-springboot-mariadb/               ← Spring Boot + MariaDB (docker run)
├── 08-3-springboot-flyway-dockercompose/  ← [배포] 메모 API (Compose + Flyway)
│   ├── compose.yaml, Dockerfile, src/
│   └── .github/workflows/maven.yml        ← Docker Hub push
├── 08-4-ec2-deploy/                       ← [배포] EC2 실행용 compose.yaml, setup-ec2.sh (템플릿)
├── ec2-deploy/                            ← 08-4를 복사해 실제 EC2에 올린 폴더 (.env 포함)
├── keys/                                  ← EC2 접속 키 (.pem), Git에 올리지 않음
├── 09-langchain-uv/
├── 10-langchain-rag-uv/                   ← PDF RAG Gradio 앱 (OpenAI, 하이브리드 검색, 로그인)
│   └── .github/workflows/docker.yml       ← Docker Hub push (langchain-rag-app)
├── 10-ec2-deploy/                         ← [배포] RAG 앱 EC2 실행용 compose.yaml, setup-ec2.sh
├── 11-k8s-memo-3tier/                     ← [Kubernetes] 메모 앱 3티어 (01-pod ~ 07-complete, gke/)
└── 12-k8s-rag/                            ← [Kubernetes] RAG 앱 (secret/ 예시, gke/ LoadBalancer, gke/secret-sync/ 심화)
```

모든 단계 폴더에는 `Dockerfile`(또는 `compose.yaml`)과 `실행방법.txt` 또는 `README.md`가 있습니다. 명령은 **해당 단계 폴더 안에서** 실행합니다.

## 단계 한눈에 보기

| 단계 | 앱 | 새로 배우는 내용 | 내 PC 포트 |
|---|---|---|---|
| [01](./docs/steps.md#01-nginx-single-html) | Nginx + HTML 1개 | `FROM`, `COPY`, `CMD` 기본 구조 | 8087 |
| [02](./docs/steps.md#02-nginx-static-files) | Nginx + HTML, CSS, 이미지 | `WORKDIR`, 여러 파일/폴더 복사, `EXPOSE` | 8087 |
| [03](./docs/steps.md#03-node-basic) | Node.js (Express) | 의존성 캐싱, `RUN`, `ENV` | 3000 |
| [04](./docs/steps.md#04-node-healthcheck) | Node.js + 헬스체크 | `LABEL`, `HEALTHCHECK`, `.dockerignore` | 3000 |
| [05](./docs/steps.md#05-python-fastapi) | Python FastAPI | pip + `requirements.txt`, uvicorn | 8000 |
| [06](./docs/steps.md#06-java-multistage) | 순수 Java 웹 서버 | **멀티 스테이지 빌드** (JDK → JRE) | 8080 |
| [07-1](./docs/steps.md#07-1-react-vite) | React (Vite) | 프론트엔드 멀티 스테이지 (Node → Nginx) | 8090 |
| [07-2](./docs/steps.md#07-2-react-memo-flyway) | React 메모 클라이언트 | **프록시**(Vite, nginx), 실행 시 설정 주입(`BACKEND_URL`), GitHub Actions → Docker Hub | 5173 (dev), 3000 (Docker) |
| [08-1](./docs/steps.md#08-1-springboot-maven) | Spring Boot | Maven 빌드, `ENTRYPOINT`, Actuator 헬스체크 | 8091 |
| [08-2](./docs/steps.md#08-2-springboot-mariadb) | Spring Boot + MariaDB | **컨테이너 2개 연결**, 볼륨, DB 자동 초기화 | 8092, 3306 |
| [08-3](./docs/steps.md#08-3-springboot-flyway-dockercompose) | Spring Boot + MariaDB + Flyway | **Docker Compose**, Flyway 마이그레이션, `/api` 경로, GitHub Actions → Docker Hub | 8080, 3307 |
| [08-4](./docs/steps.md#08-4-ec2-deploy) | web + app + mariadb (EC2) | **AWS EC2 배포**, 이미지로만 실행, 보안 그룹, 탄력적 IP | EC2 80 |
| [09](./docs/steps.md#09-langchain-uv) | LangChain + FastAPI | **uv**, 비밀 값 분리 (`--env-file`) | 8001 |
| [10](./docs/steps.md#10-langchain-rag-uv) | PDF RAG (Gradio) | 배포용 코드 수정, 환경 변수로 설정 분리, 하이브리드 검색 | 7860 |
| [10-ec2](./docs/steps.md#10-ec2-deploy) | RAG 앱 (EC2) | **외부 API 키를 쓰는 앱의 배포**, 로그인, 사용 한도 | EC2 80 (또는 7860) |
| [11](./docs/steps.md#11-k8s-memo-3tier) | 메모 앱 3티어 (Kubernetes) | **Pod, Deployment, Service, ConfigMap, Secret, PVC**, probe, minikube / GKE | minikube service (NodePort 30080) |
| [12](./docs/steps.md#12-k8s-rag) | RAG 앱 (Kubernetes) | 상태가 Pod 안에 있는 앱, `sessionAffinity`, GCP Secret Manager 에서 키 가져오기 | minikube service (NodePort 30786) |

배포 단계(07-2 → 08-3 → 08-4)는 이렇게 이어집니다.

```
07-2 (React)   ─ push ─▶ GitHub Actions ─▶ Docker Hub: boot-flyway-web ─┐
08-3 (Spring)  ─ push ─▶ GitHub Actions ─▶ Docker Hub: boot-flyway-app ─┼─ docker compose pull ─▶ EC2 (08-4)
                                           Docker Hub: mariadb (공식)  ─┘
```

자세한 그림은 [07-2 README의 전체 흐름](./07-2-react-memo-flyway/README.md#전체-흐름)을 참고하세요.

---

## 처음 시작할 때

1. [Docker Desktop](https://www.docker.com/products/docker-desktop/)을 설치하고 실행합니다.
2. 01단계 폴더로 이동해 `실행방법.txt`의 명령을 순서대로 실행합니다.
3. 막히면 [docker 명령어 정리의 문제 해결](./docs/docker-commands.md#문제-해결-빠른-참고)을 먼저 확인합니다.

08-2, 08-3, 08-4, 09, 10, 10-ec2단계는 `.env.example`을 `.env`로 복사해 비밀번호나 API 키를 넣어야 실행됩니다.
07-2는 PC에 [Node.js](https://nodejs.org/) 22 이상, 09, 10단계는 [uv](https://docs.astral.sh/uv/)가 설치되어 있어야 합니다.
08-4(EC2 배포)는 AWS 계정과 Docker Hub 계정이 필요합니다.
11, 12단계는 [minikube](https://minikube.sigs.k8s.io/docs/start/)(docker 드라이버)와 `kubectl`, GKE 실습은 Google Cloud 프로젝트와 `gcloud` CLI가 필요합니다.

## 주의

- `.env`에는 비밀번호와 API 키가 들어가므로 **Git에 올리지 않습니다.** 루트 `.gitignore`에서 제외되어 있습니다.
- EC2 접속 키(`keys/`, `*.pem`)도 **Git에 올리지 않습니다.** 키가 유출되면 누구나 서버에 접속할 수 있습니다.
- `uv.lock`, `.env.example`, `.python-version`은 다른 사람이 같은 환경으로 실행할 수 있도록 **올립니다.**
- EC2 실습이 끝나면 인스턴스를 종료하고 **탄력적 IP를 릴리스**하세요. 연결하지 않은 탄력적 IP도 요금이 나옵니다 ([EC2 실습 정리 방법](./07-2-react-memo-flyway/docs/04-ec2-deploy.md#8-실습을-마칠-때)).
