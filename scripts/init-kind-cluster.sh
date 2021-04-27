#!/bin/bash

args=""
with_metrics=no
generate_cert=no
while (( "$#" )); do 
  case $1 in
  --with-metrics) with_metrics=yes; shift;;
  --generate-cert) generate_cert=yes; shift;;
  esac
  args+="$1 "
  shift
done

shift $(($OPTIND-1))

echo "args=$args"

root_dir=$(dirname $(cd $(dirname $BASH_SOURCE) && pwd))

create_self_signed_certificates() {
  # create self-signed certificates
  certs_dir=$1
  mkdir -p $certs_dir
  openssl req -new -x509 -sha256 -newkey rsa:4096 -nodes \
    -subj "/C=MG/ST=Trial/L=K8SLABS/O=Dev/CN=localhost" \
    -keyout $certs_dir/tls.key \
    -days 365 \
    -out $certs_dir/tls.crt
}

create_cluster() {
  sed "s/\[VERSION\]/$version/g" $root_dir/manifest/kind-cluster.yaml| tee $root_dir/manifest/kind.gen.yaml
  kind create cluster --config $root_dir/manifest/kind.gen.yaml --name $1
  kubectl wait --for=condition=Ready --all nodes
  kubectl config use-context kind-$1
}

install_ingress_controller() {
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/ingress-nginx-2.16.0/deploy/static/provider/kind/deploy.yaml
  kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=90s
}

install_metrics_server() {
  echo "installing metrics components n kube-system..."
  kubectl apply -f $root_dir/manifest/metrics-server.yaml
  kubectl wait --namespace kube-system \
    --for=condition=ready pod \
    --selector=k8s-app=metrics-server \
    --timeout=90s
}

provision_localpath() {
  kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
  kubectl wait --namespace local-path-storage --for=condition=ready --all pod
  kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/examples/pvc.yaml
}

setup() {
  cluster=${1:-kube-labs}
  version=${2:-'1.6.15'}

  if [[ $generate_cert == "yes" ]]; then
    create_self_signed_certificates $root_dir/certs
  fi

  # Create cluster
  echo "creating kind cluster, name=$cluster, version=$version, with_metrics=$with_metrics..."
  create_cluster $cluster

  # Install ingress controller
  install_ingress_controller

  # Install local-path-provisioner
  provision_localpath


  if [[ $with_metrics == "yes" ]]; then
    # install metrics-server
    install_metrics_server
  fi

  # Summary
  kubectl get all --all-namespaces
}

setup $args