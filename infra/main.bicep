param location string = 'uksouth'
param envName string = 'dev'
param baseName string = toLower(replace('mvp-rag-${uniqueString(resourceGroup().id)}', '_', ''))

var tags = {
  env: envName
  system: 'runbook-rag-mvp'
}

// Helpers & safe name caps
var baseNoDash = toLower(replace(baseName, '-', ''))
var stBase = toLower(replace('st${baseNoDash}', '-', ''))
var stName = take(length(stBase) < 3 ? 'st${take(uniqueString(resourceGroup().id), 21)}' : stBase, 24)
var searchName = take('srch-${baseName}', 60)
var aoaiName = take('aoai-${baseName}', 64)
var aoaiSubdomain = take('aoai-${baseName}', 64)
var planPyName = take('plan-py-${baseName}', 40)
var planNodeName = take('plan-node-${baseName}', 40)
var funcPyName = take('func-py-${baseName}', 60)
var funcNodeName = take('func-node-${baseName}', 60)
var kvName = take(toLower(replace('kv${baseNoDash}', '-', '')), 24)
var appiName = take('appi-${baseName}', 60)

// Storage
resource stData 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: stName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  tags: tags
}

// Enable Static Website using REST API
resource stData_blob 'Microsoft.Storage/storageAccounts/blobServices@2022-09-01' = {
  parent: stData
  name: 'default'
}

resource staticWebsite 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${stData.name}-staticwebsite'
  location: location
  kind: 'AzurePowerShell'
  properties: {
    azPowerShellVersion: '11.0'
    scriptContent: '''
      $storageAccount = Get-AzStorageAccount -ResourceGroupName $env:resourceGroup -Name $env:storageAccountName
      $ctx = $storageAccount.Context
      Enable-AzStorageStaticWebsite -Context $ctx -IndexDocument index.html -ErrorDocument404Path index.html
    '''
    environmentVariables: [
      { name: 'resourceGroup', value: resourceGroup().name }
      { name: 'storageAccountName', value: stData.name }
    ]
    retentionInterval: 'PT1H'
  }
}

resource containerDocs 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  name: '${stData.name}/default/docs'
}
resource containerRunbooks 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  name: '${stData.name}/default/runbooks'
}

// App Insights
resource appi 'Microsoft.Insights/components@2020-02-02' = {
  name: appiName
  location: location
  kind: 'web'
  properties: { Application_Type: 'web' }
  tags: tags
}

// Key Vault
resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: kvName
  location: location
  properties: {
    sku: { family: 'A', name: 'standard' }
    tenantId: subscription().tenantId
    enablePurgeProtection: true
    enableSoftDelete: true
    enabledForTemplateDeployment: true
    accessPolicies: []
    // If you want data‑plane RBAC, uncomment this:
    // enableRbacAuthorization: true
  }
  tags: tags
}

// Azure AI Search
resource search 'Microsoft.Search/searchServices@2023-11-01' = {
  name: searchName
  location: location
  sku: { name: 'basic' }
  properties: {
    hostingMode: 'default'
    partitionCount: 1
    replicaCount: 1
    disableLocalAuth: false
    semanticSearch: 'free'
  }
  tags: tags
}

// Azure OpenAI
resource aoai 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: aoaiName
  location: location
  sku: { name: 'S0' }
  kind: 'OpenAI'
  properties: {
    publicNetworkAccess: 'Enabled'
    customSubDomainName: aoaiSubdomain
  }
  tags: tags
}

resource depGpt 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  parent: aoai
  name: 'gpt-4o-mini'
  properties: {
    model: { format: 'OpenAI', name: 'gpt-4o-mini', version: 'latest' }
    raiPolicyName: 'Microsoft.Default'
  }
}

resource depEmb 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  parent: aoai
  name: 'text-embedding-3-small'
  properties: {
    model: { format: 'OpenAI', name: 'text-embedding-3-small', version: 'latest' }
    raiPolicyName: 'Microsoft.Default'
  }
}

// Plans
resource planPy 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: planPyName
  location: location
  kind: 'functionapp'
  sku: { name: 'Y1', tier: 'Dynamic' }
  tags: tags
}
resource planNode 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: planNodeName
  location: location
  kind: 'functionapp'
  sku: { name: 'Y1', tier: 'Dynamic' }
  tags: tags
}

