# 10-langchain-rag-uv

PDF를 업로드하면 문서 내용을 근거로 답변하는 **RAG(검색 증강 생성) Gradio 앱**을 uv로 관리해 컨테이너로 만드는 예제입니다.
FAISS 벡터 저장소와 **OpenAI 모델**(채팅 `gpt-6-luna`, 임베딩 `text-embedding-3-small`)을 사용하며, 09 단계처럼 **API 키는 이미지에 넣지 않고 실행 시점에 `.env`로 전달**합니다.

## 이 예제의 목적

| 주제 | 내용 |
|---|---|
| 웹 UI 앱 컨테이너화 | API 서버(FastAPI)가 아닌 Gradio UI 앱을 컨테이너로 실행 |
| 코드 수정이 필요한 경우 | 접속 주소와 포트가 코드에 고정된 앱을 배포용으로 바꾸는 방법 |
| 환경 변수로 설정 분리 | 같은 코드를 로컬(127.0.0.1)과 Docker(0.0.0.0)에서 다르게 동작시키기 |
| 컨테이너 로그 | `PYTHONUNBUFFERED`로 처리 과정 로그를 `docker logs`에 바로 표시 |

### 이전 단계(09-langchain-uv)와 달라진 점

| 항목 | 09-langchain-uv | 10-langchain-rag-uv |
|---|---|---|
| 앱 형태 | FastAPI (REST API) | Gradio (웹 UI) |
| 실행 방식 | `uvicorn` 명령 | `python 파일.py` (`demo.launch()`) |
| 코드 수정 | 필요 없음 (실행 명령으로 주소 지정) | **필요함** (주소, 포트가 `launch()` 안에 고정) |
| LLM | Groq (`ChatOpenAI` + base_url) | OpenAI `gpt-6-luna` (`ChatOpenAI`) |
| 추가 기능 | 없음 | PDF 로드, 청크 분할, 임베딩, FAISS 검색 |
| API 키 | `GROQ_API_KEY` | `OPENAI_API_KEY` |
| 포트 | 8000 (내 PC 8001) | 7860 (내 PC 7860) |
| 헬스체크 대상 | `/health` | `/` (Gradio에는 `/health`가 없음) |

## 파일 구성

```
10-langchain-rag-uv/
├── Dockerfile                          # 이미지 빌드 설정
├── .dockerignore                       # 이미지에서 제외할 파일 (.env, .venv, *.pdf 등)
├── .env                                # 실제 API 키 (Git, 이미지에 포함 금지)
├── .env.example                        # 키 형식 안내용 (공유 가능)
├── .python-version                     # 사용할 Python 버전 (3.12)
├── pyproject.toml                      # 프로젝트 정보와 의존성 정의
├── uv.lock                             # uv sync로 생성, 정확한 버전 고정
├── 04main_rag_faiss_gradio_openai.py   # RAG Gradio 앱 (배포용 수정 + OpenAI 모델)
├── 실행방법.txt                        # 빌드, 실행, 테스트 명령 모음
└── README.md
```

## pyproject.toml

코드에서 직접 import하는 패키지와, LangChain 클래스가 내부에서 필요로 하는 패키지만 포함했습니다.

| 코드의 import | 패키지 | 용도 |
|---|---|---|
| `import gradio as gr` | `gradio` | 웹 UI (**6.9 미만**으로 제한, gradio-pdf 호환) |
| `from langchain_community.retrievers import BM25Retriever` | `langchain-community` + **`rank-bm25`** | 키워드 검색 (변경 5) |
| `from langchain_classic.retrievers import EnsembleRetriever` | `langchain-classic` | 키워드 + 벡터 검색 결과 합치기 (변경 5) |
| `from gradio_pdf import PDF` | `gradio-pdf` | PDF 업로드, 미리보기 컴포넌트 |
| `from dotenv import load_dotenv` | `python-dotenv` | 로컬 실행 시 `.env` 로드 |
| `from langchain_openai import ...` | `langchain-openai` | OpenAI 임베딩, 채팅 모델 (`openai`, `tiktoken`도 함께 설치됨) |
| `from langchain_core...` | `langchain-core` | 프롬프트, 파서, Runnable |
| `from langchain_text_splitters import ...` | `langchain-text-splitters` | 청크 분할 |
| `from langchain_community.document_loaders import PyPDFLoader` | `langchain-community` + **`pypdf`** | PyPDFLoader가 내부에서 pypdf 사용 |
| `from langchain_community.vectorstores import FAISS` | `langchain-community` + **`faiss-cpu`** | FAISS 클래스가 내부에서 faiss 사용 |
| `os`, `re`, `dataclasses`, `functools` | (기본 모듈) | 설치 불필요 |

