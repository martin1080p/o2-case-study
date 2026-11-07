#!/usr/bin/env bash
# Rolling update demo: opens 3 terminals - requests, backend pods, and a shell for the update command.
#   ./demo.sh            prepare the cluster and open the terminals
#   ./demo.sh requests   (terminal 1) a request every 0.3 s
#   ./demo.sh pods       (terminal 2) backend pods, one colour per version (ReplicaSet)
set -euo pipefail
cd "$(dirname "$0")"
P=o2
k() { minikube -p "$P" kubectl -- "$@"; }

case "${1:-}" in
  requests)
    URL="http://$(minikube -p "$P" ip):30080/"
    echo "GET $URL every 0.3 s"
    while true; do curl -s -m 2 "$URL" | sed -n 2p || echo FAILED; sleep 0.3; done ;;
  pods)
    # pod name = backend-<ReplicaSet hash>-<id>; the hash changes with every version -> colour by it,
    # in order of appearance (blue = the version running at the start, green = the new one, ...)
    colors=(34 32 33 35)  # blue, green, yellow, magenta
    declare -A col=()
    k get pods -l app=backend -o wide -w | while IFS= read -r line; do
      [[ $line == NAME* ]] && { echo "$line"; continue; }
      h=${line#backend-}; h=${h%%-*}
      [[ -v col[$h] ]] || col[$h]=${colors[${#col[@]} % 4]}
      printf '\033[1;%sm%s\033[0m\n' "${col[$h]}" "$line"
    done ;;
  "")
    minikube status -p "$P" >/dev/null 2>&1 || minikube start -p "$P" --nodes 2 --driver docker --cpus 2 --memory 2g
    minikube profile "$P" >/dev/null  # so a plain `kubectl` (alias of `minikube kubectl --`) talks to this cluster
    k -n kube-system rollout status deploy/coredns >/dev/null  # cluster DNS - the frontend finds the backend by name
    # images for the demo: v1 runs, v2 is the update
    for v in 1 2; do
      minikube -p "$P" image ls | grep "hello:$v" >/dev/null || { docker build -q -t "hello:$v" --build-arg VERSION=$v . && minikube -p "$P" image load "hello:$v"; }
    done
    k apply -f app.yaml >/dev/null
    k set image deploy/backend backend=hello:1 >/dev/null  # start from v1 (no-op if already there)
    k rollout status deploy/backend >/dev/null
    k rollout status deploy/frontend >/dev/null

    gnome-terminal --title "1 · requests" -- "$PWD/demo.sh" requests
    gnome-terminal --title "2 · backend pods" -- "$PWD/demo.sh" pods
    gnome-terminal --title "3 · rolling update" --working-directory "$PWD" ;;  # plain shell: type the update here
  *) echo "usage: $0 [requests|pods]" >&2; exit 1 ;;
esac
