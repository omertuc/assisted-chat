#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

SECRETS_BASE_PATH="${SECRETS_BASE_PATH:-/var/run/secrets}"

#All the secret are expected to be mounted under /var/run/secrets by the ci-operator

#$ASSISTED_CHAT_IMG is not in repo/image:tag format but rather in repo/<image name>@sha256:<digest>
#The template needs the tag, and it references the image by <image name>:<tag> so splitting the variable by ":" works for now

echo "$ASSISTED_CHAT_IMG"
IMAGE=$(echo "$ASSISTED_CHAT_IMG" | cut -d ":" -f1)
TAG=$(echo "$ASSISTED_CHAT_IMG" | cut -d ":" -f2)

if ! oc get secret -n "$NAMESPACE" gemini-api-key &>/dev/null; then
    echo "Creating gemini-api-key secret in namespace $NAMESPACE"
    oc create secret generic -n "$NAMESPACE" gemini-api-key --from-file=api_key="$SECRETS_BASE_PATH/gemini/api_key"
fi

if ! oc get secret -n "$NAMESPACE" insights-ingress &>/dev/null; then
    echo "Creating insights-ingress secret in namespace $NAMESPACE"
    oc create secret generic -n "$NAMESPACE" insights-ingress --from-literal=auth_token="dummy-token"
fi


# Create postgres secret with dummy credentials
if ! oc get secret -n "$NAMESPACE" llama-stack-db &>/dev/null; then
    echo "Creating llama-stack-db secret with local postgres credentials in namespace $NAMESPACE"
    oc create secret generic -n "$NAMESPACE" llama-stack-db \
        --from-literal=db.host=postgres-service \
        --from-literal=db.port=5432 \
        --from-literal=db.name=assistedchat \
        --from-literal=db.user=assistedchat \
        --from-literal=db.password=assistedchat123 \
        --from-literal=db.ca_cert=""
fi

# Deploy postgres
if ! oc get secret -n "$NAMESPACE" postgres-secret &>/dev/null; then
    echo "Creating postgres-secret in namespace $NAMESPACE"
    oc create secret generic -n "$NAMESPACE" postgres-secret \
        --from-literal=POSTGRES_DB=assistedchat \
        --from-literal=POSTGRES_USER=assistedchat \
        --from-literal=POSTGRES_PASSWORD=assistedchat123
fi

if ! oc get deployment -n "$NAMESPACE" postgres &>/dev/null; then
    echo "Creating postgres deployment in namespace $NAMESPACE"
    oc create deployment -n "$NAMESPACE" postgres --image=postgres:15
    oc set env -n "$NAMESPACE" deployment/postgres --from=secret/postgres-secret
fi

if ! oc get service -n "$NAMESPACE" postgres-service &>/dev/null; then
    echo "Creating postgres service in namespace $NAMESPACE"
    oc expose -n "$NAMESPACE" deployment/postgres --name=postgres-service --port=5432
fi

echo "GEMINI_API_KEY=$(cat "$SECRETS_BASE_PATH/gemini/api_key")" >.env

make generate
sed -i 's/user_id_claim: sub/user_id_claim: client_id/g' config/lightspeed-stack.yaml
sed -i 's/username_claim: preferred_username/username_claim: clientHost/g' config/lightspeed-stack.yaml

if ! oc get routes -n "$NAMESPACE" &>/dev/null; then
    # Don't apply routes on non-OCP clusters (e.g. minikube)
    FILTER='select(.kind != "Route")'
else
    FILTER='.'
fi

oc process \
    -p IMAGE="$IMAGE" \
    -p IMAGE_TAG="$TAG" \
    -p GEMINI_API_SECRET_NAME=gemini-api-key \
    -p VERTEX_API_SECRET_NAME=vertexai \
    -p ASSISTED_CHAT_DB_SECRET_NAME=llama-stack-db \
    -f template.yaml --local |
    jq '. as $root | $root.items = [$root.items[] | '"$FILTER"']' |
    oc apply -n "$NAMESPACE" -f -

sleep 5
oc wait --for=condition=Available deployment/assisted-chat -n "$NAMESPACE" --timeout=300s