> `pypdf`와 `faiss-cpu`는 코드에 import문이 없지만, 빠지면 PDF 업로드나 벡터 저장소 생성 시점에 `ImportError`가 납니다.
> 강의 전체용 `pyproject.toml`과 달리 `sentence-transformers`, `transformers`가 없어서 PyTorch가 설치되지 않으므로 이미지가 훨씬 작습니다.

## RAG 동작 흐름

```
PDF 업로드 + 질문
   │
   ├─ (PDF 또는 청크 설정이 바뀐 경우에만)
   │     PyPDFLoader → 페이지별 Document
   │        → RecursiveCharacterTextSplitter → 청크
   │        → OpenAIEmbeddings(text-embedding-3-small) → FAISS 벡터 저장소 (메모리)
   │        → BM25 키워드 검색기 (두 글자 단위, 메모리)
   │
   ├─ retriever: 하이브리드 검색 (변경 5)
   │     · BM25: 질문의 단어가 많이 들어 있는 청크 6개
   │     · FAISS: 질문과 의미가 비슷한 청크 6개
   │     · 두 결과를 순위 기반으로 합침 (중복 제외, 최대 12개)
   ├─ 프롬프트: 검색된 청크를 {context}로 넣음
   ├─ ChatOpenAI(gpt-6-luna): 답변 생성
   └─ 답변 + 출처(파일명, 페이지) 표시
```

- 벡터 저장소는 접속자(브라우저 세션)별로 `gr.State`에 보관되어, 다른 사용자의 PDF가 섞이지 않습니다.
- 같은 PDF와 같은 청크 설정이면 저장소를 재사용해 임베딩 비용을 아낍니다.
- FAISS는 **메모리에만** 저장되므로, 컨테이너를 재시작하면 사라집니다. PDF를 다시 올리면 새로 만들어집니다.

## 배포를 위한 코드 변경 사항

