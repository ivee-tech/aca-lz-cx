$LOCATION = 'australiaeast'

# deploy hub (one-off, usually already exists)
$templateFile = './bicep/modules/01-hub/deploy.hub.bicep'
$parametersFile = './bicep/modules/01-hub/deploy.hub.parameters.jsonc'

az deployment sub create `
    -n acalza01-hub `
    -l $LOCATION `
    -f $templateFile `
    -p $parametersFile

# deploy spoke
$rgHubName = 'rg-nasc-hub-dev-001'
$templateFile = './bicep/modules/02-spoke/deploy.spoke.bicep'
$parametersFile = './bicep/modules/02-spoke/deploy.spoke.parameters.jsonc'
$fwName = 'azfw-nasc-dev-aue'
$vmAdminPassword = '***'
$FW_IP_ADDRESS = $(az network firewall show --name $fwName --resource-group $rgHubName --query "ipConfigurations[0].privateIpAddress" --output tsv)

<#
# list publishers 
az vm image list-publishers --location $LOCATION
# list offers for a publisher
az vm image list-offers --location $LOCATION --publisher Canonical
# list skus for an offer
az vm image list-skus --location $LOCATION --publisher Canonical --offer UbuntuServer
#>

az deployment sub create `
    -n acalza01-spoke `
    -l $LOCATION `
    -f $templateFile `
    -p $parametersFile `
    --parameters vmAdminPassword=$vmAdminPassword `
    --parameters networkApplianceIpAddress=$FW_IP_ADDRESS

# deploy supporting services
$templateFile = './bicep/modules/03-supporting-services/deploy.supporting-services.bicep'
$parametersFile = './bicep/modules/03-supporting-services/deploy.supporting-services.parameters.jsonc'
$rgSpokeName = 'rg-nasc-spoke-dev-001'

$sqlAdministratorPassword = '***'
$supportingServicesOutputs = az deployment group create `
    -n acalza01-supporting-services `
    -g $rgSpokeName `
    -f $templateFile `
    -p $parametersFile `
    -p sqlAdministratorPassword=$sqlAdministratorPassword 

# deploy SA
$templateFile = './bicep/modules/03-supporting-services/deploy.service-account.bicep'
$parametersFile = './bicep/modules/03-supporting-services/deploy.service-account.parameters.jsonc'
$rgSpokeName = 'rg-nasc-spoke-dev-001'
az deployment group create `
    -n acalza01-service-account `
    -g $rgSpokeName `
    -f $templateFile `
    -p $parametersFile


# deploy ACA environment
$templateFile = './bicep/modules/04-container-apps-environment/deploy.aca-environment.bicep'
$parametersFile = './bicep/modules/04-container-apps-environment/deploy.aca-environment.parameters.jsonc'
$rgSpokeName = 'rg-nasc-spoke-dev-001'

az deployment group create `
    -n acalza01-appplat `
    -g $rgSpokeName `
    -f $templateFile `
    -p $parametersFile

# deploy sample app
$templateFile = './bicep/modules/05-hello-world-sample-app/deploy.hello-world.bicep'
$parametersFile = './bicep/modules/05-hello-world-sample-app/deploy.hello-world.parameters.jsonc'
$rgSpokeName = 'rg-nasc-spoke-dev-001'

az deployment group create `
    -n acalza01-helloworld `
    -g $rgSpokeName `
    -f $templateFile `
    -p $parametersFile

# deploy front door
$vnetSpokeName = 'vnet-nasc-dev-aue-spoke'
$subnetName = 'snet-fd'
az network vnet subnet update `
  --resource-group $rgSpokeName `
  --vnet-name $vnetSpokeName `
  --name $subnetName `
  --disable-private-link-service-network-policies true

$templateFile = './bicep/modules/06-front-door/deploy.front-door.bicep'
$parametersFile = './bicep/modules/06-front-door/deploy.front-door.parameters.jsonc'
$rgSpokeName = 'rg-nasc-spoke-dev-001'

az deployment group create `
    -n acalza01-frontdoor `
    -g $rgSpokeName `
    -f $templateFile `
    -p $parametersFile

# deploy application gateway
$templateFile = './bicep/modules/06-application-gateway/deploy.app-gateway.bicep'
$parametersFile = './bicep/modules/06-application-gateway/deploy.app-gateway.parameters.jsonc'
$rgSpokeName = 'rg-nasc-spoke-dev-001'
$caName = 'ca-simple-hello'

# get the FQDN for the hello world app
$FQDN_HELLOWORLD_ACA = $(az containerapp show --name $caName --resource-group $rgSpokeName --query "properties.configuration.ingress.fqdn" --output tsv)

az deployment group create `
    -n acalza01-appgw `
    -g $rgSpokeName `
    -f $templateFile `
    -p $parametersFile `
    -p applicationGatewayPrimaryBackendEndFqdn=${FQDN_HELLOWORLD_ACA}
