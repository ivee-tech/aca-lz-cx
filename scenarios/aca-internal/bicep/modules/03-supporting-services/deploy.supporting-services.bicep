targetScope = 'resourceGroup'

// ------------------
//    PARAMETERS
// ------------------

@description('The name of the workload that is being deployed. Up to 10 characters long.')
@minLength(2)
@maxLength(10)
param workloadName string

@description('The name of the environment (e.g. "dev", "test", "prod", "uat", "dr", "qa"). Up to 8 characters long.')
@maxLength(8)
param environment string

@description('The location where the resources will be created. This needs to be the same region as the spoke.')
param location string = resourceGroup().location

@description('Optional. The tags to be assigned to the created resources.')
param tags object = {}

// Hub
@description('The resource group name of the existing hub virtual network.')
param hubVNetRGName string
@description('The resource name of the existing hub virtual network.')
param hubVNetName string

// Spoke
@description('The resource name of the existing spoke virtual network to which the private endpoint will be connected.')
param spokeVNetRGName string
@description('The resource name of the existing spoke virtual network to which the private endpoint will be connected.')
param spokeVNetName string

@description('The name of the existing subnet in the spoke virtual to which the private endpoint will be connected.')
param spokePrivateEndpointSubnetName string

@description('Deploy Redis cache premium SKU')
param deployRedisCache bool

@description('Deploy (or not) an Azure OpenAI account. ATTENTION: At the time of writing this, OpenAI is in preview and only available in limited regions: look here: https://learn.microsoft.com/azure/ai-services/openai/chatgpt-quickstart#prerequisites')
param deployOpenAi bool

@description('Deploy (or not) a model on the openAI Account. This is used only as a sample to show how to deploy a model on the OpenAI account.')
param deployOpenAiGptModel bool = false

@description('Optional. Resource group name of the diagnostic log analytics workspace. If left empty, no diagnostics settings will be defined.')
param laWorkspaceRGName string = ''

@description('Optional. Resource name of the diagnostic log analytics workspace. If left empty, no diagnostics settings will be defined.')
param laWorkspaceName string = ''

@description('Optional, default value is true. If true, any resources that support AZ will be deployed in all three AZ. However if the selected region is not supporting AZ, this parameter needs to be set to false.')
param deployZoneRedundantResources bool = true

// ------------------
// RESOURCES
// ------------------

@description('User-configured naming rules')
module naming '../../../../shared/bicep/naming/naming.module.bicep' = {
  name: take('03-sharedNamingDeployment-${deployment().name}', 64)
  params: {
    uniqueId: uniqueString(resourceGroup().id)
    environment: environment
    workloadName: workloadName
    location: location
  }
}

// Keep the logic below here as it is required for all supporting services
// var hubVNetIdTokens = split(hubVNetId, '/')
// var hubVNetName = length(hubVNetIdTokens) > 8 ? hubVNetIdTokens[8] : ''

resource hubVNet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: hubVNetName
  scope: resourceGroup(hubVNetRGName)
}

resource spokeVNet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: spokeVNetName
  scope: resourceGroup(spokeVNetRGName)
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-11-01' existing = if (laWorkspaceName != '' && laWorkspaceRGName != '') {
  name: laWorkspaceName
  scope: resourceGroup(laWorkspaceRGName)
}

@description('Azure Container Registry, where all workload images should be pulled from.')
module containerRegistry 'modules/container-registry.module.bicep' = {
  name: 'containerRegistry-${uniqueString(resourceGroup().id)}'
  params: {
    containerRegistryName: naming.outputs.resourcesNames.containerRegistry
    location: location
    tags: tags
    spokeVNetId: spokeVNet.id
    hubVNetName: hubVNetName
    hubVNetId: hubVNet.id
    spokePrivateEndpointSubnetName: spokePrivateEndpointSubnetName
    containerRegistryPrivateEndpointName: naming.outputs.resourcesNames.containerRegistryPep
    containerRegistryUserAssignedIdentityName: naming.outputs.resourcesNames.containerRegistryUserAssignedIdentity
    diagnosticWorkspaceId: logAnalyticsWorkspace.id
    deployZoneRedundantResources: deployZoneRedundantResources
  }
}

@description('Azure Key Vault used to hold items like TLS certs and application secrets that your workload will need.')
module keyVault 'modules/key-vault.bicep' = {
  name: 'keyVault-${uniqueString(resourceGroup().id)}'
  params: {
    keyVaultName: naming.outputs.resourcesNames.keyVault
    location: location
    tags: tags
    spokeVNetId: spokeVNet.id
    hubVNetName: hubVNetName
    hubVNetId: hubVNet.id
    spokePrivateEndpointSubnetName: spokePrivateEndpointSubnetName
    keyVaultPrivateEndpointName: naming.outputs.resourcesNames.keyVaultPep
    diagnosticWorkspaceId: logAnalyticsWorkspace.id
  }
}


module redisCache 'modules/redis-cache.bicep' = if (deployRedisCache) {
  name: 'redisCache-${uniqueString(resourceGroup().id)}'
  params: {
    location: location
    redisName: naming.outputs.resourcesNames.redisCache
    logAnalyticsWsId: logAnalyticsWorkspace.id
    keyVaultName: keyVault.outputs.keyVaultName
    spokeVNetId: spokeVNet.id
    hubVNetName: hubVNetName
    hubVNetId: hubVNet.id
    spokePrivateEndpointSubnetName: spokePrivateEndpointSubnetName
    redisCachePrivateEndpointName: naming.outputs.resourcesNames.redisCachePep
  }
}


module openAi 'modules/open-ai.module.bicep'= if(deployOpenAi) {
  name: take('openAiModule-Deployment', 64)
  params: {
    name: naming.outputs.resourcesNames.openAiAccount
    deploymentName: naming.outputs.resourcesNames.openAiDeployment
    location: location
    tags: tags
    vnetHubResourceId: hubVNet.id
    logAnalyticsWsId: logAnalyticsWorkspace.id
    deployOpenAiGptModel: deployOpenAiGptModel
    spokeVNetId: spokeVNet.id
    hubVNetName: hubVNetName
    hubVNetId: hubVNet.id
    spokePrivateEndpointSubnetName: spokePrivateEndpointSubnetName
  }
}

// ------------------
// OUTPUTS
// ------------------

@description('The resource ID of the Azure Container Registry.')
output containerRegistryId string = containerRegistry.outputs.containerRegistryId

@description('The name of the Azure Container Registry.')
output containerRegistryName string = containerRegistry.outputs.containerRegistryName

@description('The name of the container registry login server.')
output containerRegistryLoginServer string = containerRegistry.outputs.containerRegistryLoginServer

@description('The resource ID of the user-assigned managed identity for the Azure Container Registry to be able to pull images from it.')
output containerRegistryUserAssignedIdentityId string = containerRegistry.outputs.containerRegistryUserAssignedIdentityId

@description('The name of the contianer registry agent pool name to build images')
output containerRegistryAgentPoolName string = containerRegistry.outputs.containerRegistryAgentPoolName

@description('The resource ID of the Azure Key Vault.')
output keyVaultId string = keyVault.outputs.keyVaultId

@description('The name of the Azure Key Vault.')
output keyVaultName string = keyVault.outputs.keyVaultName

@description('The secret name to retrieve the connection string from KeyVault')
output redisCacheSecretKey string = (deployRedisCache)? redisCache.outputs.redisCacheSecretKey : ''

@description('The name of the Azure Open AI account name.')
output openAIAccountName string = (deployOpenAi)? openAi.outputs.name : ''