이전 코드(`03ChatBot/04main_rag_faiss_gradio_upstage.py`)와 비교해 배포용으로 **두 군데**(변경 1, 2), 모델 교체로 **두 군데**(변경 3, 4)가 바뀌었고, RAG 로직, 프롬프트, UI는 그대로입니다.
코드 안에서도 `[변경 1]`~`[변경 5]` 주석으로 표시해 두었습니다. 모델 교체는 [모델 변경](#모델-변경-upstage-solar--openai), 검색 개선은 [하이브리드 검색](#검색-개선-하이브리드-검색-키워드--벡터)에 정리했습니다.

### 변경 1. 접속 주소를 환경 변수로

```python
# 이전
SERVER_NAME = "127.0.0.1"

# 변경
SERVER_NAME = os.getenv("GRADIO_SERVER_NAME", "127.0.0.1")
```

| 주소 | 의미 | 컨테이너에서 |
|---|---|---|
| `127.0.0.1` | 자기 자신에서 온 요청만 받음 | 컨테이너 밖(내 PC 브라우저)에서 접속 불가 |
| `0.0.0.0` | 모든 네트워크에서 온 요청을 받음 | `-p`로 연결한 포트로 접속 가능 |

09 단계는 `uvicorn --host 0.0.0.0` 명령으로 주소를 바꿀 수 있었지만, Gradio는 코드의 `demo.launch(server_name=...)`가 주소를 정하므로 코드를 고쳐야 합니다.
`launch()`에 값을 직접 넘기면 Gradio가 자체적으로 읽는 환경 변수가 무시되므로, `os.getenv`로 읽어서 넘기는 방식을 썼습니다.

### 변경 2. 포트 고정

```python
# 이전: 포트 미지정 (Gradio가 7860부터 빈 포트를 자동으로 찾음)

# 변경
SERVER_PORT = int(os.getenv("GRADIO_SERVER_PORT", "7860"))
demo.launch(share=False, server_name=SERVER_NAME, server_port=SERVER_PORT)
```

Docker는 `docker run -p 7860:7860`처럼 연결할 포트를 미리 알아야 합니다.
포트가 자동으로 정해지면 7861 같은 다른 번호가 잡혔을 때 접속이 안 되므로 고정했습니다.

### 로컬과 Docker에서의 동작

| 실행 환경 | `GRADIO_SERVER_NAME` | 실제 주소 | 접속 주소 |
|---|---|---|---|
| 로컬 (`uv run python ...`) | 없음 | `127.0.0.1:7860` | http://127.0.0.1:7860 |
| Docker | `0.0.0.0` (Dockerfile에서 지정) | `0.0.0.0:7860` | http://localhost:7860 |

환경 변수가 없으면 기본값을 쓰기 때문에, **로컬에서는 이전 코드와 똑같이 안전하게** 동작합니다.

## 모델 변경 (Upstage Solar → OpenAI)

| 항목 | 이전 (Upstage) | 변경 (OpenAI) |
|---|---|---|
| 패키지 | `langchain-upstage` | `langchain-openai` |
| 임베딩 | `UpstageEmbeddings("solar-embedding-1-large")` | `OpenAIEmbeddings("text-embedding-3-small")` |
| 채팅 | `ChatUpstage("solar-pro3", base_url=...)` | `ChatOpenAI("gpt-6-luna", reasoning_effort="none")` |
| API 키 | `UPSTAGE_API_KEY` | `OPENAI_API_KEY` |
| 파일 이름 | `04main_rag_faiss_gradio_upstage.py` | `04main_rag_faiss_gradio_openai.py` |

### 변경 3. 패키지와 클래스

```python
# 이전
from langchain_upstage import UpstageEmbeddings, ChatUpstage
UpstageEmbeddings(model="solar-embedding-1-large")
ChatUpstage(model="solar-pro3", base_url="https://api.upstage.ai/v1", temperature=temperature)

# 변경
from langchain_openai import OpenAIEmbeddings, ChatOpenAI
OpenAIEmbeddings(model="text-embedding-3-small")
ChatOpenAI(model="gpt-6-luna", temperature=temperature, reasoning_effort="none")
```

- `OpenAIEmbeddings`, `ChatOpenAI`는 환경 변수 `OPENAI_API_KEY`를 자동으로 읽습니다. 코드에 키를 넘길 필요가 없습니다.
- OpenAI 기본 주소를 쓰므로 `base_url`은 지정하지 않습니다.

### 변경 4. `reasoning_effort="none"`

`gpt-6-luna`는 **추론(reasoning) 모델**입니다. GPT-6 계열은 추론 강도(`reasoning_effort`)가 `none`일 때만 `temperature`를 받습니다.
이 앱은 "창의성 수준" 슬라이더 값을 `temperature`로 넘기므로 `none`으로 고정했습니다. RAG는 찾은 문서를 정리하는 작업이라 별도 추론 단계 없이도 충분하고, 응답도 빠릅니다.

### 모델 선택 이유

| 모델 | 이유 |
|---|---|
| `gpt-6-luna` | GPT-6 계열 중 가장 빠르고 저렴함 (입력 $0.10, 출력 $0.50 / 100만 토큰). `reasoning_effort="none"`을 지원해 temperature 슬라이더를 그대로 쓸 수 있음 |
| `text-embedding-3-small` | OpenAI의 현재 임베딩 모델 중 저렴한 쪽 (약 $0.02 / 100만 토큰, 1536차원) |

### 비용 (대략)

| 작업 | 토큰 (가정) | 비용 |
|---|---|---|
| PDF 임베딩 (30페이지, 청크 약 100개) | 약 10만 토큰 이하 (한국어는 영어보다 토큰이 많음) | 약 $0.002 이하 |
| 질문 1번 (검색 청크 최대 12개 + 답변) | 입력 약 1만 2천, 출력 약 500 | 약 $0.0015 |

정확한 최신 가격은 [OpenAI 가격 페이지](https://developers.openai.com/api/docs/pricing)에서 확인하세요. 실습 중 예상치 못한 요금을 막으려면 OpenAI 플랫폼의 Billing에서 **월 사용 한도**를 정해 두세요.

### 다른 OpenAI 모델로 바꾸려면

코드 위쪽의 상수만 바꾸면 됩니다.

```python
CHAT_MODEL = "gpt-6-luna"                 # 답변 모델
EMBEDDING_MODEL = "text-embedding-3-small" # 임베딩 모델
```

| 바꿀 모델 | 그대로 동작? | 참고 |
|---|---|---|
| `gpt-6.1-terra` | ○ | 답변 품질이 더 좋고 비용은 약 10배 (질문 1번 약 $0.015) |
| `gpt-6.1-sol`, `gpt-6-astra` | ✕ | `reasoning_effort="none"`을 지원하지 않아 temperature를 보낼 수 없음. `temperature` 인자와 UI 슬라이더를 빼고 `reasoning_effort="low"` 등으로 바꿔야 함 |
| `text-embedding-3-large` | ○ | 한국어 등 다국어 검색 성능이 더 좋고 비용은 약 6배 |

> 임베딩 모델을 바꾸면 벡터의 차원과 의미가 달라져 이전 벡터와 섞어 쓸 수 없습니다. 이 앱은 FAISS를 메모리에만 두므로, 앱을 다시 시작하고 PDF를 다시 올리면 됩니다.

## 검색 개선: 하이브리드 검색 (키워드 + 벡터)

### 문제

84쪽 분량의 `소득세법` PDF에 "비과세 소득에는 어떤 소득이 포함되나요?"라고 물으면, 정답(7쪽 **제12조 비과세소득**)이 있는데도 "제공된 문서에서 해당 정보를 찾을 수 없습니다"라고 답했습니다. 출처에도 7쪽이 없었습니다.

**답변 모델의 문제가 아니라 검색 단계에서 정답 청크를 가져오지 못한 것**입니다. 모델을 `gpt-6.1-terra`로 바꿔도 같았던 이유입니다. 모델은 받은 문맥 안에서만 답하도록 프롬프트가 되어 있으니, 문맥에 정답이 없으면 "찾을 수 없다"가 올바른 답입니다.

| 원인 | 설명 |
|---|---|
| 비슷한 문장이 많음 | 법령 문서는 "소득", "과세", "대통령령으로 정하는" 같은 표현이 모든 쪽에 나와 의미 검색만으로는 정답이 상위 6개에서 밀림 |
| 정답 청크의 잡음 | 제12조 첫 청크의 상당 부분이 `<개정 2010. 12. 27., 2011. 7. 25., ...>` 같은 날짜 목록이라 임베딩의 의미가 흐려짐 |
| 띄어쓰기 | 질문은 "비과세 소득", 문서는 "비과세소득" |

### 해결 (변경 5)

```python
# 의미가 비슷한 청크 (기존)
vector_retriever = vectorstore.as_retriever(search_kwargs={"k": SEARCH_K})

# 단어가 일치하는 청크 (추가): 한국어는 두 글자 단위로 비교
keyword_retriever = BM25Retriever.from_documents(splits, preprocess_func=korean_bigrams, k=SEARCH_K)

# 두 결과를 순위 기반으로 합침
EnsembleRetriever(retrievers=[keyword_retriever, vector_retriever], weights=[0.5, 0.5])
```

| 검색 방식 | 잘 찾는 것 | 약한 것 |
|---|---|---|
| 벡터 (FAISS + 임베딩) | 표현은 달라도 뜻이 같은 문장 | 법령 용어, 조문 이름처럼 **정확한 단어**가 중요한 질문 |
| 키워드 (BM25) | 질문의 단어가 그대로 들어 있는 문장 | 다른 단어로 바꿔 말한 질문 |
| **하이브리드** | 둘 다 | - |

**두 글자 단위로 자르는 이유:** BM25는 기본으로 공백을 기준으로 단어를 나눕니다. 한국어는 조사가 붙고(`소득에는`) 띄어쓰기가 제각각이라 `비과세 소득`과 `비과세소득`이 다른 단어가 됩니다. 두 글자씩 자르면 둘 다 `비과`, `과세`, `세소`, `소득`을 가지게 되어 서로 맞습니다.

같은 PDF에서 키워드 검색만 따로 확인한 결과입니다.

| 질문 | 공백 기준 BM25 | 두 글자 단위 BM25 |
|---|---|---|
| 비과세 소득에는 어떤 소득이 포함되나요? | 6, 14, 83, 70, 68, 59쪽 (정답 없음) | 52, 60, **7**, **10**, **28**, **82**쪽 (모두 "비과세소득" 포함) |
| 거주자와 비거주자의 정의는? | 5, 5, 4, 4, 57, 39쪽 | 39, **1**, **2**, 39, 5, 5쪽 (제1조의2 정의 포함) |

추가로 PDF에서 추출한 텍스트의 연속 공백(`개인의  소득에`)을 한 칸으로 정리합니다.

| 항목 | 이전 | 변경 |
|---|---|---|
| 모델에 넘기는 청크 | 6개 | 최대 12개 (두 검색 결과 합침, 중복 제외) |
| 질문 비용 | 약 $0.001 | 약 $0.0015 (입력 토큰 증가, BM25 자체는 비용 없음) |
| 추가 패키지 | - | `langchain-classic`(EnsembleRetriever), `rank-bm25` |

### 그래도 못 찾으면

| 방법 | 설정 |
|---|---|
| 청크를 크게 (조문 하나가 한 청크에 들어가도록) | 고급 설정의 청크 크기 1500~2000 |
| 검색 개수 늘리기 | `SEARCH_K = 8` (비용이 조금 늘어남) |
| 키워드 비중 높이기 (용어 중심 문서) | `HYBRID_WEIGHTS = [0.6, 0.4]` |
| 다국어 성능이 더 좋은 임베딩 | `EMBEDDING_MODEL = "text-embedding-3-large"` |
| 질문에 문서 용어 그대로 쓰기 | "비과세 소득" 대신 "비과세소득", "제12조" |

## 비밀 값(API 키) 다루기

09 단계와 같은 방식입니다.

```
.env (내 PC에만 존재)
  │
  ├─ docker build ──✕── .dockerignore로 제외 → 이미지에 키 없음
  │
  └─ docker run --env-file .env ──→ 컨테이너 환경 변수 OPENAI_API_KEY
                                          │
                                          ├─ require_api_key(): 시작 시 키 확인
                                          └─ OpenAIEmbeddings, ChatOpenAI가 자동으로 읽음
```

- 코드의 `load_dotenv()`는 로컬에서는 `.env`를 읽고, 컨테이너에서는 파일이 없어 아무 일도 하지 않습니다.
- 키가 없으면 UI를 띄우기 전에 `ValueError`로 종료되므로, 컨테이너는 `Exited (1)`이 되고 `docker logs`에 원인이 나옵니다.
- `.env`는 `.dockerignore`와 `.gitignore` 양쪽에 넣고, 값에는 따옴표나 공백을 넣지 않습니다.

## Dockerfile 핵심 부분

uv 설치, 의존성 캐시 구조는 09 단계와 같습니다. 이 단계에서 추가된 부분만 정리합니다.

### 실행 환경 변수

```dockerfile
ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    GRADIO_SERVER_NAME=0.0.0.0 \
    GRADIO_SERVER_PORT=7860 \
    GRADIO_ANALYTICS_ENABLED=False
```

| 설정 | 의미 |
|---|---|
| `PYTHONUNBUFFERED=1` | `print()` 출력을 바로 내보냄. 없으면 처리 과정 로그가 `docker logs`에 늦게 나오거나 안 보임 |
| `GRADIO_SERVER_NAME=0.0.0.0` | 코드의 [변경 1]이 읽는 값, 외부 접속 허용 |
| `GRADIO_SERVER_PORT=7860` | 코드의 [변경 2]가 읽는 값, 포트 고정 |
| `GRADIO_ANALYTICS_ENABLED=False` | Gradio 사용 통계 전송 끄기 |

### HEALTHCHECK

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:7860/', timeout=3)"
```

- Gradio에는 별도 `/health` 경로가 없으므로 첫 화면(`/`)이 열리는지 확인합니다.
- 화면만 불러오므로 헬스체크로 OpenAI API 사용량은 발생하지 않습니다.
- Gradio와 LangChain 패키지를 불러오는 데 시간이 걸려 `--start-period=30s`를 두었습니다.

### 실행 명령

```dockerfile
CMD ["python", "04main_rag_faiss_gradio_openai.py"]
```

Gradio는 `demo.launch()`가 직접 웹 서버를 띄우므로, 09 단계와 달리 uvicorn이 아닌 python으로 실행합니다.

## 실행 방법

### 0. 사전 준비 (처음 한 번)

1. [OpenAI 플랫폼](https://platform.openai.com/api-keys)에서 API 키 발급 (결제 수단 등록 또는 크레딧 충전 필요)
2. `.env.example`을 `.env`로 복사하고 `OPENAI_API_KEY` 입력
3. 10 폴더에서 `uv sync` 실행

```bash
uv sync
```

| 생성되는 것 | 역할 | Docker에서 |
|---|---|---|
| `uv.lock` | 설치된 정확한 버전 기록 | **필요함** (`uv sync --locked`에 사용) |
| `.venv/` | 내 PC용 가상 환경 | 필요 없음 (`.dockerignore`로 제외) |

### 1. 로컬에서 먼저 확인 (선택)

```bash
uv run python 04main_rag_faiss_gradio_openai.py
```

- 접속 주소: http://127.0.0.1:7860
- Docker와 같은 7860 포트를 쓰므로, 확인 후 **Ctrl + C로 종료**하고 다음 단계로 넘어갑니다.

### 2. 이미지 빌드

```bash
docker build -t langchain-rag-app .
```

### 3. 컨테이너 실행

```bash
# (재실행 시) 기존 컨테이너 정리
docker rm -f my-rag

docker run -d -p 7860:7860 --env-file .env --name my-rag langchain-rag-app
```

### 4. 상태 확인

```bash
docker ps            # STATUS가 (health: starting) → (healthy)로 바뀌는지 확인
docker logs my-rag   # "Gradio 서버 시작: http://0.0.0.0:7860" 확인
```

## 테스트

> 질문할 때마다 OpenAI API 사용량이 발생하고, 새 PDF를 올리면 임베딩 비용이 추가로 발생합니다. 대략적인 금액은 [비용](#비용-대략)을 참고하세요.

1. 브라우저에서 http://localhost:7860 접속
2. 왼쪽에 PDF 업로드
3. 질문 입력 또는 예시 질문 버튼 클릭 후 질문하기
4. 답변 아래에 `[1] 파일명 (Page N)` 형태의 출처가 붙는지 확인

처리 과정은 로그로 실시간 확인할 수 있습니다.

```bash
# -f: 새 로그를 계속 출력 (Ctrl + C로 종료해도 컨테이너는 계속 실행됨)
docker logs -f my-rag
```

```
Gradio 서버 시작: http://0.0.0.0:7860
새로운 PDF/설정 처리 중...
PDF 파일 로딩 중: /tmp/gradio/.../sample.pdf
총 12페이지 로드됨
총 38개 청크로 분할됨
FAISS 벡터 저장소 생성 중...
벡터 저장소 생성 완료!
하이브리드 검색기(키워드 + 벡터) 준비 완료
기존 벡터 저장소 사용
```

두 번째 질문부터 `기존 벡터 저장소 사용`이 나오면 임베딩을 재사용하고 있다는 뜻입니다.

## 문제 해결

| 증상 | 원인 | 해결 |
|---|---|---|
| 실행 직후 `Exited (1)` | `OPENAI_API_KEY`가 전달되지 않음 | `docker logs`에서 ValueError 확인, `--env-file .env` 추가 |
| `.env`를 바꿨는데 `OPENAI_API_KEY가 설정되지 않았습니다` | 이전 `.env`에 `UPSTAGE_API_KEY`만 있음 | `.env.example`을 보고 `OPENAI_API_KEY=sk-...`로 교체 |
| 채팅창에 `Error code: 401` | 키가 틀렸거나 삭제됨 | OpenAI 플랫폼에서 키 확인, `.env` 수정 후 컨테이너 다시 실행 |
| 채팅창에 `Error code: 429` (`insufficient_quota`) | 결제 수단 미등록, 크레딧 소진 | OpenAI 플랫폼 Billing에서 결제 수단, 사용 한도 확인 |
| 채팅창에 `Error code: 404` (`model_not_found`) | 계정에서 쓸 수 없는 모델, 또는 모델 이름 오타 | 코드의 `CHAT_MODEL`, `EMBEDDING_MODEL` 확인 |
| 채팅창에 `Unsupported parameter: 'temperature'` | `reasoning_effort="none"`을 지원하지 않는 모델(`gpt-6-astra`, `gpt-6.1-sol`)로 바꿈 | [모델 바꾸기](#다른-openai-모델로-바꾸려면) 참고 |
| 첫 PDF 업로드 때 `openaipublic.blob.core.windows.net` 연결 오류 | 임베딩 전에 토큰 수를 세는 `tiktoken`이 처음 한 번 인코딩 파일을 내려받는데, 회사 방화벽 등이 막음 | 해당 주소를 허용하거나 다른 네트워크에서 실행 |
| 컨테이너는 Up인데 브라우저 접속 안 됨 | 이전 코드(127.0.0.1 고정)로 빌드됨 | 수정된 코드인지 확인 후 다시 빌드 |
| 로그에 처리 과정이 안 보임 | `PYTHONUNBUFFERED` 누락 | Dockerfile의 ENV 확인 |
| 로컬 실행 시 포트 충돌 | Docker 컨테이너가 7860 사용 중 | `docker stop my-rag` 후 실행 |
| `uv sync` 시 `Failed to download and build tokenizers==0.20.3` | uv가 Python 3.14를 선택함 (tokenizers 0.20.x는 3.13까지만 지원) | `pyproject.toml`의 `requires-python = ">=3.12,<3.14"` 확인, `.python-version` 파일 이름 확인 후 `.venv` 삭제하고 `uv sync` |
| PDF 업로드 창이 안 보이고 대화창이 "로딩 중"에서 멈춤 | Gradio 6.9.0 이상 설치됨. gradio-pdf가 쓰는 Svelte 런타임 파일(`assets/svelte/*.js`)이 6.9.0부터 빠짐 | `pyproject.toml`의 `"gradio>=6.3.0,<6.9"` 확인 후 `uv sync`, 브라우저 강력 새로고침(Ctrl + F5) |
| 빌드 시 lock 파일 오류 | `pyproject.toml` 수정 후 `uv.lock` 미갱신 | `uv sync` 다시 실행 후 빌드 |
| PDF 업로드 후 `No module named 'pypdf'` | `pypdf` 누락 | `pyproject.toml`에 `pypdf` 확인 후 `uv sync` |
| 저장소 생성 시 `faiss` 관련 ImportError | `faiss-cpu` 누락 | `pyproject.toml`에 `faiss-cpu` 확인 후 `uv sync` |
| "텍스트를 추출할 수 없습니다" | 스캔 이미지로 된 PDF | 텍스트가 선택되는 PDF로 테스트 |
| 문서에 있는 내용인데 "찾을 수 없습니다", 출처에 정답 쪽이 없음 | 검색 단계에서 정답 청크를 가져오지 못함 (모델 문제 아님) | [하이브리드 검색](#검색-개선-하이브리드-검색-키워드--벡터)의 "그래도 못 찾으면" 참고 |
| 재시작 후 이전 PDF 답변이 안 됨 | FAISS가 메모리에만 저장됨 | 정상, PDF를 다시 업로드 |

키가 컨테이너에 전달되었는지는 값을 출력하지 않고 확인할 수 있습니다.

```bash
docker exec my-rag python -c "import os; print('set' if os.getenv('OPENAI_API_KEY') else 'missing')"
```

## 보안 참고

- 컨테이너는 `0.0.0.0`으로 열리므로, 같은 네트워크의 다른 사람이 내 PC의 7860 포트로 접속하면 **내 API 키로 질문할 수 있습니다.** 외부에 공개할 일이 있다면 `demo.launch(auth=...)` 같은 인증을 먼저 추가하세요.
- `share=False`를 유지해 gradio.live 공개 링크가 만들어지지 않도록 했습니다.
- 운영 환경에서는 `ghcr.io/astral-sh/uv:latest` 대신 특정 버전 태그로 고정하는 것을 권장합니다.