// Functions
resource funcPy 'Microsoft.Web/sites@2022-09-01' = {
  name: funcPyName
  location: location
  kind: 'functionapp,linux'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: planPy.id
    siteConfig: {
      appSettings: [
        { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'python' }
        { name: 'AzureWebJobsStorage', value: 'DefaultEndpointsProtocol=https;AccountName=${stData.name};AccountKey=${stData.listKeys().keys[0].value};EndpointSuffix=core.windows.net' }
        { name: 'DATA_STORAGE_CONNECTION', value: 'DefaultEndpointsProtocol=https;AccountName=${stData.name};AccountKey=${stData.listKeys().keys[0].value};EndpointSuffix=core.windows.net' }
        { name: 'DOCS_CONTAINER', value: 'docs' }
        { name: 'RUNBOOKS_CONTAINER', value: 'runbooks' }
        { name: 'SEARCH_ENDPOINT', value: 'https://${search.name}.search.windows.net' }
        { name: 'SEARCH_INDEX', value: 'support-docs' }
        { name: 'AOAI_ENDPOINT', value: 'https://${aoai.properties.customSubDomainName}.openai.azure.com' }
        { name: 'AOAI_DEPLOYMENT', value: 'gpt-4o-mini' }
        { name: 'EMBED_DEPLOYMENT', value: 'text-embedding-3-small' }
        { name: 'APPINSIGHTS_INSTRUMENTATIONKEY', value: appi.properties.InstrumentationKey }
      ]
      linuxFxVersion: 'Python|3.10'
      cors: {
        allowedOrigins: [] // we add the static website origin post-deploy
      }
    }
    httpsOnly: true
    clientAffinityEnabled: false
  }
  tags: tags
}

resource funcNode 'Microsoft.Web/sites@2022-09-01' = {
  name: funcNodeName
  location: location
  kind: 'functionapp,linux'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: planNode.id
    siteConfig: {
      appSettings: [
        { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'node' }
        { name: 'AzureWebJobsStorage', value: 'DefaultEndpointsProtocol=https;AccountName=${stData.name};AccountKey=${stData.listKeys().keys[0].value};EndpointSuffix=core.windows.net' }
        { name: 'STORAGE_CONNECTION', value: 'DefaultEndpointsProtocol=https;AccountName=${stData.name};AccountKey=${stData.listKeys().keys[0].value};EndpointSuffix=core.windows.net' }
        { name: 'RUNBOOKS_CONTAINER', value: 'runbooks' }
        { name: 'APPINSIGHTS_INSTRUMENTATIONKEY', value: appi.properties.InstrumentationKey }
        { name: 'PLAYWRIGHT_BROWSERS_PATH', value: '0' }
      ]
      linuxFxVersion: 'Node|18'
      cors: { allowedOrigins: [] }
    }
    httpsOnly: true
    clientAffinityEnabled: false
  }
  tags: tags
}

// ---------------------------
// RBAC (BCP120-safe deterministic names)
// ---------------------------

// Role definition IDs
var roleDefStorageBlobDataContributor = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
var roleDefSearchDataRole             = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7ca78c08-252a-4471-8644-bb5ff32d4ba0')
var roleDefOpenAIUser                 = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3f88fce2-fbea-4b41-8f87-8821b88348b5')
var roleDefKeyVaultSecretsUser        = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')

// Storage: funcPy -> Blob Data Contributor
resource roleBlobPy 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  // name must be start-of-deployment calculable (no principalId). Use scope.id + funcPy.id + roleDef.
  name: guid(stData.id, funcPy.id, roleDefStorageBlobDataContributor)
  scope: stData
  properties: {
    principalId: funcPy.identity.principalId
    roleDefinitionId: roleDefStorageBlobDataContributor
    principalType: 'ServicePrincipal'
  }
}

// Storage: funcNode -> Blob Data Contributor
resource roleBlobNode 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(stData.id, funcNode.id, roleDefStorageBlobDataContributor)
  scope: stData
  properties: {
    principalId: funcNode.identity.principalId
    roleDefinitionId: roleDefStorageBlobDataContributor
    principalType: 'ServicePrincipal'
  }
}

// Azure Cognitive Search: funcPy -> Search data role
resource roleSearch 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(search.id, funcPy.id, roleDefSearchDataRole)
  scope: search
  properties: {
    principalId: funcPy.identity.principalId
    roleDefinitionId: roleDefSearchDataRole
    principalType: 'ServicePrincipal'
  }
}

// Azure OpenAI: funcPy -> OpenAI user
resource roleAOAI 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aoai.id, funcPy.id, roleDefOpenAIUser)
  scope: aoai
  properties: {
    principalId: funcPy.identity.principalId
    roleDefinitionId: roleDefOpenAIUser
    principalType: 'ServicePrincipal'
  }
}

// Key Vault: funcPy -> Key Vault Secrets User
resource roleKV 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, funcPy.id, roleDefKeyVaultSecretsUser)
  scope: kv
  properties: {
    principalId: funcPy.identity.principalId
    roleDefinitionId: roleDefKeyVaultSecretsUser
    principalType: 'ServicePrincipal'
  }
}
