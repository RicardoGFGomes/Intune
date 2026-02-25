<#
.SYNOPSIS
    Get hardware hash and other properties from a Windows PC for Windows Autopilot registration
    
.DESCRIPTION
    This script gets the hardware hash and other important properties from a Windows PC for Windows Autopilot registration
    
.PARAMETER Online
    Connect to Windows Autopilot and upload the device information
    
.PARAMETER GroupTag
    The Group Tag to assign to the device (OrderID from Autopilot profile)
    
.PARAMETER Assign
    Wait for the profile to be assigned (triggers automatic assignment if configured)
    
.PARAMETER Reboot
    Reboot the system after the hardware hash is uploaded
    
.EXAMPLE
    .\Get-WindowsAutoPilotInfo.ps1
    Gets the hardware hash and device information without uploading
    
.EXAMPLE
    .\Get-WindowsAutoPilotInfo.ps1 -Online -GroupTag "MYGROUP" -Assign -Reboot
    Gets hardware hash, uploads to Autopilot with group tag, waits for assignment, and reboots
    
.NOTES
    Created: Microsoft
    Version: 5.4
#>

param(
    [Parameter(Mandatory=$false)] [switch] $Online,
    [Parameter(Mandatory=$false)] [string] $GroupTag = "",
    [Parameter(Mandatory=$false)] [switch] $Assign,
    [Parameter(Mandatory=$false)] [switch] $Reboot
)

$ErrorActionPreference = "Continue"

# Get device information
function Get-WindowsAutoPilotInfo {
    $serial = (Get-WmiObject -Class Win32_BIOS).SerialNumber
    $manufacturer = (Get-WmiObject -Class Win32_ComputerSystemProduct).Vendor
    $model = (Get-WmiObject -Class Win32_ComputerSystemProduct).Name
    
    # Get hardware hash
    $devDetail = (Get-WmiObject -Namespace "root\cimv2\mdm\dmmap" -Class "MDM_DevDetail_Ext01" -Filter "InstanceID='Ext' AND ParentID='./DevDetail'" -ErrorAction SilentlyContinue)
    if ($null -eq $devDetail) {
        Write-Host "ERROR: Unable to get device information. Script must run as administrator." -ForegroundColor Red
        return $null
    }
    
    $hash = $devDetail.DeviceHardwareData
    
    return @{
        'SerialNumber' = $serial
        'Manufacturer' = $manufacturer
        'Model' = $model
        'HardwareHash' = $hash
    }
}

# Display device information
function Display-DeviceInfo {
    param($deviceInfo)
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Windows Autopilot Device Information" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Serial Number : $($deviceInfo.SerialNumber)" -ForegroundColor White
    Write-Host "Manufacturer  : $($deviceInfo.Manufacturer)" -ForegroundColor White
    Write-Host "Model         : $($deviceInfo.Model)" -ForegroundColor White
    Write-Host "Hardware Hash : $($deviceInfo.HardwareHash.Substring(0, 50))..." -ForegroundColor White
    Write-Host "========================================`n" -ForegroundColor Cyan
}

# Upload to Windows Autopilot
function Register-WindowsAutoPilotInfo {
    param(
        $deviceInfo,
        $groupTag = "",
        $waitForAssignment = $false
    )
    
    try {
        # If Online option is used, attempt to upload
        if ($Online) {
            Write-Host "Connecting to Microsoft intune..." -ForegroundColor Cyan
            
            # Ensure required modules are installed
            $requiredModules = @(
                "WindowsAutopilotIntune",
                "AzureAD",
                "Microsoft.Graph.Intune"
            )
            
            foreach ($module in $requiredModules) {
                if (-not (Get-Module -ListAvailable -Name $module -ErrorAction SilentlyContinue)) {
                    Write-Host "Installing module: $module" -ForegroundColor Yellow
                    Install-Module -Name $module -Force -AllowClobber -ErrorAction SilentlyContinue | Out-Null
                }
            }
            
            # Import modules
            Import-Module WindowsAutopilotIntune -Force -ErrorAction SilentlyContinue
            Import-Module AzureAD -Force -ErrorAction SilentlyContinue
            
            # Connect to Azure AD / Microsoft Graph
            Write-Host "Please sign in with your Intune admin account..." -ForegroundColor Yellow
            Connect-AzureAD -ErrorAction SilentlyContinue | Out-Null
            
            # Upload device
            Write-Host "Uploading device information..." -ForegroundColor Cyan
            Add-AutopilotImportedDevice -SerialNumber $deviceInfo.SerialNumber `
                -HardwareIdentifier $deviceInfo.HardwareHash `
                -GroupTag $groupTag -ErrorAction Stop
            
            Write-Host "Device uploaded successfully!" -ForegroundColor Green
            
            # If -Assign is specified, wait for assignment
            if ($Assign) {
                Write-Host "Waiting for profile assignment (this may take a few minutes)... " -ForegroundColor Cyan -NoNewline
                $maxWait = 0
                while ($maxWait -lt 300) { # Wait up to 5 minutes
                    $device = Get-AutopilotDevice -sn $deviceInfo.SerialNumber -ErrorAction SilentlyContinue
                    if ($null -ne $device -and $null -ne $device.deploymentProfileAssignmentStatus -and $device.deploymentProfileAssignmentStatus -ne "unassigned") {
                        Write-Host "SUCCESS" -ForegroundColor Green
                        Write-Host "Profile assigned: $($device.deploymentProfileAssignmentStatus)" -ForegroundColor Green
                        break
                    }
                    Start-Sleep -Seconds 5
                    $maxWait += 5
                    Write-Host "." -ForegroundColor Cyan -NoNewline
                }
                if ($maxWait -ge 300) {
                    Write-Host "TIMEOUT" -ForegroundColor Yellow
                    Write-Host "Warning: Profile assignment timeout. Device may still be assigned." -ForegroundColor Yellow
                }
            }
        }
    }
    catch {
        Write-Host "Error during registration: $_" -ForegroundColor Red
        return $false
    }
    
    return $true
}

# Main script execution
function Main {
    Write-Host "Windows Autopilot Information Tool" -ForegroundColor Cyan
    
    # Check if running as administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    if (-not $isAdmin) {
        Write-Host "ERROR: This script must run as Administrator" -ForegroundColor Red
        exit 1
    }
    
    # Get device information
    $deviceInfo = Get-WindowsAutoPilotInfo
    if ($null -eq $deviceInfo) {
        exit 1
    }
    
    # Display device information
    Display-DeviceInfo -deviceInfo $deviceInfo
    
    # Register if Online flag is specified
    if ($Online) {
        Register-WindowsAutoPilotInfo -deviceInfo $deviceInfo -groupTag $GroupTag -waitForAssignment $Assign
    }
    
    # Reboot if requested
    if ($Reboot -and $Online) {
        Write-Host "System will restart in 30 seconds..." -ForegroundColor Yellow
        Write-Host "Press Ctrl+C to cancel" -ForegroundColor Yellow
        Start-Sleep -Seconds 10
        
        # Give user a final message before restart
        Write-Host "Press Enter to restart now, or Ctrl+C to cancel" -ForegroundColor Yellow
        Read-Host
        
        Restart-Computer -Force
    }
}

# Run main function
Main
