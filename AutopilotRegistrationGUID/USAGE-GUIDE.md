# Windows Autopilot Registration Tool - Usage Guide

## Overview
This updated tool provides a complete Windows Autopilot registration solution with a user-friendly WPF interface for managing device registration and profile assignment.

## New Features

### 1. Register Device Button
The **"Register Device"** button automates the hardware hash collection and Autopilot registration process.

**What it does:**
- Launches the official Microsoft Get-WindowsAutoPilotInfo.ps1 script
- Uploads device hardware information to Windows Autopilot
- Uses the Group Tag (OrderID) from your selected Autopilot profile
- Applies the `-Assign` and `-Reboot` parameters based on your checkbox selections

**How to use:**
1. Connect to Microsoft Graph API (click "Connect to Graph API")
2. Select an Autopilot profile from the dropdown
3. Optionally check "Wait for registration (Profile Assignment)" to pause the process until the profile is assigned
4. Optionally check "Reboot after registration" to automatically restart the device
5. Click "Register Device"
6. A new elevated PowerShell window will open to perform the registration

### 2. Wait for Registration Checkbox
**Enabled when:** A profile with a Group Tag (OrderID) is selected

**When checked:** The registration process will include the `-Assign` parameter, which:
- Waits for the Autopilot profile to be assigned to the device
- Provides confirmation that the assignment was successful
- May take a few minutes to complete

**When unchecked:** The registration completes after uploading the hardware hash without waiting for assignment

### 3. Reboot after Registration Checkbox
**Enabled when:** A profile with a Group Tag (OrderID) is selected

**When checked:** After successful registration, the device will automatically restart
- Provides a 30-second warning before restart
- Allows Ctrl+C to cancel the restart
- Useful for completing the Autopilot setup process

**When unchecked:** The device will NOT restart after registration

### 4. Cleanup Button
Removes all installed components and resets the tool.

**What it removes:**
- Microsoft.Graph.Authentication module
- Microsoft.Graph.DeviceManagement module
- Get-WindowsAutoPilotInfo.ps1 script
- Cached authentication tokens

**When to use:**
- After completing Autopilot registration
- When you need to uninstall all related components
- Before handing over the device to end users

**How to use:**
1. Click the "Cleanup" button
2. Confirm the action in the dialog box
3. The tool will uninstall modules and remove scripts
4. The UI will reset and show "Graph API: Not Connected"

## Common Workflows

### Scenario 1: Basic Registration (Wait for Assignment)
1. Click "Connect to Graph API"
2. Select your Autopilot profile
3. **Check** "Wait for registration (Profile Assignment)"
4. **Uncheck** "Reboot after registration"
5. Click "Register Device"
6. Wait for the PowerShell window to show assignment confirmation
7. Close the PowerShell window when complete

### Scenario 2: Full Automated Setup
1. Click "Connect to Graph API"
2. Select your Autopilot profile
3. **Check** "Wait for registration (Profile Assignment)"
4. **Check** "Reboot after registration"
5. Click "Register Device"
6. The PowerShell window will complete registration and automatically reboot
7. Device will enter Windows Autopilot OOBE experience

### Scenario 3: Silent Registration (No Wait, No Reboot)
1. Click "Connect to Graph API"
2. Select your Autopilot profile
3. **Uncheck** both checkboxes
4. Click "Register Device"
5. The registration uploads and the PowerShell window closes quickly

## Requirements

### For the Tool:
- Windows 10/11 (administrator rights required)
- PowerShell 5.1 or later
- Internet connectivity
- Microsoft Entra ID / Office 365 administrator credentials

### For Registration:
- Device in Windows OOBE or Windows desktop environment
- Administrator privileges on the device
- Internet connectivity during registration
- Valid Autopilot profile with Group Tag configured

## Parameters Used

The "Register Device" button uses the following command structure:
```powershell
Get-WindowsAutoPilotInfo.ps1 -Online -GroupTag [OrderID] [-Assign] [-Reboot]
```

Where:
- `-Online` - Always used to upload to Autopilot
- `-GroupTag` - Set to your profile's OrderID
- `-Assign` - Added if "Wait for registration" is checked
- `-Reboot` - Added if "Reboot after registration" is checked

## Troubleshooting

### "Get-WindowsAutoPilotInfo.ps1 not found"
- Ensure Get-WindowsAutoPilotInfo.ps1 is in the same directory as AutopilotRegistrationGUID.ps1
- If deleted, download it again from the repository

### PowerShell window opens but closes immediately
- Check that the device has internet connectivity
- Verify you have administrator privileges
- Check Windows Autopilot enrollment restrictions aren't blocking the device

### Registration times out waiting for assignment
- The device may still be assigned even if timeout occurs
- Check Intune for device assignment status
- Verify the profile is assigned to the correct group

### Module installation fails
- Ensure internet connectivity
- Run the tool as administrator
- Check that Windows Update isn't blocking PowerShell module installation

## Advanced Information

### What Get-WindowsAutoPilotInfo.ps1 Does:
1. Collects device hardware information (serial number, manufacturer, model)
2. Extracts the Windows Autopilot hardware hash using WMI
3. If `-Online` is specified: uploads to Autopilot service
4. If `-Assign` is specified: waits for profile assignment (max 5 minutes)
5. If `-Reboot` is specified: automatically restarts the system

### Group Tag (OrderID) Extraction:
The tool automatically extracts the OrderID from your Autopilot profile's group assignment membership rule. This value is used to tag the device appropriately in the Autopilot service.

## Support

If you encounter issues:
1. Check the PowerShell command output for error details
2. Review Intune admin center for device registration status
3. Verify all prerequisites are met
4. Consult Microsoft Autopilot documentation at https://learn.microsoft.com/autopilot
