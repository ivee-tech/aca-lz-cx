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

@description('Deploy an Azure Storage account for the workload.')
param deployStorageAccount bool = false

@description('Azure Storage account SKU name.')
param storageAccountSkuName string = 'Standard_LRS'

@description('Azure Storage account kind.')
@allowed([
  'StorageV2'
  'BlockBlobStorage'
  'FileStorage'
  'Storage'
])
param storageAccountKind string = 'StorageV2'

@description('Azure Storage account access tier. Set to an empty string for SKUs that do not support tiers.')
param storageAccountAccessTier string = 'Hot'

@description('Allow shared key authorization for the storage account.')
param storageAccountAllowSharedKeyAccess bool = true

@description('Allow blob public access for the storage account.')
param storageAccountAllowBlobPublicAccess bool = false

@description('Enable hierarchical namespace (Data Lake Storage Gen2) for the storage account.')
param storageAccountEnableHierarchicalNamespace bool = false

@description('Azure Storage account minimum TLS version.')
@allowed([
  'TLS1_0'
  'TLS1_1'
  'TLS1_2'
])
param storageAccountMinimumTlsVersion string = 'TLS1_2'

@description('Storage queue names to create when deploying the storage account.')
param storageAccountQueueNames array = []

@description('Deploy (or not) an Azure OpenAI account. ATTENTION: At the time of writing this, OpenAI is in preview and only available in limited regions: look here: https://learn.microsoft.com/azure/ai-services/openai/chatgpt-quickstart#prerequisites')
param deployOpenAi bool

@description('Deploy an Azure Service Bus namespace for the workload.')
param deployServiceBus bool = false

@description('Deploy an Azure SQL database for the workload.')
param deploySqlDatabase bool = false

@description('Queue names to create when deploying the Service Bus namespace.')
param serviceBusQueueNames array = []

@description('Topic names to create when deploying the Service Bus namespace.')
param serviceBusTopicNames array = []

@description('Service Bus namespace SKU.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param serviceBusSkuName string = 'Premium'

@description('Messaging units used when deploying a Premium Service Bus namespace.')
param serviceBusCapacity int = 1

@description('Enable zone redundancy for the Service Bus namespace (Premium SKU only).')
param serviceBusZoneRedundant bool = true

@description('Public network access setting for the Service Bus namespace.')
@allowed([
  'Enabled'
  'Disabled'
])
param serviceBusPublicNetworkAccess string = 'Disabled'

@description('Allow trusted Azure services to access the Service Bus namespace when public network access is disabled.')
param serviceBusAllowTrustedServicesAccess bool = true

@description('Administrator login for the Azure SQL server.')
param sqlAdministratorLogin string = 'sqladminuser'

@secure()
@description('Administrator password for the Azure SQL server (required when deploySqlDatabase = true).')
param sqlAdministratorPassword string = ''

@description('The name of the Azure SQL database.')
param sqlDatabaseName string = 'planetsdb'

@description('Azure SQL database SKU name (for example, GP_Gen5_2 or S0).')
param sqlDatabaseSkuName string = 'GP_Gen5_2'

@description('Azure SQL database SKU tier.')
param sqlDatabaseSkuTier string = 'GeneralPurpose'

@description('Azure SQL database compute capacity. Set to 0 when not required by the SKU.')
param sqlDatabaseSkuCapacity int = 0

@description('Azure SQL database compute family. Leave empty when not required by the SKU.')
param sqlDatabaseSkuFamily string = ''

@description('Azure SQL database maximum size in GB.')
param sqlDatabaseMaxSizeGb int = 32

@description('Enable zone redundancy for the Azure SQL database (supported tiers only).')
param sqlDatabaseZoneRedundant bool = false

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

var logAnalyticsWorkspaceId = (laWorkspaceName != '' && laWorkspaceRGName != '') ? logAnalyticsWorkspace.id : ''

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
    diagnosticWorkspaceId: logAnalyticsWorkspaceId
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
    diagnosticWorkspaceId: logAnalyticsWorkspaceId
  }
}

module storageAccount 'modules/storage-account.bicep' = {
  name: 'storageAccount-${uniqueString(resourceGroup().id)}'
  params: {
    deploy: deployStorageAccount
    location: location
    tags: tags
    storageAccountName: naming.outputs.resourcesNames.storageAccount
    storageAccountPrivateEndpointName: naming.outputs.resourcesNames.storageAccountPep
    hubVNetId: hubVNet.id
    hubVNetName: hubVNetName
    spokeVNetId: spokeVNet.id
    spokePrivateEndpointSubnetName: spokePrivateEndpointSubnetName
    skuName: storageAccountSkuName
    kind: storageAccountKind
    accessTier: storageAccountAccessTier
    allowSharedKeyAccess: storageAccountAllowSharedKeyAccess
    allowBlobPublicAccess: storageAccountAllowBlobPublicAccess
    enableHierarchicalNamespace: storageAccountEnableHierarchicalNamespace
    minimumTlsVersion: storageAccountMinimumTlsVersion
    queueNames: storageAccountQueueNames
  }
}


