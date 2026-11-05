#!/usr/bin/env bash
# ==========================================================
# EC2 처음 준비 스크립트 (인스턴스마다 한 번만 실행)
#
# 하는 일
#   1. Docker 설치 + 부팅 시 자동 시작
#   2. Docker Compose 플러그인 설치 (docker compose 명령)
#   3. 스왑 2GB 추가 (메모리가 작은 인스턴스에서 컨테이너가 죽지 않도록)
#   4. 현재 사용자(ec2-user)를 docker 그룹에 추가 (sudo 없이 docker 명령)
#
# 지원 OS: Amazon Linux 2023, Ubuntu 22.04 / 24.04
#
# 실행 방법 (EC2 에 SSH 로 접속한 뒤)
#   cd ~/10-ec2-deploy
#   bash setup-ec2.sh
#   exit                 ← 4번(docker 그룹)은 다시 접속해야 적용됨
#
# 여러 번 실행해도 안전함
#   - 이미 설치된 항목은 "이미 있음"을 출력하고 건너뜀
# ==========================================================

# 오류가 나면 바로 멈추기 (안전장치)
#   -e          : 명령 하나라도 실패하면 스크립트 중단 (뒤 단계가 엉뚱하게 실행되는 것 방지)
#   -u          : 정의하지 않은 변수를 쓰면 오류 (오타 방지)
#   -o pipefail : A | B 처럼 파이프로 연결된 명령 중 하나라도 실패하면 실패로 처리
set -euo pipefail

# ----------------------------------------------------------
# 0. OS 확인
# ----------------------------------------------------------
# /etc/os-release 파일에는 OS 정보가 "이름=값" 형태로 들어 있음
#   Amazon Linux 2023 : ID="amzn",   PRETTY_NAME="Amazon Linux 2023..."
#   Ubuntu            : ID=ubuntu,   PRETTY_NAME="Ubuntu 24.04 LTS"
# 앞의 . (source) 는 파일 내용을 현재 셸에서 실행 → ID, PRETTY_NAME 변수를 바로 사용 가능
. /etc/os-release
echo "== OS: ${PRETTY_NAME}"

# ----------------------------------------------------------
# 1. Docker 설치
# ----------------------------------------------------------
# command -v docker : docker 명령이 있으면 경로를 출력하고 성공(0), 없으면 실패
# >/dev/null 2>&1  : 출력과 오류 메시지를 버림 (있는지만 확인)
if command -v docker >/dev/null 2>&1; then
  echo "== Docker 이미 설치됨: $(docker --version)"

elif [ "${ID}" = "amzn" ]; then
  # Amazon Linux 2023
  # - 기본 저장소(dnf)에 docker 패키지가 있음
  # - 단, docker compose 플러그인은 없으므로 2번에서 따로 설치
  # - -y : 설치 확인 질문에 자동으로 yes
  echo "== Docker 설치 (dnf)"
  sudo dnf install -y docker

elif [ "${ID}" = "ubuntu" ]; then
  # Ubuntu
  # - Docker 공식 설치 스크립트 사용 (docker, compose 플러그인, buildx 까지 한 번에 설치)
  # - curl -fsSL : 실패 시 오류(-f), 진행 표시 숨김(-sS), 리다이렉트 따라감(-L)
  echo "== Docker 설치 (get.docker.com)"
  curl -fsSL https://get.docker.com | sudo sh

else
  # 그 밖의 OS 는 설치 방법이 달라서 중단
  # >&2 : 메시지를 오류 출력(stderr)으로 보냄
  echo "지원하지 않는 OS 입니다: ${ID}" >&2
  exit 1
fi

# Docker 서비스 시작 + 부팅할 때 자동 시작
#   enable : 재부팅 후에도 자동 실행되도록 등록
#   --now  : 등록과 동시에 지금 바로 시작
# → EC2 를 재부팅해도 Docker 가 켜지고, compose 의 restart: unless-stopped 덕분에 컨테이너도 다시 실행됨
sudo systemctl enable --now docker

# ----------------------------------------------------------
# 2. Docker Compose 플러그인 (없을 때만)
# ----------------------------------------------------------
# docker compose version 이 성공하면 이미 설치된 것
# - 아직 docker 그룹이 적용되지 않았을 수 있으므로 sudo 로도 한 번 더 확인
if docker compose version >/dev/null 2>&1 || sudo docker compose version >/dev/null 2>&1; then
  echo "== Compose 이미 설치됨"
