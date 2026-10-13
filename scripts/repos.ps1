$resources = Join-Path $PSScriptRoot "./../resources"

$repositories = @(
    "https://github.com/AetherGases/aether-web-flow.git",
    "https://github.com/AetherGases/aether-docs.git",
    "https://github.com/AetherGases/aether-analytics.git",
    "https://github.com/AetherGases/aether-landing.git",
    "https://github.com/AetherGases/aether-web-administrative.git",
    "https://github.com/AetherGases/aether-core-api.git",
    "https://github.com/AetherGases/aether-mobile.git",
    "https://github.com/AetherGases/ms-aeko-hub.git",
    "https://github.com/AetherGases/aeko-sdk.git",
    "https://github.com/AetherGases/aether-user-experience",
    "https://github.com/AetherGases/aether-rpa.git",
    "https://github.com/AetherGases/aether-kong-gateway.git",
    "https://github.com/AetherGases/aether-ms-calculator.git",
    "https://github.com/AetherGases/aether-ms-inventory.git",
    "https://github.com/AetherGases/aether-ms-auth.git",
    "https://github.com/AetherGases/aether-ms-cloudinary.git"
)

if (-not (Test-Path $resources)) {
    New-Item -ItemType Directory -Path $resources -Force | Out-Null
}


Write-Host "Iniciando clonagem"

foreach ($repository in $repositories) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($repository)
    $destination = Join-Path $resources $name
    
    if (Test-Path $destination) {
        Write-Host "$name ja existe, pulando..."
        continue
    }

    git clone $repository $destination
}

Write-Host "Clonagem concluida"