module redisCache 'modules/redis-cache.bicep' = {
  name: 'redisCache-${uniqueString(resourceGroup().id)}'
  params: {
    deploy: deployRedisCache
    location: location
    redisName: naming.outputs.resourcesNames.redisCache
    logAnalyticsWsId: logAnalyticsWorkspaceId
    keyVaultName: keyVault.outputs.keyVaultName
    spokeVNetId: spokeVNet.id
    hubVNetName: hubVNetName
    hubVNetId: hubVNet.id
    spokePrivateEndpointSubnetName: spokePrivateEndpointSubnetName
    redisCachePrivateEndpointName: naming.outputs.resourcesNames.redisCachePep
  }
}


module openAi 'modules/open-ai.module.bicep'= {
  name: take('openAiModule-Deployment', 64)
  params: {
    deploy: deployOpenAi
    name: naming.outputs.resourcesNames.openAiAccount
    deploymentName: naming.outputs.resourcesNames.openAiDeployment
    location: location
    tags: tags
    vnetHubResourceId: hubVNet.id
    logAnalyticsWsId: logAnalyticsWorkspaceId
    deployOpenAiGptModel: deployOpenAiGptModel
    spokeVNetId: spokeVNet.id
    hubVNetName: hubVNetName
    hubVNetId: hubVNet.id
    spokePrivateEndpointSubnetName: spokePrivateEndpointSubnetName
  }
}

module serviceBus 'modules/service-bus.bicep' = {
  name: 'serviceBus-${uniqueString(resourceGroup().id)}'
  params: {
    deploy: deployServiceBus
    location: location
    tags: tags
    serviceBusName: naming.outputs.resourcesNames.serviceBus
    skuName: serviceBusSkuName
    capacity: serviceBusCapacity
    queueNames: serviceBusQueueNames
    topicNames: serviceBusTopicNames
    zoneRedundant: serviceBusZoneRedundant
    publicNetworkAccess: serviceBusPublicNetworkAccess
    allowTrustedServicesAccess: serviceBusAllowTrustedServicesAccess
    hubVNetId: hubVNet.id
    hubVNetName: hubVNetName
    spokeVNetId: spokeVNet.id
    spokePrivateEndpointSubnetName: spokePrivateEndpointSubnetName
    serviceBusPrivateEndpointName: naming.outputs.resourcesNames.serviceBusPep
  workspaceId: logAnalyticsWorkspaceId
  }
}

module sqlDatabase 'modules/sql-database.bicep' = {
  name: 'sqlDatabase-${uniqueString(resourceGroup().id)}'
  params: {
    deploy: deploySqlDatabase
    location: location
    tags: tags
    sqlServerName: naming.outputs.resourcesNames.sqlServer
    sqlDatabaseName: sqlDatabaseName
    administratorLogin: sqlAdministratorLogin
    administratorLoginPassword: sqlAdministratorPassword
    skuName: sqlDatabaseSkuName
    skuTier: sqlDatabaseSkuTier
    skuCapacity: sqlDatabaseSkuCapacity
    skuFamily: sqlDatabaseSkuFamily
    maxSizeGb: sqlDatabaseMaxSizeGb
    zoneRedundant: sqlDatabaseZoneRedundant
    hubVNetId: hubVNet.id
    hubVNetName: hubVNetName
    spokeVNetId: spokeVNet.id
    spokePrivateEndpointSubnetName: spokePrivateEndpointSubnetName
    sqlPrivateEndpointName: naming.outputs.resourcesNames.sqlServerPep
  workspaceId: logAnalyticsWorkspaceId
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

@description('The resource ID of the Azure Storage account.')
output storageAccountId string = storageAccount.outputs.storageAccountId

@description('The name of the Azure Storage account.')
output storageAccountName string = storageAccount.outputs.storageAccountName

@description('Metadata for storage queues created by this deployment.')
output storageAccountQueues array = storageAccount.outputs.storageAccountQueueNames

@description('The secret name to retrieve the connection string from KeyVault')
output redisCacheSecretKey string = redisCache.outputs.redisCacheSecretKey

@description('The name of the Azure Open AI account name.')
output openAIAccountName string = openAi.outputs.name

@description('The Service Bus namespace name.')
output serviceBusNamespaceName string = serviceBus.outputs.serviceBusName

@description('The Service Bus namespace connection string.')
output serviceBusConnectionString string = serviceBus.outputs.serviceBusConnectionString

@description('Metadata for Service Bus queues created by this deployment.')
output serviceBusQueues array = serviceBus.outputs.serviceBusQueues

@description('Metadata for Service Bus topics created by this deployment.')
output serviceBusTopics array = serviceBus.outputs.serviceBusTopics

@description('The Azure SQL server name.')
output sqlServerName string = sqlDatabase.outputs.sqlServerName

@description('The Azure SQL server fully qualified domain name.')
output sqlServerFqdn string = sqlDatabase.outputs.sqlServerFqdn

@description('The Azure SQL database name.')
output sqlDatabaseName string = sqlDatabase.outputs.sqlDatabaseName

@description('The Azure SQL database resource ID.')
output sqlDatabaseId string = sqlDatabase.outputs.sqlDatabaseId
