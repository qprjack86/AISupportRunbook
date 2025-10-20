
param(
  [string]$SearchServiceName,
  [string]$ResourceGroup
)
$endpoint = "https://$SearchServiceName.search.windows.net"
$apiVersion = "2023-11-01"
$adminKey = az search admin-key show -g $ResourceGroup -n $SearchServiceName --query primaryKey -o tsv
$body = Get-Content -Raw -Path (Join-Path $PSScriptRoot 'create-search-index.json')
Invoke-RestMethod -Method Put -Uri "$endpoint/indexes/support-docs?api-version=$apiVersion" -Headers @{ 'api-key' = $adminKey; 'Content-Type' = 'application/json' } -Body $body
