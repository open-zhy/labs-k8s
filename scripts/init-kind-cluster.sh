#!/bin/bash

CLUSTER_NAME=${1:-kube-labs}
ROOT_DIR=$(dirname $(cd $(dirname $BASH_SOURCE) && pwd))

echo CLUSTER_NAME=$CLUSTER_NAME;

# create self-signed certificates
mkdir -p $ROOT_DIR/certs
openssl req -new -x509 -sha256 -newkey rsa:4096 -nodes \
	-subj "/C=MG/ST=Trial/L=K8SLABS/O=Dev/CN=localhost" \
    -keyout $ROOT_DIR/certs/tls.key \
    -days 365 \
    -out $ROOT_DIR/certs/tls.crt

exit;
# Create cluster
kind create cluster --config $ROOT_DIR/manifest/kind-cluster.yaml --name $CLUSTER_NAME
kubectl wait --for=condition=Ready --all nodes
kubectl config use-context kind-$CLUSTER_NAME

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

 # Summary
 kubectl get all --all-namespaces