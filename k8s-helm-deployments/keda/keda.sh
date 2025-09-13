#!/bin/bash
# KEDA Helm installation script

NAMESPACE=keda
HELM_RELEASE=keda

# Check if already installed
if ! helm list -n ${NAMESPACE} | grep -q ${HELM_RELEASE}; then
    echo "KEDA not found. Installing..."
    mkdir -p ~/keda && pushd ~/keda

    helm repo add kedacore https://kedacore.github.io/charts
    helm repo update
    kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    helm install ${HELM_RELEASE} kedacore/keda -n ${NAMESPACE} -f keda-affinity.yaml

    popd
else
    echo "KEDA already installed in namespace ${NAMESPACE}."
fi

echo "Check KEDA pods:"
kubectl get pods -n ${NAMESPACE}
