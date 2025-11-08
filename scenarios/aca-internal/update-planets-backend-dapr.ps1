[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $ResourceGroup,
    [Parameter(Mandatory = $true)] [string] $ContainerAppName,
    [Parameter(Mandatory = $true)] [string] $EnvironmentName,
    [Parameter(Mandatory = $true)] [string] $NasaApiKey,
    [string] $DaprAppId = "planets-backend",
    [string] $ComponentName = "nasa-neo-feed",
    [string] $ComponentFile = "../dapr/components/nasa-neo-feed.yaml"
)

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI (az) is required. Install it before running this script."
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$componentFullPath = Join-Path -Path $scriptRoot -ChildPath $ComponentFile
$resolvedComponentPath = Resolve-Path -Path $componentFullPath -ErrorAction SilentlyContinue
if (-not $resolvedComponentPath) {
        throw "Dapr component file '$componentFullPath' was not found."
}

Write-Host "Applying Dapr component '$ComponentName' to environment '$EnvironmentName' in resource group '$ResourceGroup'..."
az containerapp env dapr-component set `
    --resource-group $ResourceGroup `
    --name $EnvironmentName `
    --dapr-component-name $ComponentName `
    --yaml $resolvedComponentPath | Out-Null

Write-Host "Enabling Dapr for container app '$ContainerAppName' (app id '$DaprAppId')..."
az containerapp dapr enable `
    --resource-group $ResourceGroup `
    --name $ContainerAppName `
    --dapr-app-id $DaprAppId `
    --dapr-app-port 8080 `
    --dapr-app-protocol http
#    --set-env-vars "NASA__NeoFeed__ApiKey=$NasaApiKey" "NASA__NeoFeed__ComponentName=$ComponentName" | Out-Null

Write-Host "Updated container app '$ContainerAppName' with Dapr configuration."