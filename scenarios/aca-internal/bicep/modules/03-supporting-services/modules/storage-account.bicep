targetScope = 'resourceGroup'

// ------------------
//    PARAMETERS
// ------------------

@description('Controls whether the storage account resources are deployed.')
param deploy bool = true

@description('The location where the resources will be created. This needs to be the same region as the spoke.')
param location string = resourceGroup().location

@description('Optional. The tags to be assigned to the created resources.')
param tags object = {}

@description('The name of the storage account to be created.')
param storageAccountName string

@description('The name prefix used for the private endpoints that will be associated with the storage account.')
param storageAccountPrivateEndpointName string

@description('The resource ID of the Hub Virtual Network.')
param hubVNetId string

@description('The resource name of the Hub Virtual Network.')
param hubVNetName string

@description('The resource ID of the VNet to which the private endpoints will be connected.')
param spokeVNetId string

@description('The name of the subnet in the VNet to which the private endpoints will be connected.')
param spokePrivateEndpointSubnetName string

@description('The SKU for the storage account.')
param skuName string = 'Standard_LRS'

@description('The kind of the storage account.')
@allowed([
  'StorageV2'
  'BlockBlobStorage'
  'FileStorage'
  'Storage'
])
param kind string = 'StorageV2'

@description('The access tier for the storage account. Set to an empty string for SKUs that do not support access tiers.')
param accessTier string = 'Hot'

@description('The minimum TLS version permitted for requests to the storage account.')
@allowed([
  'TLS1_0'
  'TLS1_1'
  'TLS1_2'
])
param minimumTlsVersion string = 'TLS1_2'

@description('Allow shared key authorization for the storage account.')
param allowSharedKeyAccess bool = true

@description('Allow public blob access for the storage account.')
param allowBlobPublicAccess bool = false

@description('Enable hierarchical namespace (Data Lake Storage Gen2). Only supported for StorageV2 accounts with compatible SKUs.')
param enableHierarchicalNamespace bool = false

@description('Provision Azure Storage queues for the workload.')
param queueNames array = []

@description('Force HTTPS for requests to the storage account.')
param supportsHttpsTrafficOnly bool = true

// ------------------
// VARIABLES
// ------------------

var blobPrivateEndpointName = take('${storageAccountPrivateEndpointName}-blob', 80)
var queuePrivateEndpointName = take('${storageAccountPrivateEndpointName}-queue', 80)
var fileSharePrivateEndpointName = take('${storageAccountPrivateEndpointName}-fileshare', 80)
var privateBlobDnsZoneName = 'privatelink.blob.${environment().suffixes.storage}'
var privateQueueDnsZoneName = 'privatelink.queue.${environment().suffixes.storage}'
var privateFileShareDnsZoneName = 'privatelink.file.${environment().suffixes.storage}'

var spokeVNetIdTokens = split(spokeVNetId, '/')
var spokeSubscriptionId = spokeVNetIdTokens[2]
var spokeResourceGroupName = spokeVNetIdTokens[4]
var spokeVNetName = spokeVNetIdTokens[8]

var spokeVNetLinks = concat(
  [
    {
      vnetName: spokeVNetName
      vnetId: vnetSpoke.id
      registrationEnabled: false
    }
  ],
  !empty(hubVNetName) ? [
    {
      vnetName: hubVNetName
      vnetId: hubVNetId
      registrationEnabled: false
    }
  ] : []
)

// ------------------
// RESOURCES
// ------------------

resource vnetSpoke 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  scope: resourceGroup(spokeSubscriptionId, spokeResourceGroupName)
  name: spokeVNetName
}

resource spokePrivateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  parent: vnetSpoke
  name: spokePrivateEndpointSubnetName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-04-01' = if (deploy) {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  kind: kind
  properties: {
    accessTier: accessTier != '' ? accessTier : null
    allowBlobPublicAccess: allowBlobPublicAccess
    allowSharedKeyAccess: allowSharedKeyAccess
    minimumTlsVersion: minimumTlsVersion
    supportsHttpsTrafficOnly: supportsHttpsTrafficOnly
    publicNetworkAccess: 'Disabled'
    isHnsEnabled: enableHierarchicalNamespace
  }
}

resource storageQueuesService 'Microsoft.Storage/storageAccounts/queueServices@2023-04-01' = if (deploy) {
  name: 'default'
  parent: storageAccount
}

resource storageQueues 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-04-01' = [for queueName in queueNames: if (deploy) {
  name: queueName
  parent: storageQueuesService
}]

module storageAccountBlobNetworking '../../../../../shared/bicep/network/private-networking.bicep' = if (deploy) {
  name: take('storageAccountBlobNetworking-${deployment().name}', 64)
  params: {
    location: location
    azServicePrivateDnsZoneName: privateBlobDnsZoneName
    azServiceId: storageAccount.id
    privateEndpointName: blobPrivateEndpointName
    privateEndpointSubResourceName: 'blob'
    virtualNetworkLinks: spokeVNetLinks
    subnetId: spokePrivateEndpointSubnet.id
    vnetHubResourceId: hubVNetId
  }
}

module storageAccountQueueNetworking '../../../../../shared/bicep/network/private-networking.bicep' = if (deploy) {
  name: take('storageAccountQueueNetworking-${deployment().name}', 64)
  params: {
    location: location
    azServicePrivateDnsZoneName: privateQueueDnsZoneName
    azServiceId: storageAccount.id
    privateEndpointName: queuePrivateEndpointName
    privateEndpointSubResourceName: 'queue'
    virtualNetworkLinks: spokeVNetLinks
    subnetId: spokePrivateEndpointSubnet.id
    vnetHubResourceId: hubVNetId
  }
}

module storageAccountFileShareNetworking '../../../../../shared/bicep/network/private-networking.bicep' = if (deploy) {
  name: take('storageAccountFileShareNetworking-${deployment().name}', 64)
  params: {
    location: location
    azServicePrivateDnsZoneName: privateFileShareDnsZoneName
    azServiceId: storageAccount.id
    privateEndpointName: fileSharePrivateEndpointName
    privateEndpointSubResourceName: 'file'
    virtualNetworkLinks: spokeVNetLinks
    subnetId: spokePrivateEndpointSubnet.id
    vnetHubResourceId: hubVNetId
  }
}

// ------------------
// OUTPUTS
// ------------------

@description('The resource ID of the storage account.')
output storageAccountId string = deploy ? storageAccount.id : ''

@description('The name of the storage account.')
output storageAccountName string = deploy ? storageAccount.name : ''

@description('Queue names created for the storage account.')
output storageAccountQueueNames array = queueNames
