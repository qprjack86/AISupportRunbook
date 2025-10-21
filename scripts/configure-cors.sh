#!/usr/bin/env bash
set -euo pipefail
RG="$1"
STG=$(az resource list -g "$RG" --resource-type Microsoft.Storage/storageAccounts --query [0].name -o tsv)
FUNC_PY=$(az functionapp list -g "$RG" --query "[?contains(name, 'func-py')].name" -o tsv)
FUNC_NODE=$(az functionapp list -g "$RG" --query "[?contains(name, 'func-node')].name" -o tsv)
ORIGIN="https://$STG.z13.web.core.windows.net"
az functionapp cors add -g "$RG" -n "$FUNC_PY" --allowed-origins "$ORIGIN"
az functionapp cors add -g "$RG" -n "$FUNC_NODE" --allowed-origins "$ORIGIN"
