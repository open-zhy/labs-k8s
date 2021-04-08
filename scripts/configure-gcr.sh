#!/bin/bash
set -o errexit

if [ -z "$CLUSTER_CONTEXT" ]; then
  KUBECTL="$(which kubectl) -n default"  
else
  KUBECTL="$(which kubectl) $CLUSTER_CONTEXT"
fi

GOOGLE_KEY_FILE=$1

if [ "$#" -eq 0 ]; then
  echo "ERR: missing argument, provide at least the Google Key path"
  exit 1
fi

[ -f $GOOGLE_KEY_FILE ] || (echo "'$GOOGLE_KEY_FILE' does not exist." && exit 1)

shift;

NAMESPACES="default $@"

echo "configuring cluster to be bound with Google Cloud Registry..."
for ns in $NAMESPACES; do
  $KUBECTL -n $ns delete secret gcr-json-key || echo "gcr-json-key is not in $ns" \
  && $KUBECTL -n $ns create secret docker-registry gcr-json-key \
    --docker-server=gcr.io \
    --docker-username=_json_key \
    --docker-password="$(cat $GOOGLE_KEY_FILE)" \
    --docker-email=$(cat $GOOGLE_KEY_FILE | jq .client_email) \
  && $KUBECTL -n $ns patch serviceaccount default -p '{"imagePullSecrets": [{"name": "gcr-json-key"}]}'
done