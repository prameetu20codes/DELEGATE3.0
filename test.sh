# 1. Point kubectl at the cluster
gcloud container clusters get-credentials harness-test \
  --region us-central1 --project customer-success-244100

# 2. Service account + admin rights for Harness
kubectl create serviceaccount harness-deployer -n default
kubectl create clusterrolebinding harness-deployer \
  --clusterrole=cluster-admin --serviceaccount=default:harness-deployer

# 3. Long-lived (non-expiring) token bound to that SA
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: harness-deployer-token
  namespace: default
  annotations:
    kubernetes.io/service-account.name: harness-deployer
type: kubernetes.io/service-account-token
EOF

# 4. Pull the values you'll paste into Harness
echo "== masterUrl =="
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'; echo
echo "== token =="
kubectl get secret harness-deployer-token -n default -o jsonpath='{.data.token}' | base64 -d; echo
echo "== CA cert =="
kubectl get secret harness-deployer-token -n default -o jsonpath='{.data.ca\.crt}' | base64 -d
