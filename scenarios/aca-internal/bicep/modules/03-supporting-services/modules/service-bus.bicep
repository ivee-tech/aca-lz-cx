targetScope = 'resourceGroup'

@description('The location where the resources will be created.')
param location string = resourceGroup().location

@description('Optional. The tags to be assigned to the created resources.')
param tags object = {}

@description('The name of the Service Bus namespace.')
param serviceBusName string

@description('Controls whether the Service Bus namespace resources are deployed.')
param deploy bool = true

@description('The SKU for the Service Bus namespace.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param skuName string = 'Premium'

@description('Messaging units for Premium tier namespaces.')
param capacity int = 1

@description('Queue names to create in the namespace.')
param queueNames array = []

@description('Topic names to create in the namespace.')
param topicNames array = []

@description('Enable availability zone redundancy (Premium SKU only).')
param zoneRedundant bool = true

@description('Allow access from the public internet.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Disabled'

@description('Allow Azure trusted services access when public network access is disabled.')
param allowTrustedServicesAccess bool = true

@description('The resource ID of the hub virtual network.')
param hubVNetId string

@description('The name of the hub virtual network. Leave empty when no hub vnet is linked.')
param hubVNetName string = ''

@description('The resource ID of the spoke virtual network.')
param spokeVNetId string

@description('The subnet name in the spoke virtual network for the private endpoint.')
param spokePrivateEndpointSubnetName string

@description('The name of the private endpoint created for Service Bus.')
param serviceBusPrivateEndpointName string

@description('Resource ID of the Log Analytics workspace for diagnostics. Leave empty to skip diagnostics.')
param workspaceId string = ''

var privateDnsZoneName = 'privatelink.servicebus.windows.net'
var serviceBusNamespaceResourceName = 'namespace'

var spokeVNetTokens = split(spokeVNetId, '/')
var spokeSubscriptionId = spokeVNetTokens[2]
var spokeResourceGroupName = spokeVNetTokens[4]
var spokeVNetName = spokeVNetTokens[8]

var virtualNetworkLinks = concat(
  [
    {
      vnetName: spokeVNetName
      vnetId: spokeVNet.id
      registrationEnabled: false
    }
  ],
  (!empty(hubVNetName) && !empty(hubVNetId)) ? [
    {
      vnetName: hubVNetName
      vnetId: hubVNetId
      registrationEnabled: false
    }
  ] : []
)

resource spokeVNet 'Microsoft.Network/virtualNetworks@2022-07-01' existing = {
  scope: resourceGroup(spokeSubscriptionId, spokeResourceGroupName)
  name: spokeVNetName
}

resource spokePrivateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2022-07-01' existing = {
  parent: spokeVNet
  name: spokePrivateEndpointSubnetName
}

module serviceBusNamespace '../../../../../shared/bicep/service-bus.bicep' = if (deploy) {
  name: 'serviceBusNamespace-${uniqueString(serviceBusName)}'
  params: {
    name: serviceBusName
    location: location
    tags: tags
    skuName: skuName
    capacity: capacity
    queueNames: queueNames
    topicNames: topicNames
    zoneRedundant: zoneRedundant
    publicNetworkAccess: publicNetworkAccess
    allowTrustedServicesAccess: allowTrustedServicesAccess
    workspaceId: workspaceId
  }
}

module serviceBusNetworking '../../../../../shared/bicep/network/private-networking.bicep' = if (deploy) {
  name: 'serviceBusNetwork-${uniqueString(serviceBusName)}'
  params: {
    location: location
    azServicePrivateDnsZoneName: privateDnsZoneName
    azServiceId: serviceBusNamespace!.outputs.id
    privateEndpointName: serviceBusPrivateEndpointName
    privateEndpointSubResourceName: serviceBusNamespaceResourceName
    virtualNetworkLinks: virtualNetworkLinks
    subnetId: spokePrivateEndpointSubnet.id
    vnetHubResourceId: hubVNetId
  }
}

output serviceBusId string = deploy ? serviceBusNamespace!.outputs.id : ''
output serviceBusName string = deploy ? serviceBusNamespace!.outputs.name : ''
output serviceBusConnectionString string = deploy ? serviceBusNamespace!.outputs.connectionString : ''
output serviceBusQueues array = deploy ? serviceBusNamespace!.outputs.queues : []
output serviceBusTopics array = deploy ? serviceBusNamespace!.outputs.topics : []
