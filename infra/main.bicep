
param location string = 'uksouth'
param envName string = 'dev'
param baseName string = toLower(replace('ppf-rag-${uniqueString(resourceGroup().id)}', '_', ''))

var tags = {
  env: envName
  system: 'runbook-rag-mvp-docx'
}

// Storage for docs & runbooks
resource stData 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: substring(replace('st${baseName}', '-', ''), 0, 23)
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  tags: tags
}

resource stData_blob 'Microsoft.Storage/storageAccounts/blobServices@2022-09-01' = {
  name: 'default'
  parent: stData
}

resource containerDocs 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  name: '${stData.name}/default/docs'
}
resource containerRunbooks 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  name: '${stData.name}/default/runbooks'
}

// App Insights
resource appi 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${baseName}'
  location: location
  kind: 'web'
  properties: { Application_Type: 'web' }
  tags: tags
}

// Key Vault (RBAC)
resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv-${baseName}'
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enablePurgeProtection: true
    enableSoftDelete: true
    enabledForTemplateDeployment: true
    accessPolicies: []
  }
  tags: tags
}

// Azure AI Search
resource search 'Microsoft.Search/searchServices@2023-11-01' = {
  name: 'srch-${baseName}'
  location: location
  sku: { name: 'basic' }
  properties: {
    hostingMode: 'default'
    partitionCount: 1
    replicaCount: 1
    disableLocalAuth: false
    semanticSearch: null
  }
  tags: tags
}

// Azure OpenAI
resource aoai 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: 'aoai-${baseName}'
  location: location
  sku: { name: 'S0' }
  kind: 'OpenAI'
  properties: {
    publicNetworkAccess: 'Enabled'
    customSubDomainName: 'aoai-${baseName}'
  }
  tags: tags
}

// OpenAI deployments
resource depGpt 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  name: 'gpt-4o-mini'
  parent: aoai
  properties: {
    model: { format: 'OpenAI', name: 'gpt-4o-mini', version: 'latest' }
    raiPolicyName: 'Microsoft.Default'
  }
}
resource depEmb 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  name: 'text-embedding-3-small'
  parent: aoai
  properties: {
    model: { format: 'OpenAI', name: 'text-embedding-3-small', version: 'latest' }
    raiPolicyName: 'Microsoft.Default'
  }
}

// Function App plan (consumption)
resource planPy 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: 'plan-py-${baseName}'
  location: location
  kind: 'functionapp'
  sku: { name: 'Y1', tier: 'Dynamic' }
  tags: tags
}

// Function App (managed identity)
resource funcPy 'Microsoft.Web/sites@2022-09-01' = {
  name: 'func-py-${baseName}'
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
    }
    httpsOnly: true
  }
  tags: tags
}

// Static Web App (Free tier)
resource swa 'Microsoft.Web/staticSites@2022-03-01' = {
  name: 'swa-${baseName}'
  location: location
  sku: {
    name: 'Free'
    tier: 'Free'
  }
  properties: {
    repositoryUrl: 'https://example.com/placeholder.git'
    branch: 'main'
    buildProperties: {
      appLocation: 'src/portal'
      outputLocation: 'dist'
    }
  }
  tags: tags
}

// RBAC assignments
resource roleBlobPy 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(stData.id, funcPy.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: stData
  properties: {
    principalId: funcPy.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
  }
}
resource roleSearch 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(search.id, funcPy.id, '7ca78c08-252a-4471-8644-bb5ff32d4ba0')
  scope: search
  properties: {
    principalId: funcPy.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7ca78c08-252a-4471-8644-bb5ff32d4ba0') // Search Index Data Contributor
  }
}
resource roleAOAI 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aoai.id, funcPy.id, '3f88fce2-fbea-4b41-8f87-8821b88348b5')
  scope: aoai
  properties: {
    principalId: funcPy.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3f88fce2-fbea-4b41-8f87-8821b88348b5') // Cognitive Services OpenAI User
  }
}
resource roleKV 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, funcPy.id, '4633458b-17de-408a-b874-0445c86b69e6')
  scope: kv
  properties: {
    principalId: funcPy.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
  }
}
