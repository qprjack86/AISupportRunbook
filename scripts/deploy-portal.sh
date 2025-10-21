#!/usr/bin/env bash
set -euo pipefail
RG="$1"
STG=$(az resource list -g "$RG" --resource-type Microsoft.Storage/storageAccounts --query [0].name -o tsv)

pushd src/portal > /dev/null
npm ci
npm run build
popd > /dev/null

az storage blob service-properties update   --account-name "$STG"   --static-website --index-document index.html --404-document index.html

az storage blob upload-batch   -s src/portal/dist   -d '$web'   --account-name "$STG"

echo "Portal published at: https://$STG.z13.web.core.windows.net/"
