param(
    [Parameter(Mandatory=$true)] [string]$ResourceGroup,
    [Parameter(Mandatory=$true)] [string]$GatewayName,
    [Parameter(Mandatory=$true)] [string]$ContainerAppName,
    [Parameter(Mandatory=$true)] [string]$ApiPath,
    [int]$Priority = 90
)

<#
Minimal script to add path-based routing for a Container App on an existing Azure Application Gateway.
Adds (idempotently): backend pool, probe, HTTP settings, url-path-map (with one path rule), and a request routing rule.
It does NOT modify or delete existing default/basic rules; it simply introduces a higher (or specified) priority rule that
matches the given ApiPath.

Assumptions / Notes:
 - Application Gateway already exists and has at least one HTTP listener (first one is reused).
 - Container App has ingress enabled; we read its public FQDN.
 - ApiPath should include wildcard if desired (e.g. /api/v2/*). A base variant (/api/v2) is auto-added for convenience.
 - Standard v2 / WAF v2 SKU supports rule priorities. Ensure Priority value doesn’t collide with existing rules.
 - Script is intentionally minimal: no dry-run, rollback, or complex safety nets. Re-run safe (idempotent resource checks).
 - Requires Azure CLI logged in and correct subscription selected.

Exit Codes:
 0 success
 1 unrecoverable error (writes message to stderr)
#>

function Fail($msg) { Write-Error $msg; exit 1 }

Write-Host "[api-route] Retrieving Container App FQDN..." -ForegroundColor Cyan
$fqdn = az containerapp show `
  --name $ContainerAppName `
  --resource-group $ResourceGroup `
  --query "properties.configuration.ingress.fqdn" -o tsv 2>$null
if (-not $fqdn) { Fail "Container App '$ContainerAppName' FQDN not found." }
Write-Host "[api-route] Container App FQDN: $fqdn" -ForegroundColor Green

# Name conventions (short & deterministic)
$backendPoolName      = "${ContainerAppName}Pool"
$httpSettingsName     = "${ContainerAppName}Http"
$probeName            = "${ContainerAppName}Probe"
$urlPathMapName       = "apiPathMap"          # reuse for multiple APIs if desired
$pathRuleName         = ($ApiPath -replace '[^a-zA-Z0-9]', '') + 'Rule'
if ($pathRuleName.Length -gt 32) { $pathRuleName = $pathRuleName.Substring(0,32) }
$routingRuleName      = "apiRoutingRule"      # single routing rule hosting the path map

# Normalize paths list (ensure both /api/v2 and /api/v2/* if user supplied wildcard form)
$paths = New-Object System.Collections.Generic.List[string]
function AddPath([string]$p){ if (-not $p.StartsWith('/')) { $p = "/$p" }; if ($paths -notcontains $p) { $paths.Add($p) } }
if ($ApiPath.Contains('*')) {
  $wild = $ApiPath
  AddPath $wild
  $base = $wild -replace '\*.*$','' -replace '/$',''
  if ($base -and $base -ne '/') { AddPath $base }
} else {
  AddPath $ApiPath
}
Write-Host "[api-route] Paths => $($paths -join ', ')" -ForegroundColor Yellow

Write-Host "[api-route] Fetching gateway state (once)..." -ForegroundColor Cyan
$gwJson = az network application-gateway show -g $ResourceGroup -n $GatewayName -o json 2>$null
if (-not $gwJson) { Fail "Application Gateway '$GatewayName' not found in RG '$ResourceGroup'." }
$gw = $gwJson | ConvertFrom-Json

# Helper to test existence
function ExistsIn($collection, $name){ return $collection | Where-Object { $_.name -eq $name } | ForEach-Object { $true } | Select-Object -First 1 }

# 1. Backend Pool
if (-not (ExistsIn $gw.backendAddressPools $backendPoolName)) {
  Write-Host "[api-route] Creating backend pool $backendPoolName" -ForegroundColor Cyan
  az network application-gateway address-pool create -g $ResourceGroup --gateway-name $GatewayName -n $backendPoolName --fqdn $fqdn | Out-Null
} else { Write-Host "[api-route] Backend pool exists" -ForegroundColor DarkGray }

# 2. Probe (explicit host & simple root path)
if (-not (ExistsIn $gw.probes $probeName)) {
  Write-Host "[api-route] Creating probe $probeName" -ForegroundColor Cyan
  az network application-gateway probe create -g $ResourceGroup --gateway-name $GatewayName -n $probeName `
    --protocol Https --host $fqdn --path / --interval 30 --timeout 30 --threshold 3 | Out-Null
} else { Write-Host "[api-route] Probe exists" -ForegroundColor DarkGray }

# 3. HTTP Settings (HTTPS, explicit host header for SNI, probe wired)
if (-not (ExistsIn $gw.backendHttpSettingsCollection $httpSettingsName)) {
  Write-Host "[api-route] Creating HTTP settings $httpSettingsName" -ForegroundColor Cyan
  az network application-gateway http-settings create -g $ResourceGroup --gateway-name $GatewayName -n $httpSettingsName `
    --port 443 --protocol Https --host-name $fqdn --probe $probeName --timeout 30 | Out-Null
} else { Write-Host "[api-route] HTTP settings exist" -ForegroundColor DarkGray }

# Refresh GW for subsequent existence checks
$gwJson = az network application-gateway show -g $ResourceGroup -n $GatewayName -o json
$gw = $gwJson | ConvertFrom-Json

# 4. URL Path Map & Path Rule
$pathMap = $gw.urlPathMaps | Where-Object { $_.name -eq $urlPathMapName }
if (-not $pathMap) {
  Write-Host "[api-route] Creating url-path-map $urlPathMapName with rule $pathRuleName" -ForegroundColor Cyan
  az network application-gateway url-path-map create -g $ResourceGroup --gateway-name $GatewayName -n $urlPathMapName `
    --paths $paths --address-pool $backendPoolName --http-settings $httpSettingsName --rule-name $pathRuleName | Out-Null
} else {
  # Ensure each desired path is covered by some path rule; if missing, add/extend one rule (create new path rule if needed)
  $existingPaths = @($pathMap.pathRules.path -join ';' -split ';')
  $missing = $paths | Where-Object { $existingPaths -notcontains $_ }
  if ($missing.Count -gt 0) {
    if ($pathMap.pathRules.Count -eq 1 -and $pathMap.pathRules[0].paths.Count -lt 10) {
      Write-Host "[api-route] Updating existing rule $($pathMap.pathRules[0].name) with paths: $($missing -join ',')" -ForegroundColor Cyan
      az network application-gateway url-path-map rule update -g $ResourceGroup --gateway-name $GatewayName `
        --path-map-name $urlPathMapName -n $pathMap.pathRules[0].name --paths ($existingPaths + $missing) `
        --address-pool $backendPoolName --http-settings $httpSettingsName | Out-Null
    } else {
      Write-Host "[api-route] Creating additional path rule $pathRuleName for missing paths" -ForegroundColor Cyan
      az network application-gateway url-path-map rule create -g $ResourceGroup --gateway-name $GatewayName `
        --path-map-name $urlPathMapName -n $pathRuleName --paths $missing `
        --address-pool $backendPoolName --http-settings $httpSettingsName | Out-Null
    }
  } else {
    Write-Host "[api-route] All paths already present in url-path-map" -ForegroundColor DarkGray
  }
}

# 5. Request Routing Rule (PathBasedRouting) referencing the path map
$gwJson = az network application-gateway show -g $ResourceGroup -n $GatewayName -o json
$gw = $gwJson | ConvertFrom-Json
$listenerName = $gw.httpListeners[0].name
$rule = $gw.requestRoutingRules | Where-Object { $_.name -eq $routingRuleName }
if (-not $rule) {
  Write-Host "[api-route] Creating request routing rule $routingRuleName (priority $Priority)" -ForegroundColor Cyan
  az network application-gateway rule create -g $ResourceGroup --gateway-name $GatewayName -n $routingRuleName `
    --rule-type PathBasedRouting --http-listener $listenerName --url-path-map $urlPathMapName --priority $Priority | Out-Null
} else {
  Write-Host "[api-route] Rule exists; ensuring it points to url-path-map $urlPathMapName" -ForegroundColor Cyan
  az network application-gateway rule update -g $ResourceGroup --gateway-name $GatewayName -n $routingRuleName `
    --rule-type PathBasedRouting --http-listener $listenerName --url-path-map $urlPathMapName --priority $Priority | Out-Null
}

Write-Host "[api-route] Done. Validate with: az network application-gateway show -g $ResourceGroup -n $GatewayName --query 'requestRoutingRules[].{name:name,priority:priority,ruleType:ruleType}' -o table" -ForegroundColor Green
exit 0
