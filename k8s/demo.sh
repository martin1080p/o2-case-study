#!/usr/bin/env bash
# Demo of a rolling update and a node crash: opens 3 terminals - requests, pods, and a shell for the commands below.
#   ./demo.sh            prepare the cluster and open the terminals
#   ./demo.sh requests   (terminal 1) a request every 0.3 s
#   ./demo.sh pods       (terminal 2) backend and frontend pods, coloured by version (blue v1, green v2)
#   ./demo.sh upgrade    rolling update of the backend to v2
#   ./demo.sh downgrade  rolling update of the backend back to v1
#   ./demo.sh crash      node o2-m02 crashes (its Docker container is killed)
#   ./demo.sh recover    node o2-m02 comes back and re-joins the cluster
set -euo pipefail
cd "$(dirname "$0")"
P=o2
k() { minikube -p "$P" kubectl -- "$@"; }

case "${1:-}" in
  requests)
    URL="http://$(minikube -p "$P" ip):30080/"
    echo "GET $URL every 0.3 s"
    while true; do  # one line per request: which frontend and backend (pod, node, version) answered, or the error
      if r=$(curl -s -m 2 "$URL"); then echo "$r" | paste -sd ' ' | sed 's/: Hello from the backend//; s/  */ /g'; else echo FAILED; fi
      sleep 0.3
    done ;;
  pods)  # every change of a pod as one line, coloured by its image: blue hello:1, green hello:2
    printf '%-28s %-8s %-6s %-17s %s\n' POD IMAGE READY STATUS NODE
    declare -A last=()
    k get pods -w --no-headers -o custom-columns='N:.metadata.name,I:.spec.containers[0].image,R:.status.containerStatuses[0].ready,P:.status.phase,W:.status.containerStatuses[0].state.waiting.reason,D:.metadata.deletionTimestamp,NODE:.spec.nodeName' |
    while read -r name image ready phase waiting deleting node; do
      [[ $waiting != "<none>" ]] && phase=$waiting      # e.g. ContainerCreating
      [[ $deleting != "<none>" ]] && phase=Terminating
      [[ $ready == true ]] && ready=1/1 || ready=0/1
      line=$(printf '%-28s %-8s %-6s %-17s %s' "$name" "$image" "$ready" "$phase" "$node")
      [[ ${last[$name]:-} == "$line" ]] && continue      # nothing visible changed
      last[$name]=$line
      case $image in hello:1) c=34 ;; hello:2) c=32 ;; *) c=33 ;; esac
      printf '\033[1;%sm%s\033[0m\n' "$c" "$line"
    done ;;
  upgrade|downgrade)  # rolling update of the backend: new image -> pods replaced one by one
    v=$([[ $1 == upgrade ]] && echo 2 || echo 1)
    k set image deploy/backend backend=hello:$v
    k rollout status deploy/backend ;;
  crash)    # a hard crash, as if the machine lost power: no shutdown, the node just stops answering
    docker kill "$P-m02" >/dev/null && echo "node $P-m02 crashed" ;;
  recover)  # minikube restarts the node container and joins it to the cluster again
    docker stop "$P-m02" >/dev/null 2>&1 || true
    minikube -p "$P" node start m02
    # Kubernetes never moves running pods back by itself - a rolling restart spreads them over both nodes again
    k rollout restart deploy/backend deploy/frontend
    k rollout status deploy/backend >/dev/null && k rollout status deploy/frontend >/dev/null ;;
  "")
    minikube status -p "$P" >/dev/null 2>&1 || minikube start -p "$P" --nodes 2 --driver docker --cpus 2 --memory 2g
    kubectl config use-context "$P" >/dev/null  # a plain `kubectl` in terminal 3 talks to this cluster
    k -n kube-system rollout status deploy/coredns >/dev/null  # cluster DNS - the frontend finds the backend by name
    # images for the demo: v1 runs, v2 is the update
    for v in 1 2; do
      minikube -p "$P" image ls | grep "hello:$v" >/dev/null || { docker build -q -t "hello:$v" --build-arg VERSION=$v . && minikube -p "$P" image load "hello:$v"; }
    done
    k apply -f app.yaml >/dev/null
    k set image deploy/backend backend=hello:1 >/dev/null  # start from v1 (no-op if already there)
    k rollout status deploy/backend >/dev/null
    k rollout status deploy/frontend >/dev/null
    # after a restart the Deployments report the old "ready" state for a while - wait until the app really answers
    for _ in $(seq 180); do curl -s -m 2 "http://$(minikube -p "$P" ip):30080/" | grep -q Hello && break; sleep 1; done

    gnome-terminal --title "1 · requests" -- "$PWD/demo.sh" requests
    gnome-terminal --title "2 · pods" -- "$PWD/demo.sh" pods
    gnome-terminal --title "3 · commands" --working-directory "$PWD" ;;  # plain shell: ./demo.sh upgrade | downgrade | crash | recover
  *) echo "usage: $0 [requests|pods|upgrade|downgrade|crash|recover]" >&2; exit 1 ;;
esac
