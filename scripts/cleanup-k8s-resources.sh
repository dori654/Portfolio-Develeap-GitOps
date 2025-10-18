#!/bin/bash

echo "🧹 Cleaning up Kubernetes resources before Terraform destroy..."
echo ""

# 1. Delete LoadBalancer services
echo "📋 Step 1: Deleting LoadBalancer services..."
kubectl delete svc kibana-kibana -n logging --ignore-not-found=true
echo "   ✅ Kibana LoadBalancer deleted"

# 2. Delete Ingress resources (this will remove AWS ALB/NLB)
echo ""
echo "📋 Step 2: Deleting Ingress resources..."
kubectl delete ingress --all -A --timeout=60s
echo "   ✅ All Ingress resources deleted"

# 3. Delete ArgoCD applications to clean up resources
echo ""
echo "📋 Step 3: Deleting ArgoCD applications..."
kubectl delete applications --all -n argocd --timeout=120s
echo "   ✅ All ArgoCD applications deleted"

# 4. Force delete stuck ingress-nginx namespace resources
echo ""
echo "📋 Step 4: Cleaning up ingress-nginx namespace..."
if kubectl get namespace ingress-nginx &>/dev/null; then
    echo "   🔍 Found ingress-nginx namespace, cleaning up..."

    # Delete any LoadBalancer services in ingress-nginx
    kubectl delete svc --all -n ingress-nginx --timeout=30s --ignore-not-found=true

    # Force delete all pods
    kubectl delete pods --all -n ingress-nginx --force --grace-period=0 --ignore-not-found=true

    # Remove finalizers from namespace to force deletion
    kubectl get namespace ingress-nginx -o json | jq '.spec.finalizers = []' | kubectl replace --raw /api/v1/namespaces/ingress-nginx/finalize -f - 2>/dev/null || true

    echo "   ✅ Ingress-nginx namespace cleaned up"
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