# get the App Gateway public IP
$pipName = 'pip-agw-nasc-dev-aue'
$AGW_IP_ADDRESS = $(az network public-ip show --name $pipName -g $rgSpokeName --query "ipAddress" --output tsv)
Write-Host "Application Gateway Public IP: $AGW_IP_ADDRESS"


# deploy new app into ACA environment with App Gateway integration
$rgSpokeName = 'rg-nasc-spoke-dev-001'
$templateFile = './bicep/modules/07-new-app/deploy.new-container-app.bicep'
$parametersFile = './bicep/modules/07-new-app/deploy.new-container-app.parameters.jsonc'

az deployment group create `
  -g $rgSpokeName `
  -f $templateFile `
  -p $parametersFile `
  --query "properties.outputs" `
  --output json 

# Update Application Gateway to route /api/v2/* to the new container app
$rgSpokeName = 'rg-nasc-spoke-dev-001'
$caName = 'ca-nasc-api1'
$agwName = 'agw-nasc-dev-aue'
$fqdn = $(az containerapp show --name $caName -g $rgSpokeName --query "properties.configuration.ingress.fqdn" --output tsv)
# $fqdn = 'ca-nasc-api1.calmdesert-2ea64a90.australiaeast.azurecontainerapps.io'

## Minimal API route addition (replaces previous complex routing scripts)
& .\add-api-route.ps1 -ResourceGroup $rgSpokeName -GatewayName $agwName -ContainerAppName $caName -ApiPath '/api/v2/*' -Priority 90


# disable export to allow temporary public access to the ACR
$rgSpokeName = 'rg-nasc-spoke-dev-001'
$acrName = 'crnascmieoldevaue'
$v = 'enabled'
az resource update --resource-group $rgSpokeName `
    --name $acrName `
    --resource-type "Microsoft.ContainerRegistry/registries" `
    --api-version "2021-06-01-preview" `
    --set "properties.policies.exportPolicy.status=$v" `
    --set "properties.publicNetworkAccess=$v"  

# deploy planets backend app
$rgSpokeName = 'rg-nasc-spoke-dev-001'
$templateFile = './bicep/modules/07-new-app/deploy.new-container-app.bicep'
$parametersFile = './bicep/modules/07-new-app/deploy.planets-backend.parameters.jsonc'
az deployment group create `
  --resource-group $rgSpokeName `
  --template-file $templateFile `
  --parameters $parametersFile

# deploy planets frontend app
$rgSpokeName = 'rg-nasc-spoke-dev-001'
$templateFile = './bicep/modules/07-new-app/deploy.new-container-app.bicep'
$parametersFile = './bicep/modules/07-new-app/deploy.planets-frontend.parameters.jsonc'
az deployment group create `
  --resource-group $rgSpokeName `
  --template-file $templateFile `
  --parameters $parametersFile

# grant Service Bus permissions to managed identity
$rgSpokeName = 'rg-nasc-spoke-dev-001'
$managedIdentityName = 'id-crnascmieoldevaue-AcrPull'
$serviceBusNamespaceName = 'sb-nasc-mieol-dev-aue'
$serviceBusQueueName = 'rocket-messages'

$managedIdentity = az identity show `
    --name $managedIdentityName `
    --resource-group $rgSpokeName `
    --output json | ConvertFrom-Json
$principalId = $managedIdentity.principalId
if (-not $principalId) {
    throw "Managed identity '$managedIdentityName' not found in resource group '$rgSpokeName'."
}

$serviceBusQueueId = az servicebus queue show `
    --resource-group $rgSpokeName `
    --namespace-name $serviceBusNamespaceName `
    --name $serviceBusQueueName `
    --query id `
    --output tsv

$roles = @('Azure Service Bus Data Sender', 'Azure Service Bus Data Receiver')
foreach ($role in $roles) {
    Write-Host "Assigning role '$role' on queue '$serviceBusQueueName' to managed identity '$managedIdentityName'."
    az role assignment create `
        --assignee $principalId `
        --role $role `
        --scope $serviceBusQueueId `
        --output none
}
Write-Host "Service Bus role assignments completed for managed identity '$managedIdentityName'."


# deploy the Dapr components to Azure Container Apps
$rgSpokeName = 'rg-nasc-spoke-dev-001'
$envName = 'cae-nasc-dev-aue'
$appName = 'ca-nasc-planets-api'
$daprAppId = 'planets-backend'
$componentName = 'nasa-neo-feed'
$componentFile = '../../planets-app/planets-backend/dapr/components/nasa-neo-feed.yaml'
$nasaApiKey = $env:NASA_API_KEY
.\update-planets-backend-dapr.ps1 -ResourceGroup $rgSpokeName `
    -ContainerAppName $appName `
    -EnvironmentName $envName `
    -NasaApiKey $nasaApiKey `
    -DaprAppId $daprAppId `
    -ComponentName $componentName `
    -ComponentFile $componentFile
