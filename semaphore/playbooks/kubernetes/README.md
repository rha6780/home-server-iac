# Kubernetes Ansible Entry Point

이 디렉터리는 `scripts/kubernetes`의 shell-only 설치 흐름을 Ansible/Semaphore에서 실행하기 위한 진입점입니다.

## 준비

```bash
cp scripts/kubernetes/.env.example scripts/kubernetes/.env
vi scripts/kubernetes/.env
```

Semaphore inventory에는 `inventory.example.yml` 내용을 기준으로 노드 IP와 SSH 키를 맞춰 등록합니다.
이 playbook은 inventory 파일 위치를 기준으로 `scripts/kubernetes`를 찾습니다.

## 실행

```bash
ansible-playbook \
  -i semaphore/playbooks/kubernetes/inventory.example.yml \
  semaphore/playbooks/kubernetes/site.yml
```

특정 단계만 실행하려면 `k8s_deploy_steps`를 덮어씁니다.

```bash
ansible-playbook \
  -i semaphore/playbooks/kubernetes/inventory.example.yml \
  semaphore/playbooks/kubernetes/site.yml \
  -e k8s_deploy_steps=1,2
```

단계 번호는 `scripts/kubernetes/deploy.sh`와 동일합니다.

| 단계 | 내용 |
|---|---|
| `1` | HAProxy 설치 |
| `2` | Control Plane Primary 초기화 |
| `3` | 추가 Control Plane join |
| `4` | Worker join |
| `5` | Helm 컴포넌트 설치 |
