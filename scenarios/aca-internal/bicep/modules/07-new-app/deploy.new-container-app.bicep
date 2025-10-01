targetScope = 'resourceGroup'

// ------------------
//    PARAMETERS
// ------------------

@description('The location where the resources will be created.')
param location string = resourceGroup().location

@description('Optional. The tags to be assigned to the created resources.')
param tags object = {}

// Container App Parameters
@description('The name of the new container app.')
@minLength(2)
@maxLength(32)
param containerAppName string

@description('The container image for the new app.')
param containerImage string

@description('The target port for the container app.')
param targetPort int = 80

@description('The CPU allocation for the container.')
param cpuAllocation string = '0.25'

@description('The memory allocation for the container.')
param memoryAllocation string = '0.5Gi'

@description('Minimum number of replicas.')
param minReplicas int = 1

@description('Maximum number of replicas.')
param maxReplicas int = 10

@description('The existing Container Apps environment name.')
param containerAppsEnvironmentName string

@description('The name of the existing user-assigned managed identity for ACR access.')
param acrUmiName string

@description('The name of the existing container registry.')
param containerRegistryName string

@description('Optional environment variables for the container.')
param environmentVariables array = []

@description('Optional secrets for the container.')
param secrets array = []

// ------------------
// RESOURCES
// ------------------

@description('Reference to the existing Container Apps environment.')
resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2023-05-01' existing = {
  name: containerAppsEnvironmentName
}

@description('Reference to the existing user-assigned managed identity for ACR.')
resource acrUmi 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: acrUmiName
}

@description('Reference to the existing container registry.')
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: containerRegistryName
}

@description('Deploy the new Container App.')
resource newContainerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: containerAppName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${acrUmi.id}': {}
    }
  }
  properties: {
    configuration: {
      activeRevisionsMode: 'single'
      ingress: {
        allowInsecure: false
        external: true
        targetPort: targetPort
        transport: 'auto'
      }
      registries: [
        {
          server: containerRegistry.properties.loginServer
          identity: acrUmi.id
        }
      ]
      secrets: secrets
    }
    environmentId: containerAppsEnvironment.id
    workloadProfileName: 'Consumption'
    template: {
      containers: [
        {
          name: containerAppName
          image: containerImage
          resources: {
            cpu: json(cpuAllocation)
            memory: memoryAllocation
          }
          env: environmentVariables
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
      volumes: []
    }
  }
}

// ------------------
// OUTPUTS
// ------------------

@description('The FQDN of the new Container App.')
output containerAppFqdn string = newContainerApp.properties.configuration.ingress.fqdn

@description('The name of the new Container App.')
output containerAppName string = newContainerApp.name

@description('The resource ID of the new Container App.')
output containerAppId string = newContainerApp.id

@description('Configuration details for adding to Application Gateway backend pool.')
output applicationGatewayBackendConfig object = {
  backendPoolName: '${containerAppName}Backend'
  backendFqdn: newContainerApp.properties.configuration.ingress.fqdn
  targetPort: targetPort
  healthProbePath: '/'
  containerAppName: containerAppName
}
