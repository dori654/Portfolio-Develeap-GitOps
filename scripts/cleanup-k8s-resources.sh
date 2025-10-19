#!/bin/bash

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "🧹 Cleaning up Kubernetes resources before Terraform destroy..."
echo ""

# Function to force delete a stuck namespace
force_delete_namespace() {
    local namespace=$1
    echo "   🔍 Attempting to force delete namespace: $namespace"

    # Delete all pods with force
    echo "      ↳ Force deleting all pods..."
    kubectl delete pods --all -n "$namespace" --force --grace-period=0 --ignore-not-found=true 2>/dev/null || true

    # Delete all deployments
    echo "      ↳ Force deleting deployments..."
    kubectl delete deployment --all -n "$namespace" --force --grace-period=0 --ignore-not-found=true 2>/dev/null || true

    # Delete all replicasets
    echo "      ↳ Force deleting replicasets..."
    kubectl delete replicaset --all -n "$namespace" --force --grace-period=0 --ignore-not-found=true 2>/dev/null || true

    # Delete all services
    echo "      ↳ Deleting services..."
    kubectl delete service --all -n "$namespace" --force --grace-period=0 --ignore-not-found=true 2>/dev/null || true

    # Remove finalizers from namespace
    echo "      ↳ Removing namespace finalizers..."
    kubectl get namespace "$namespace" -o json 2>/dev/null | jq '.spec.finalizers = []' | kubectl replace --raw /api/v1/namespaces/$namespace/finalize -f - 2>/dev/null || true

    # Wait a moment for deletion
    sleep 2

    # Check if namespace still exists
    if kubectl get namespace "$namespace" &>/dev/null; then
        echo -e "      ${YELLOW}⚠️  Namespace $namespace still exists (may take a moment)${NC}"
        return 1
    else
        echo -e "      ${GREEN}✅ Namespace $namespace deleted successfully${NC}"
        return 0
    fi
}

# 1. Delete LoadBalancer services
echo "📋 Step 1: Deleting LoadBalancer services..."
kubectl delete svc kibana-kibana -n logging --ignore-not-found=true --timeout=30s 2>/dev/null || true
echo "   ✅ Kibana LoadBalancer deleted"

# 2. Delete Ingress resources (this will remove AWS ALB/NLB)
echo ""
echo "📋 Step 2: Deleting Ingress resources..."
kubectl delete ingress --all -A --timeout=60s --ignore-not-found=true 2>/dev/null || true
echo "   ✅ All Ingress resources deleted"

# 3. Delete ArgoCD applications to clean up resources
echo ""
echo "📋 Step 3: Deleting ArgoCD applications..."
kubectl delete applications --all -n argocd --timeout=120s --ignore-not-found=true 2>/dev/null || true
echo "   ✅ All ArgoCD applications deleted"

# 4. Force delete stuck ingress-nginx namespace resources
echo ""
echo "📋 Step 4: Cleaning up ingress-nginx namespace..."
if kubectl get namespace ingress-nginx &>/dev/null; then
    echo "   🔍 Found ingress-nginx namespace, cleaning up..."

    # Check if namespace is in Terminating state
    NS_STATUS=$(kubectl get namespace ingress-nginx -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

    if [ "$NS_STATUS" = "Terminating" ]; then
        echo -e "   ${YELLOW}⚠️  Namespace is stuck in Terminating state${NC}"
        force_delete_namespace "ingress-nginx"
    else
        # Delete any LoadBalancer services in ingress-nginx
        kubectl delete svc --all -n ingress-nginx --timeout=30s --ignore-not-found=true 2>/dev/null || true

        # Force delete all pods
        kubectl delete pods --all -n ingress-nginx --force --grace-period=0 --ignore-not-found=true 2>/dev/null || true

        # Remove finalizers from namespace to force deletion
        kubectl get namespace ingress-nginx -o json 2>/dev/null | jq '.spec.finalizers = []' | kubectl replace --raw /api/v1/namespaces/ingress-nginx/finalize -f - 2>/dev/null || true

        echo "   ✅ Ingress-nginx namespace cleaned up"
    fi
else
    echo "   ✅ No ingress-nginx namespace found"
fi

# 4. Delete persistent volumes claims
echo ""
# echo "📋 Step 4: Deleting PVCs (which delete EBS volumes)..."
# kubectl delete pvc --all -A --timeout=120s
# echo "   ✅ All PVCs deleted"

# 5. Wait for AWS resources to be released
echo ""
echo "⏳ Waiting 60 seconds for AWS resources to be released..."
sleep 60

# 6. Check for remaining LoadBalancers
echo ""
echo "📋 Step 5: Checking for remaining LoadBalancer services..."
LBS=$(kubectl get svc -A -o json | jq -r '.items[] | select(.spec.type=="LoadBalancer") | "\(.metadata.namespace)/\(.metadata.name)"')
if [ -z "$LBS" ]; then
    echo "   ✅ No LoadBalancer services found"
else
    echo "   ⚠️  Found remaining LoadBalancers:"
    echo "$LBS"
    echo "   Deleting them..."
    while IFS= read -r lb; do
        ns=$(echo $lb | cut -d'/' -f1)
        name=$(echo $lb | cut -d'/' -f2)
        kubectl delete svc "$name" -n "$ns" --force --grace-period=0
    done <<< "$LBS"
fi

echo ""
echo "✅ Kubernetes cleanup complete!"
echo ""
echo "You can now run: terraform destroy -auto-approve"
