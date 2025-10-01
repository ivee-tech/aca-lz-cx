targetScope = 'resourceGroup'

// ------------------
//    PARAMETERS
// ------------------

@description('The location where the resources will be created.')
param location string = resourceGroup().location

@description('Optional. The tags to be assigned to the created resources.')
param tags object = {}

@description('The name of the private link service to create.')
param privateLinkServiceName string

@description('SubnetId used to configure private link service.')
param privateLinkSubnetId string

@description('Azure Container Apps Environment Subscription Id')
param containerAppsEnvironmentSubscriptionId string

@description('Azure Container Apps Environment name')
param containerAppsEnvironmentName string

@description('Azure Container Apps Environment resource group name')
param containerAppsEnvironmentResourceGroupName string

// ------------------
// VARIABLES
// ------------------

// => Resolve container apps environment managed resource group name to get the frontend Ip configuration
// The infrastructure resource group follows the pattern: ME_{resourceGroupName}_{containerAppsEnvironmentName}
var containerAppsManagedResourceGroup = take('ME_${containerAppsEnvironmentResourceGroupName}_${containerAppsEnvironmentName}', 63)

// ------------------
// RESOURCES
// ------------------

resource loadBalancer 'Microsoft.Network/loadBalancers@2021-05-01' existing = {
  name: 'capp-svc-lb' // 'kubernetes-internal'
  scope: resourceGroup(containerAppsEnvironmentSubscriptionId, containerAppsManagedResourceGroup)
}

resource privateLinkService 'Microsoft.Network/privateLinkServices@2022-01-01' = {
  name: privateLinkServiceName
  location: location
  tags: tags
  properties: {
    loadBalancerFrontendIpConfigurations: [
      {
        id: loadBalancer.properties.frontendIPConfigurations[0].id
      }
    ]
    ipConfigurations: [
      {
        name: 'snet-provider-default-1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: privateLinkSubnetId
          }
          primary: true
          privateIPAddressVersion: 'IPv4'
        }
      }
    ]
  }
}

output privateLinkServiceId string = privateLinkService.id

output privateEndpointConnections array = privateLinkService.properties.privateEndpointConnections
