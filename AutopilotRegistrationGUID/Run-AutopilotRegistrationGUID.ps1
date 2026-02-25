#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Launcher script for the Autopilot Registration GUID Tool
    
.DESCRIPTION
    This script provides a convenient way to launch the main tool script
    with proper error handling and user feedback
#>

param(
    [switch]$NoExit
)

# Determine script directory
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path

# Path to the main tool script
$toolScript = Join-Path -Path $scriptDirectory -ChildPath "AutopilotRegistrationGUID.ps1"

# Check if the main script exists
if (-not (Test-Path -Path $toolScript)) {
    Write-Host "Error: AutopilotRegistrationGUID.ps1 not found in $scriptDirectory" -ForegroundColor Red
    Write-Host "Please ensure the script file is in the same directory as this launcher." -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit
}

# Display launch information
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "    Autopilot Registration GUID Tool" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Launching tool..." -ForegroundColor Yellow
Write-Host ""

# Execute the main tool script
try {
    & $toolScript
}
catch {
    Write-Host "An error occurred while running the tool:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}

Write-Host ""
Write-Host "Tool execution completed." -ForegroundColor Cyan

if ($NoExit) {
    Read-Host "Press Enter to exit"
}
