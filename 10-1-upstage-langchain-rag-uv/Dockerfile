# uv로 의존성을 관리하는 PDF 질의응답(RAG) Gradio 앱 이미지
# 사전 준비: uv sync (uv.lock 파일 생성)
# 빌드: docker build -t langchain-rag-app .
# 실행: docker run -d -p 7860:7860 --env-file .env langchain-rag-app

# 베이스 이미지 선택
# - Debian slim 기반 Python 3.12 (faiss-cpu 등 바이너리 패키지 호환성이 좋음)
FROM python:3.12-slim

# uv 설치
# - 공식 uv 이미지에서 실행 파일만 복사
# - 운영 환경에서는 :latest 대신 특정 버전 태그로 고정 권장
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# uv 동작 설정
# - UV_COMPILE_BYTECODE=1: 설치 시 .pyc로 미리 컴파일해 앱 시작 속도 향상
# - UV_LINK_MODE=copy: 컨테이너 환경에서 링크 경고 없이 파일 복사로 설치
# - UV_PYTHON_DOWNLOADS=0: 별도 Python을 내려받지 않고 이미지의 Python 3.12 사용
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=0

# 작업 디렉토리 설정
WORKDIR /app

# 의존성 파일 먼저 복사 (캐싱 최적화)
# - 세 파일이 그대로면 아래 설치 단계를 캐시로 건너뜀
COPY pyproject.toml uv.lock .python-version ./

# 의존성 설치
# - /app/.venv 가상 환경에 uv.lock에 적힌 버전 그대로 설치
# - --locked: uv.lock이 pyproject.toml과 맞지 않으면 빌드 실패 (버전 불일치 방지)
# - --no-dev: 개발용 패키지 제외
RUN uv sync --locked --no-dev

# 앱 소스 복사
COPY 04main_rag_faiss_gradio_upstage.py .

# 실행 환경 설정
# - PATH: python 명령이 .venv 안의 것으로 실행되도록 등록
# - PYTHONUNBUFFERED=1: print() 출력을 버퍼에 모으지 않고 바로 내보냄
#   (없으면 "PDF 파일 로딩 중..." 같은 로그가 docker logs에 늦게 나오거나 안 보임)
# - GRADIO_SERVER_NAME=0.0.0.0: 컨테이너 밖에서 접속 가능하도록 설정 (코드의 [변경 1])
# - GRADIO_SERVER_PORT=7860: 포트 고정 (코드의 [변경 2])
# - GRADIO_ANALYTICS_ENABLED=False: Gradio 사용 통계 전송 끄기
ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    GRADIO_SERVER_NAME=0.0.0.0 \
    GRADIO_SERVER_PORT=7860 \
    GRADIO_ANALYTICS_ENABLED=False

# 포트 열기 (문서화 용도)
EXPOSE 7860

# 건강 상태 검사
# - Gradio에는 별도 /health 경로가 없으므로 첫 화면(/)이 열리는지 확인
# - slim 이미지에는 wget, curl이 없으므로 Python 기본 모듈로 호출
# - --start-period=30s: Gradio와 LangChain 패키지를 불러오는 시간 동안 실패 무시
# - 화면만 확인하므로 헬스체크로 Upstage API 사용량은 발생하지 않음
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:7860/', timeout=3)"

# 앱 실행
# - Gradio는 demo.launch()로 서버를 띄우므로 uvicorn이 아닌 python으로 실행
# - UPSTAGE_API_KEY는 여기 없음, docker run의 --env-file로 전달
CMD ["python", "04main_rag_faiss_gradio_upstage.py"]
