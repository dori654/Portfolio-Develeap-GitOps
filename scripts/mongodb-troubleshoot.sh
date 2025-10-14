#!/bin/bash

# MongoDB Troubleshooting Script for Cat Agency
# This script fixes common MongoDB StatefulSet issues

set -e

NAMESPACE="cat-agency"
STATEFULSET_NAME="mongodb-replica-set"
SERVICE_ACCOUNT="mongodb-database"

echo "🔧 MongoDB Troubleshooting Script for Cat Agency"
echo "================================================="

# Check if namespace exists
echo "📋 Checking namespace: $NAMESPACE"
if ! kubectl get namespace $NAMESPACE > /dev/null 2>&1; then
    echo "❌ Namespace $NAMESPACE does not exist!"
    exit 1
fi
echo "✅ Namespace exists"

# Check/Create service account
echo "📋 Checking service account: $SERVICE_ACCOUNT"
if ! kubectl get serviceaccount $SERVICE_ACCOUNT -n $NAMESPACE > /dev/null 2>&1; then
    echo "⚠️  Service account missing, creating..."
    kubectl create serviceaccount $SERVICE_ACCOUNT -n $NAMESPACE
    echo "✅ Service account created"
else
    echo "✅ Service account exists"
fi

# Check StatefulSet status
echo "📋 Checking StatefulSet: $STATEFULSET_NAME"
if ! kubectl get statefulset $STATEFULSET_NAME -n $NAMESPACE > /dev/null 2>&1; then
    echo "❌ StatefulSet $STATEFULSET_NAME does not exist!"
    exit 1
fi

CURRENT_REPLICAS=$(kubectl get statefulset $STATEFULSET_NAME -n $NAMESPACE -o jsonpath='{.spec.replicas}')
READY_REPLICAS=$(kubectl get statefulset $STATEFULSET_NAME -n $NAMESPACE -o jsonpath='{.status.readyReplicas}')

echo "   Current replicas: $CURRENT_REPLICAS"
echo "   Ready replicas: $READY_REPLICAS"

# Scale StatefulSet if needed
if [ "$CURRENT_REPLICAS" = "0" ] || [ -z "$READY_REPLICAS" ] || [ "$READY_REPLICAS" = "null" ]; then
    echo "⚠️  StatefulSet needs scaling, scaling to 1 replica..."
    kubectl scale statefulset $STATEFULSET_NAME --replicas=1 -n $NAMESPACE
    echo "✅ StatefulSet scaled to 1 replica"
else
    echo "✅ StatefulSet is properly scaled"
fi

# Wait for MongoDB pod to be ready
echo "📋 Waiting for MongoDB pod to be ready..."
if kubectl wait --for=condition=ready pod/mongodb-replica-set-0 -n $NAMESPACE --timeout=60s; then
    echo "✅ MongoDB pod is ready!"
else
    echo "⚠️  MongoDB pod is not ready yet, checking status..."
    kubectl get pods -n $NAMESPACE | grep mongodb
    echo ""
    echo "📋 Recent events:"
    kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -5
fi

# Check backend connectivity
echo "📋 Checking backend pods..."
BACKEND_PODS=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/component=backend --no-headers | wc -l)
if [ "$BACKEND_PODS" -gt 0 ]; then
    echo "   Found $BACKEND_PODS backend pods"
    kubectl get pods -n $NAMESPACE -l app.kubernetes.io/component=backend
else
    echo "   No backend pods found"
fi

echo ""
echo "🎉 MongoDB troubleshooting completed!"
echo ""
echo "📋 Current status summary:"
kubectl get pods,svc,statefulsets -n $NAMESPACE