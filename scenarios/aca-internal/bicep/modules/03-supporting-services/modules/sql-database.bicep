targetScope = 'resourceGroup'

@description('The location where the resources will be created.')
param location string = resourceGroup().location

@description('Optional. The tags to be assigned to the created resources.')
param tags object = {}

@description('The name of the Azure SQL logical server.')
param sqlServerName string

@description('The name of the Azure SQL database.')
param sqlDatabaseName string

@description('Controls whether the Azure SQL resources are deployed.')
param deploy bool = true

@description('Administrator login for the Azure SQL server.')
param administratorLogin string = 'sqladminuser'

@secure()
@description('Administrator password for the Azure SQL server.')
param administratorLoginPassword string

@description('The SKU name for the Azure SQL database (for example, GP_Gen5_2 or S0).')
param skuName string = 'GP_Gen5_2'

@description('The SKU tier for the Azure SQL database.')
param skuTier string = 'GeneralPurpose'

@description('The compute capacity for the Azure SQL database SKU. Leave 0 to omit.')
param skuCapacity int = 0

@description('The compute family for the Azure SQL database SKU. Leave empty to omit.')
param skuFamily string = ''

@description('The maximum database size in GB.')
param maxSizeGb int = 32

@description('Database collation.')
param collation string = 'SQL_Latin1_General_CP1_CI_AS'

@description('Configure zone redundancy for the database (supported tiers only).')
param zoneRedundant bool = false

@description('The resource ID of the hub virtual network.')
param hubVNetId string

@description('The name of the hub virtual network. Leave empty when no hub vnet is linked.')
param hubVNetName string = ''

@description('The resource ID of the spoke virtual network.')
param spokeVNetId string

@description('The subnet name in the spoke virtual network for the private endpoint.')
param spokePrivateEndpointSubnetName string

@description('The name of the private endpoint created for the SQL server.')
param sqlPrivateEndpointName string

@description('Resource ID of the Log Analytics workspace for diagnostics. Leave empty to skip diagnostics.')
param workspaceId string = ''

var sqlHostnameSuffix = environment().suffixes.sqlServerHostname
var privateDnsZoneName = startsWith(sqlHostnameSuffix, '.') ? 'privatelink${sqlHostnameSuffix}' : 'privatelink.${sqlHostnameSuffix}'
var privateEndpointSubResourceName = 'sqlServer'
var maxSizeBytes = maxSizeGb * 1024 * 1024 * 1024

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

var diagnosticLogCategories = [
  'SQLInsights'
  'AutomaticTuning'
  'QueryStoreRuntimeStatistics'
  'QueryStoreWaitStatistics'
  'Errors'
  'DatabaseWaitStatistics'
  'Timeouts'
  'Blocks'
  'Deadlocks'
]

var diagnosticMetricCategories = [
  'AllMetrics'
]

var diagnosticLogs = [for category in diagnosticLogCategories: {
  category: category
  enabled: true
  retentionPolicy: {
    enabled: false
    days: 0
  }
}]

var diagnosticMetrics = [for category in diagnosticMetricCategories: {
  category: category
  enabled: true
  retentionPolicy: {
    enabled: false
    days: 0
  }
}]

var skuBase = {
  name: skuName
  tier: skuTier
}

var skuCapacitySetting = skuCapacity > 0 ? {
  capacity: skuCapacity
} : {}

var skuFamilySetting = !empty(skuFamily) ? {
  family: skuFamily
} : {}

var databasePropertiesBase = {
  collation: collation
  maxSizeBytes: maxSizeBytes
}

var databaseZoneRedundantSetting = zoneRedundant ? {
  zoneRedundant: true
} : {}

resource spokeVNet 'Microsoft.Network/virtualNetworks@2022-07-01' existing = {
  scope: resourceGroup(spokeSubscriptionId, spokeResourceGroupName)
  name: spokeVNetName
}

resource spokePrivateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2022-07-01' existing = {
  parent: spokeVNet
  name: spokePrivateEndpointSubnetName
}

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = if (deploy) {
  name: sqlServerName
  location: location
  tags: tags
  properties: {
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    version: '12.0'
    publicNetworkAccess: 'Disabled'
    minimalTlsVersion: '1.2'
  }
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01-preview' = if (deploy) {
  parent: sqlServer
  name: sqlDatabaseName
  location: location
  sku: union(union(skuBase, skuCapacitySetting), skuFamilySetting)
  properties: union(databasePropertiesBase, databaseZoneRedundantSetting)
}

resource sqlDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (deploy && !empty(workspaceId)) {
  name: 'diagnosticSettings'
  scope: sqlDatabase
  properties: {
    workspaceId: workspaceId
    logs: diagnosticLogs
    metrics: diagnosticMetrics
  }
}

module sqlNetworking '../../../../../shared/bicep/network/private-networking.bicep' = if (deploy) {
  name: 'sqlNetworking-${uniqueString(resourceGroup().id, sqlServerName)}'
  params: {
    location: location
    azServicePrivateDnsZoneName: privateDnsZoneName
    azServiceId: sqlServer!.id
    privateEndpointName: sqlPrivateEndpointName
    privateEndpointSubResourceName: privateEndpointSubResourceName
    virtualNetworkLinks: virtualNetworkLinks
    subnetId: spokePrivateEndpointSubnet.id
    vnetHubResourceId: hubVNetId
  }
}

output sqlServerId string = deploy ? sqlServer!.id : ''
output sqlServerName string = deploy ? sqlServer!.name : ''
output sqlServerFqdn string = deploy ? sqlServer!.properties.fullyQualifiedDomainName : ''
output sqlDatabaseId string = deploy ? sqlDatabase!.id : ''
output sqlDatabaseName string = deploy ? sqlDatabase!.name : ''
