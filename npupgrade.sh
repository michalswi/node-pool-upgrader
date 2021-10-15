#!/usr/bin/env bash
set -e

# built-in
# https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/how-to-use-vm-token#get-a-token-using-curl
RESOURCE=https%3A%2F%2Fmanagement.azure.com%2F
API_VERSION=2020-09-01

function envCheck(){
  if [ -z "$ARM_CLIENT_ID" ] || [ -z "$ARM_CLIENT_SECRET" ] || [ -z "$ARM_TENANT_ID" ] || [ -z "$ARM_SUBSCRIPTION_ID" ]; then
    echo "Check if all Azure related arguments were provided. Run '$(basename $0)' for more details."
    exit 1
  fi
  if [ -z "$RESOURCE_GROUP_NAME" ] || [ -z "$CLUSTER_NAME" ] || [ -z "$KUBERNETES_NODE_VERSION" ]; then
    echo "Check if all K8s related arguments were provided. Run '$(basename $0)' for more details."
    exit 1
  fi
}

# Get Token
# https://docs.microsoft.com/en-us/azure/active-directory/develop/access-tokens
# https://docs.microsoft.com/en-us/rest/api/azure/#create-the-request
function getToken(){
  curl -s -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&resource=${RESOURCE}&client_id=${ARM_CLIENT_ID}&client_secret=${ARM_CLIENT_SECRET}" \
  https://login.microsoftonline.com/${ARM_TENANT_ID}/oauth2/token \
  | jq -r '.access_token'
}

# Get Cluster Provisioning State - properties.provisioningState
# https://docs.microsoft.com/en-us/rest/api/aks/managed-clusters/get
function getClusterProvisioningState(){
  curl -s -X GET \
  -H "Authorization: Bearer ${TOKEN}" \
  https://management.azure.com/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP_NAME}/providers/Microsoft.ContainerService/managedClusters/${CLUSTER_NAME}?api-version=${API_VERSION} \
  | jq -r '.properties.provisioningState'
}

# Get Node Pool Provisioning State - properties.provisioningState
# https://docs.microsoft.com/en-us/rest/api/aks/agent-pools/get
function getNodePoolProvisioningState(){
  curl -s -X GET \
  -H "Authorization: Bearer ${TOKEN}" \
  https://management.azure.com/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP_NAME}/providers/Microsoft.ContainerService/managedClusters/${CLUSTER_NAME}/agentPools/${POOL_NAME}?api-version=${API_VERSION} \
  | jq -r '.properties.provisioningState'
}

# Get Node Pool current version - properties.orchestratorVersion
# https://docs.microsoft.com/en-us/rest/api/aks/agent-pools/get
function getNodePoolVersion(){
  curl -s -X GET \
  -H "Authorization: Bearer ${TOKEN}" \
  https://management.azure.com/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP_NAME}/providers/Microsoft.ContainerService/managedClusters/${CLUSTER_NAME}/agentPools/${POOL_NAME}?api-version=${API_VERSION}
}

# Upgrade Node Pool
# https://docs.microsoft.com/en-us/rest/api/aks/agent-pools/create-or-update
function upgradeNodePool(){
  curl -s -X PUT \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d @nodepool.json \
  https://management.azure.com/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP_NAME}/providers/Microsoft.ContainerService/managedClusters/${CLUSTER_NAME}/agentPools/${POOL_NAME}?api-version=${API_VERSION}
}

usage() {
	cat <<EOF
Upgrade an Azure Kubernetes Service (AKS) cluster's Node Pools

Usage: $(basename $0) <command> <pool_name>

Supported commands:
  upgrade <pool_name>       Upgrade node pools
  status  <pool_name>       Check Cluster and Node Pool provisioning state

Provided arguments should be exported (set as a env vars):
  ARM_CLIENT_ID             Service Principal ID
  ARM_CLIENT_SECRET         Service Principal secret/password
  ARM_TENANT_ID             Azure Tenant ID
  ARM_SUBSCRIPTION_ID       Azure Subscription ID

  RESOURCE_GROUP_NAME       RG name where K8s was deployed
  CLUSTER_NAME              K8s cluster name
  KUBERNETES_NODE_VERSION   New K8s version

EOF
	exit 1
}

upgrade() {
  envCheck
  echo "--- Upgrade in progress.. ---"

  POOL_NAME=$1
  TOKEN=$(getToken)
  
  # Check the Node Pool current version
  NODE_POOL_VERSION=$(getNodePoolVersion | jq -r '.properties.orchestratorVersion')
  if [[ ${NODE_POOL_VERSION} == ${KUBERNETES_NODE_VERSION} ]] ; then
    echo "Node Pool Version was already upgraded to ${KUBERNETES_NODE_VERSION}"
    exit 0
  fi
  
  # Get the Node Pool version and make payload for upgrade
  getNodePoolVersion | jq ".properties.orchestratorVersion = \"${KUBERNETES_NODE_VERSION}\"" > nodepool.json
  upgradeNodePool
}

status() {
  envCheck
  echo "--- Checking status.. ---"

  POOL_NAME=$1
  TOKEN=$(getToken)
  
  CLUSTER_STATE=$(getClusterProvisioningState)
  echo "Cluster Provisioning State is ${CLUSTER_STATE}"
  NODE_STATE=$(getNodePoolProvisioningState)
  echo "Node Pool Provisioning State is ${NODE_STATE}"
}

if [ $# -eq 0 ]; then
  usage
elif [ $# -eq 1 ]; then
  echo "Missing <pool_name>. Run '$(basename $0)' for more details."
elif [ $# -gt 2 ]; then
  usage
else
  CMD="$1"
  ARGS="${@:2}"
  shift
  case "$CMD" in
    upgrade)
      upgrade $ARGS
    ;;
    status)
      status $ARGS
    ;;
  esac
fi
