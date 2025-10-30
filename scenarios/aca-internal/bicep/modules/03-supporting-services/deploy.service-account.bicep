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


@description('The name of the Azure Storage Account.')
param storageAccountName string

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

@description('Optional. Resource group name of the diagnostic log analytics workspace. If left empty, no diagnostics settings will be defined.')
param laWorkspaceRGName string = ''

@description('Optional. Resource name of the diagnostic log analytics workspace. If left empty, no diagnostics settings will be defined.')
param laWorkspaceName string = ''

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

module storageAccount 'modules/storage-account.bicep' = {
  name: 'storageAccount-${uniqueString(resourceGroup().id)}'
  params: {
    deploy: deployStorageAccount
    location: location
    tags: tags
    storageAccountName: storageAccountName
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


// ------------------
// OUTPUTS
// ------------------

@description('The resource ID of the Azure Storage account.')
output storageAccountId string = storageAccount.outputs.storageAccountId

@description('The name of the Azure Storage account.')
output storageAccountName string = storageAccount.outputs.storageAccountName

@description('Metadata for storage queues created by this deployment.')
output storageAccountQueues array = storageAccount.outputs.storageAccountQueueNames
