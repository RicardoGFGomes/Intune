# Autopilot Registration GUID Tool

A Windows PowerShell WPF application for managing Windows Autopilot profiles and extracting device group tags based on dynamic group membership rules.

## Features

### Device Information Display
- **Computer Name**: Local device hostname
- **IP Address**: IPv4 address of the device (excluding loopback and APIPA addresses)
- **Serial Number**: Hardware serial number from BIOS

### System Status Indicators
- **Internet Connectivity**: Shows if the device has internet access (tested via Google DNS and domain resolution)
- **Graph API Connection**: Displays connection status to Microsoft Graph API with color-coded indicators
  - 🔴 Red: Not connected or connection failed
  - 🟢 Green: Successfully connected
  - 🟡 Yellow: Checking status

### Graph API Integration (Minimal Module Installation)
The tool uses only two essential modules to keep startup time fast:
- `Microsoft.Graph.Authentication` - For authentication
- `Microsoft.Graph.DeviceManagement` - For Autopilot profile retrieval

Required Graph API Scopes:
- `DeviceManagementServiceConfig.Read.All`
- `Directory.Read.All`

### Autopilot Profile Management
- **Connect Button**: Initiates Azure AD interactive authentication to Microsoft Graph
- **Profile Dropdown**: Lists all available Autopilot deployment profiles (after successful connection)
- **Group Tag Extraction**: Automatically extracts OrderID from dynamic group membership rules

### OrderID Extraction Logic
The tool automatically parses dynamic group membership rules to extract the OrderID:

**Example Rule**: 
```
(device.devicePhysicalIds -any (_ -eq "[OrderID]:179887111881"))
```

**Extracted OrderID**: `179887111881`

This OrderID is displayed in the Group Tag section and represents the unique identifier for that Autopilot group assignment.

### Group Assignment Display
When a profile is selected:
- All assigned groups are listed
- Each group shows its OrderID (if available)
- First OrderID is displayed in the prominent "Group Tag" section

## Usage

### Prerequisites
- Windows 10/11
- PowerShell 5.1 or higher
- Administrator privileges
- Internet connectivity
- Azure AD account with appropriate permissions

### Running the Script

#### Local Execution
1. Open PowerShell as Administrator
2. Navigate to the script directory
3. Run the script:
   ```powershell
   .\AutopilotRegistrationGUID.ps1
   ```

4. The WPF window will open with:
   - Device information automatically populated
   - Internet status checked
   - Graph API in disconnected state

#### Running Directly from OOBE (Windows 11)

You can run the script directly from the Windows Out-of-Box Experience (OOBE) screen using this one-liner command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression (Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/RicardoGFGomes/Intune/refs/heads/main/AutopilotRegistrationGUID/AutopilotRegistrationGUID.ps1' -UseBasicParsing).Content"
```

This command:
- Downloads the latest version directly from your GitHub repository
- Runs with bypass execution policy for OOBE environments
- Executes with no stored profile settings
- Immediately launches the WPF interface for Autopilot profile selection and device registration

**Usage in OOBE:**
1. Press `Shift + F10` to open Command Prompt
2. Type `powershell` and press Enter
3. Paste the command above
4. Press Enter to execute
5. The tool will download and launch immediately
   - Graph API in disconnected state

#### Running Directly from OOBE (Windows 11)

You can run the script directly from the Windows Out-of-Box Experience (OOBE) screen using this one-liner command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression (Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/RicardoGFGomes/Intune/refs/heads/main/AutopilotRegistrationGUID/AutopilotRegistrationGUID.ps1' -UseBasicParsing).Content"
```

This command:
- Downloads the latest version directly from your GitHub repository
- Runs with bypass execution policy for OOBE environments
- Executes with no stored profile settings
- Immediately launches the WPF interface for Autopilot profile selection and device registration

**Usage in OOBE:**
1. Press `Shift + F10` to open Command Prompt
2. Type `powershell` and press Enter
3. Paste the command above
4. Press Enter to execute
5. The tool will download and launch immediately

### Connecting to Graph API

1. Click the **"Connect to Graph API"** button
2. An authentication dialog will appear
3. Sign in with your Azure AD account that has permissions to read Autopilot profiles
4. The button will change to show the connection status
5. Once connected, the profile dropdown will be enabled

### Selecting an Autopilot Profile

1. Click the **Profile** dropdown menu
2. Select the desired Autopilot profile
3. The tool will retrieve:
   - Assigned groups for that profile
   - Dynamic membership rules
   - OrderID from the membership rules
4. The **Group Tag** section will display the extracted OrderID
5. Assigned groups will be listed below with their OrderIDs

### Refreshing Profiles

Click the **"Refresh Profiles"** button to:
- Re-fetch all Autopilot profiles from Graph API
- Clear current selections
- Update the profile list

### Exiting the Application

Click the **"Exit"** button to:
- Disconnect from Microsoft Graph API
- Clear authentication tokens
- Close the application gracefully

## Technical Details

### Module Installation
The script automatically installs required Graph API modules if not already present. This typically takes 1-2 minutes on first run.

### Authentication
- Uses interactive browser-based authentication
- Tokens are temporary and session-specific
- Automatically disconnected on exit
- Supports multi-factor authentication (MFA)

### Error Handling
- Graceful handling of network failures
- User-friendly error dialogs
- Detailed logging to PowerShell console for troubleshooting

### Performance Considerations
- Minimal module loading for fast startup
- Only fetches profiles when explicitly requested
- Efficient Graph API queries using beta endpoints
- Caches profile data during session

## Troubleshooting

### "Failed to initialize Graph API modules"
- Ensure you have internet connectivity
- Check PowerShell execution policy: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`
- Verify NuGet package provider is installed

### "No profiles found"
- Verify your Azure AD account has `DeviceManagementServiceConfig.Read.All` permissions
- Confirm at least one Autopilot profile exists in your Intune environment

### "Failed to get group assignments"
- Check that the profile has assigned groups
- Verify your account has `Directory.Read.All` permissions
- Check Azure AD group membership rules are properly configured

### Connection Timeouts
- Check internet connectivity
- Verify firewall allows Graph API access
- Try refreshing the profiles

## Security Notes

- This tool requires administrative privileges
- Credentials are handled by the native Azure AD authentication provider
- No credentials are stored locally
- All communication uses HTTPS to Graph API
- Tokens are automatically cleared on application exit

## Additional Notes

- The tool is designed to be "snappy" - meaning it prioritizes fast startup and response times
- Only essential Graph API modules are installed to minimize file size and load time
- Each session is isolated; credentials must be re-entered if the script is run multiple times
- The dynamic group query parsing is optimized for standard Autopilot ordering ID patterns

## Support

For issues or questions:
1. Check PowerShell console output for detailed error messages
2. Verify Azure AD permissions
3. Ensure Graph API endpoints are accessible
4. Confirm Autopilot profiles exist in Intune

---

**Version**: 1.0  
**Last Updated**: February 2026  
**Author**: Autopilot Registration GUID Tool Development