else
  echo "== Compose 플러그인 설치"

  # CPU 종류 확인: x86_64 (t3 등 Intel/AMD) 또는 aarch64 (t4g 등 Graviton)
  # GitHub 릴리스 파일 이름이 docker-compose-linux-x86_64 / docker-compose-linux-aarch64 형태라 그대로 사용
  ARCH="$(uname -m)"

  # Docker 는 이 폴더에 있는 실행 파일을 "docker <이름>" 하위 명령으로 인식함
  # → 여기에 docker-compose 파일을 두면 "docker compose" 명령이 생김 (모든 사용자 공통)
  sudo mkdir -p /usr/local/lib/docker/cli-plugins

  # GitHub 의 최신 릴리스(latest)에서 내 CPU 에 맞는 파일을 내려받음
  sudo curl -fSL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${ARCH}" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose

  # 실행 권한 추가 (내려받은 파일은 기본적으로 실행 권한이 없음)
  sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
fi

# ----------------------------------------------------------
# 3. 스왑 2GB (없을 때만)
# ----------------------------------------------------------
# 스왑: 메모리(RAM)가 부족할 때 디스크 일부를 임시 메모리처럼 쓰는 공간
# - Gradio + LangChain + FAISS 는 PDF 를 처리할 때 메모리를 많이 씀 (t3.micro 1GB 는 빠듯함)
# - 스왑이 없으면 리눅스가 메모리를 확보하려고 컨테이너를 강제 종료(OOM Kill, exit code 137)
# - 스왑은 RAM 보다 훨씬 느리므로 "죽지 않게 하는 보험"일 뿐, 근본 해결은 인스턴스 크기 늘리기
#
# swapon --show : 사용 중인 스왑 목록 출력 (없으면 아무것도 출력하지 않음)
# wc -l         : 출력 줄 수 세기 → 0 이면 스왑 없음
if [ "$(swapon --show | wc -l)" -eq 0 ]; then
  echo "== 스왑 2GB 생성"

  # 1) 2GB 크기의 빈 파일 만들기 (/dev/zero 에서 1MB 씩 2048번 = 2GB)
  sudo dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none

  # 2) root 만 읽고 쓸 수 있게 (메모리 내용이 디스크에 기록되므로 다른 사용자가 보면 안 됨)
  sudo chmod 600 /swapfile

  # 3) 이 파일을 스왑 영역으로 포맷
  sudo mkswap /swapfile >/dev/null

  # 4) 지금 바로 스왑 사용 시작
  sudo swapon /swapfile

  # 5) 재부팅 후에도 자동으로 스왑을 켜도록 /etc/fstab 에 한 줄 추가
  #    tee -a : 파일 끝에 추가 (sudo 권한으로 쓰기 위해 echo > 대신 tee 사용)
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
else
  echo "== 스왑 이미 있음"
fi

# ----------------------------------------------------------
# 4. docker 그룹에 현재 사용자 추가
# ----------------------------------------------------------
# - Docker 는 기본적으로 root 만 쓸 수 있어서 매번 sudo docker ... 를 입력해야 함
# - docker 그룹에 들어가면 sudo 없이 docker 명령 사용 가능
#   -a : 기존 그룹은 유지하고 (append)
#   -G : docker 그룹을 추가
# - 그룹 변경은 "새로 로그인할 때" 적용됨 → 스크립트가 끝나면 exit 후 다시 SSH 접속
# - 참고: docker 그룹은 사실상 root 와 같은 권한이므로 믿을 수 있는 사용자만 추가
sudo usermod -aG docker "${USER}"

# ----------------------------------------------------------
# 5. 결과 확인
# ----------------------------------------------------------
# 아직 docker 그룹이 적용되기 전이므로 sudo 로 확인
echo
sudo docker --version            # 예: Docker version 25.x
sudo docker compose version      # 예: Docker Compose version v2.x
free -h | head -3                # Mem(실제 메모리), Swap(2.0Gi 이면 정상)
echo
echo "완료. 로그아웃(exit) 후 다시 SSH 접속하면 sudo 없이 docker 명령을 쓸 수 있습니다."
echo "다음 단계: cp .env.example .env && chmod 600 .env && nano .env  (OPENAI_API_KEY, APP_PASSWORD 입력)"
