# 3단계: Service (3티어 완성)

[← 2. Deployment](../02-deployment/README.md) · **3. Service** · [4. ConfigMap →](../04-configmap/README.md)

**Service**는 Pod 묶음 앞에 붙이는 **고정 주소**입니다. Pod는 다시 만들어질 때마다 IP가 바뀌지만, Service의 이름과 IP는 바뀌지 않습니다.
이 단계에서 frontend, backend, mariadb를 Service로 연결해 **메모 앱이 처음으로 동작**합니다.

```mermaid
flowchart LR
    U(["브라우저"]) -- "localhost:30080" --> FS{{"Service frontend<br/>NodePort"}}
    FS --> F["Pod frontend<br/>nginx"]
    F -- "http://backend:8080" --> BS{{"Service backend<br/>ClusterIP"}}
    BS --> B["Pod backend<br/>Spring Boot"]
    B -- "mariadb:3306" --> DS{{"Service mariadb<br/>ClusterIP"}}
    DS --> D["Pod mariadb"]
```

## Service가 Pod를 찾는 방법: 이름표(label)

```yaml
# Deployment 의 Pod 설계도                 # Service
template:                                  spec:
  metadata:                                  selector:
    labels:                                    app: backend    ← 이 이름표가 붙은 Pod 로 전달
      app: backend   ───────────────────▶
```

Service는 Pod 이름이나 IP를 모릅니다. **이름표가 맞는 Pod**를 계속 찾아서 요청을 보냅니다. Pod가 바뀌어도 이름표만 같으면 됩니다.

## Service 종류

| type | 접속할 수 있는 곳 | 이 실습에서 |
|---|---|---|
| `ClusterIP` (기본값) | 클러스터 **안**에서만 | `mariadb`, `backend` (외부에 공개하지 않음) |
| `NodePort` | 노드(내 PC)의 포트 30000~32767 | `frontend` (브라우저 접속, 30080) |
| `LoadBalancer` | 클라우드 로드 밸런서의 외부 IP | 클라우드 클러스터에서 사용 (다음 단계 학습) |

compose에서 DB와 앱 포트는 열지 않고 nginx 80만 열었던 것과 같은 구성입니다.

## 파일

| 파일 | 내용 |
|---|---|
| `10-mariadb-deployment.yaml` | 2단계와 같음 |
| `11-mariadb-service.yaml` | **추가**: `mariadb:3306` (ClusterIP) |
| `20-backend-deployment.yaml` | **추가**: Spring Boot, `DB_HOST=mariadb` |
| `21-backend-service.yaml` | **추가**: `backend:8080` (ClusterIP) |
| `30-frontend-deployment.yaml` | **추가**: nginx, `BACKEND_URL=http://backend:8080` |
| `31-frontend-service.yaml` | **추가**: NodePort 30080 |

> 이미지 이름의 `hubusername`을 내 아이디로 바꿨는지 확인하세요 ([준비 2](../README.md#2-이미지-이름-바꾸기-한-번만)).

## 실행

```bash
kubectl apply -f 03-service/

kubectl get pods -n memo -w
#   mariadb-...    1/1   Running             0
#   backend-...    0/1   Error               0     ← DB 준비 전이라 실패 (정상)
#   backend-...    1/1   Running             1     ← 자동 재시작 후 성공
#   frontend-...   1/1   Running             0
```

> **backend가 처음에 1~2번 재시작하는 것은 정상입니다.** compose의 `depends_on`처럼 시작 순서를 기다려 주는 기능이 기본으로는 없어서, MariaDB가 준비되기 전에 시작하면 접속에 실패하고 종료됩니다. Kubernetes가 자동으로 다시 시작하므로 결국 연결됩니다. [7단계](../07-complete/README.md)에서 정리합니다.

```bash
kubectl get svc -n memo
#   NAME       TYPE        CLUSTER-IP      PORT(S)
#   backend    ClusterIP   10.96.120.15    8080/TCP
#   frontend   NodePort    10.96.33.201    80:30080/TCP
#   mariadb    ClusterIP   10.96.200.7     3306/TCP

kubectl logs -n memo deploy/backend | grep -i "migrat"
#   Successfully applied 3 migrations to schema `boot_db`, now at version v3
```
minikube가 docker driver를 사용 중이므로 minikube service 서비스이름 명령어를 이용하여 접속해야 합니다
```bash
minikube service frontend -n memo --url
```

결과로 받은 url로 브라우저에서 접속해야 합니다. 메모 화면과 `앱 UP` `DB UP` 배지가 보이면 3티어가 모두 연결된 것입니다.
Docker Desktop이 아니라면 [접속 방법](../README.md#앱-접속-방법)을 참고하세요.

## 살펴보기

**1. Service 이름으로 접속되는지 (클러스터 안에서)**
```bash
kubectl exec -n memo deploy/frontend -- wget -qO- http://backend:8080/api/memos
kubectl exec -n memo deploy/frontend -- nslookup backend      # Service 의 고정 IP (CLUSTER-IP)
```

**2. Service 뒤의 실제 Pod 목록 (Endpoints)**
```bash
kubectl get endpoints -n memo
#   backend    10.1.0.23:8080
#   mariadb    10.1.0.21:3306
```
> 최근 버전에서는 `Endpoints is deprecated` 경고가 함께 나올 수 있습니다. 동작에는 문제가 없고, 새 방식은 `kubectl get endpointslices -n memo`입니다.

**3. Pod가 바뀌어도 주소는 그대로**
```bash
kubectl delete pod -n memo -l app=backend
kubectl get endpoints backend -n memo      # Pod IP 는 바뀌었지만
kubectl get svc backend -n memo            # Service IP 와 이름은 그대로 → 화면도 계속 동작
```

## 실습: 백엔드 2개로 늘리기 (로드 밸런싱)

```bash
kubectl scale deploy/backend --replicas=2 -n memo
kubectl get pods -n memo -l app=backend -o wide     # Pod 2개
kubectl get endpoints backend -n memo               # IP 2개
```

화면에서 메모를 여러 번 새로고침한 뒤 두 Pod의 로그를 보면 요청이 나눠져 들어온 것을 볼 수 있습니다.

```bash
kubectl logs -n memo -l app=backend --tail=5 --prefix    # --prefix: 어느 Pod 의 로그인지 표시
```

## 남은 문제

YAML을 열어 보면 같은 값이 여러 곳에 있습니다.

| 값 | 적힌 곳 |
|---|---|
| `boot_db`, `boot` | mariadb Deployment, backend Deployment |
| `boot-pass-1234` | mariadb Deployment, backend Deployment (**비밀번호가 그대로 보임**) |

하나만 고치면 서로 달라져서 접속이 실패합니다. → [4. ConfigMap](../04-configmap/README.md), [5. Secret](../05-secret/README.md)

## 정리

```bash
kubectl delete namespace memo
```

---

[← 2. Deployment](../02-deployment/README.md) · [전체 안내](../README.md) · [4. ConfigMap →](../04-configmap/README.md)
