#!/bin/bash

args=""
with_metrics=no
while (( "$#" )); do 
  case $1 in
  --with-metrics) with_metrics=yes
  shift;;
  esac
  args+="$1 "
  shift
done

shift $(($OPTIND-1))

echo "args=$args"

root_dir=$(dirname $(cd $(dirname $BASH_SOURCE) && pwd))

setup() {
  cluster=${1:-kube-labs}
  version=${2:-'1.6.15'}

  echo "creating kind cluster, name=$cluster, version=$version, with_metrics=$with_metrics..."

  # create self-signed certificates
  mkdir -p $root_dir/certs
  openssl req -new -x509 -sha256 -newkey rsa:4096 -nodes \
    -subj "/C=MG/ST=Trial/L=K8SLABS/O=Dev/CN=localhost" \
    -keyout $root_dir/certs/tls.key \
    -days 365 \
    -out $root_dir/certs/tls.crt

  # Create cluster
  sed "s/\[VERSION\]/$version/g" $root_dir/manifest/kind-cluster.yaml| tee $root_dir/manifest/kind.gen.yaml
  kind create cluster --config $root_dir/manifest/kind.gen.yaml --name $cluster
  kubectl wait --for=condition=Ready --all nodes
  kubectl config use-context kind-$cluster

  # Install ingress controller
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/ingress-nginx-2.16.0/deploy/static/provider/kind/deploy.yaml
  kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=90s

  # Install local-path-provisioner
  kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
  kubectl wait --namespace local-path-storage --for=condition=ready --all pod
  kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/examples/pvc.yaml

  if [[ $with_metrics == "yes" ]]; then
    echo "installing metrics components n kube-system..."
    kubectl apply -f apply $root_dir/manifest/metrics-server.yaml
    kubectl wait --namespace kube-system \
      --for=condition=ready pod \
      --selector=k8s-app=metrics-server \
      --timeout=90s
  fi

  # Summary
  kubectl get all --all-namespaces
}

setup $args