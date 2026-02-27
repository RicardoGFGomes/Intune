#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Autopilot Registration GUID Tool - WPF UI for managing Autopilot profiles and device information
    
.DESCRIPTION
    This tool provides a WPF interface to:
    - Display device information (IP address, serial number)
    - Check internet connectivity
    - Connect to Microsoft Graph API
    - Retrieve and manage Autopilot profiles
    - Extract OrderID from dynamic group queries
#>

# Set error action preference
$ErrorActionPreference = "Continue"

# Global variables
$global:graphConnected = $false
$global:accessToken = $null
$global:autopilotProfiles = @()
$script:selectedGroupTag = ""

# ==================== Helper Functions ====================

function Get-DeviceInformation {
    <#
    .SYNOPSIS
    Retrieves device information like IP address and serial number
    #>
    try {
        # Get IP Address
        $ipAddress = (Get-NetIPAddress -AddressFamily IPv4 -PrefixLength 24 | Where-Object { $_.IPAddress -notmatch "^127|^169" } | Select-Object -First 1).IPAddress
        if (-not $ipAddress) {
            $ipAddress = "Not Found"
        }
        
        # Get Serial Number
        $serialNumber = (Get-WmiObject -Class Win32_BIOS).SerialNumber
        if (-not $serialNumber) {
            $serialNumber = "Not Found"
        }
        
        # Get Computer Name
        $computerName = $env:COMPUTERNAME
        
        return @{
            IPAddress = $ipAddress
            SerialNumber = $serialNumber
            ComputerName = $computerName
        }
    }
    catch {
        return @{
            IPAddress = "Error"
            SerialNumber = "Error"
            ComputerName = $env:COMPUTERNAME
        }
    }
}

function Test-InternetConnectivity {
    <#
    .SYNOPSIS
    Tests internet connectivity
    #>
    try {
        $testResults = Test-Connection -ComputerName 8.8.8.8 -Count 1 -ErrorAction Stop
        return $true
    }
    catch {
        try {
            Test-Connection -ComputerName google.com -Count 1 -ErrorAction Stop | Out-Null
            return $true
        }
        catch {
            return $false
        }
    }
}

function Initialize-GraphModules {
    <#
    .SYNOPSIS
    Installs and imports only the required minimal Graph API modules
    #>
    $requiredModules = @(
        "Microsoft.Graph.Authentication",
        "Microsoft.Graph.DeviceManagement"
    )
    
    foreach ($module in $requiredModules) {
        try {
            if (-not (Get-Module -ListAvailable -Name $module)) {
                Write-Verbose "Installing $module..."
                Install-Module -Name $module -Force -AllowClobber -ErrorAction Stop
            }
            Import-Module -Name $module -ErrorAction Stop
        }
        catch {
            Write-Error "Failed to install/import $module : $_"
            return $false
        }
    }
    
    return $true
}

function Connect-ToGraphAPI {
    <#
    .SYNOPSIS
    Connects to Microsoft Graph API with minimal required scopes
    #>
    try {
        $scopes = @(
            "DeviceManagementServiceConfig.Read.All",
            "Directory.Read.All"
        )
        
        # Disable WAM and use web authentication
        [System.Environment]::SetEnvironmentVariable("MSAL_LOG_LEVEL", "None")
        
        $connection = Connect-MgGraph -Scopes $scopes -NoWelcome -ErrorAction Stop 2>&1 | Where-Object {$_.GetType().Name -ne 'WarningRecord'}
        $global:graphConnected = $true
        return $true
    }
    catch {
        Write-Error "Failed to connect to Graph API: $_"
        $global:graphConnected = $false
        return $false
    }
}

function Disconnect-FromGraphAPI {
    <#
    .SYNOPSIS
    Disconnects from Microsoft Graph API
    #>
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        $global:graphConnected = $false
        return $true
    }
    catch {
        return $false
    }
}

function Get-AutopilotProfiles {
    <#
    .SYNOPSIS
    Retrieves Windows Autopilot deployment profiles from Microsoft Graph
    #>
    try {
        # Use the dedicated Windows Autopilot endpoint
        $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles"
        $profiles = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
        
        if ($profiles.value -and $profiles.value.Count -gt 0) {
            $profileData = @()
            foreach ($profile in $profiles.value) {
                $profileData += @{
                    Name = $profile.displayName
                    ID = $profile.id
                    Profile = $profile
                }
            }
            $global:autopilotProfiles = $profileData
            return $profileData
        }
        
        return @()
    }
    catch {
        Write-Error "Failed to retrieve Autopilot profiles: $_"
        return @()
    }
}

function Get-AutopilotProfilesV2 {
    <#
    .SYNOPSIS
    Alternative method to get Windows Autopilot deployment profiles
    #>
    try {
        # Try the dedicated Windows Autopilot endpoint
        $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles"
        $profiles = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
        
        $autopilotProfiles = @()
        if ($profiles.value) {
            foreach ($profile in $profiles.value) {
                $autopilotProfiles += @{
                    Name = $profile.displayName
                    ID = $profile.id
                    Profile = $profile
                }
            }
        }
        
        $global:autopilotProfiles = $autopilotProfiles
        return $autopilotProfiles
    }
    catch {
        Write-Error "Failed to retrieve Autopilot profiles (v2): $_"
        return @()
    }
}

function Extract-OrderIDFromQuery {
    <#
    .SYNOPSIS
    Extracts OrderID from dynamic group query expressions
    .EXAMPLE
    Extract-OrderIDFromQuery "(device.devicePhysicalIds -any (_ -eq `"[OrderID]:179887111881`"))"
    Returns: 179887111881
    
    Supports any alphanumeric characters, underscores, hyphens, etc.
    #>
    param(
        [string]$QueryExpression
    )
    
    if ([string]::IsNullOrWhiteSpace($QueryExpression)) {
        return $null
    }
    
    # Extract everything between [OrderID]: and the closing quote
    if ($QueryExpression -match '\[OrderID\]:([^"'']+)') {
        return $matches[1]
    }
    
    return $null
}

function Get-GroupAssignmentsForProfile {
    <#
    .SYNOPSIS
    Gets assigned groups for an Autopilot profile and extracts OrderID
    #>
    param(
        [string]$ProfileID
    )
    
    try {
        # Use the correct endpoint for Windows Autopilot deployment profiles
        $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles/$ProfileID/assignments"
        $assignments = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
        
        $groupData = @()
        if ($assignments.value) {
            foreach ($assignment in $assignments.value) {
                # Try different property paths for group ID
                $groupID = $null
                
                if ($assignment.target.groupId) {
                    $groupID = $assignment.target.groupId
                }
                elseif ($assignment.groupId) {
                    $groupID = $assignment.groupId
                }
                elseif ($assignment.target.PSObject.Properties.Name -contains 'id') {
                    $groupID = $assignment.target.id
                }
                
                if ($groupID) {
                    try {
                        # Get group details
                        $groupUri = "https://graph.microsoft.com/v1.0/groups/$groupID`?`$select=id,displayName,membershipRule,membershipRuleProcessingState"
                        $group = Invoke-MgGraphRequest -Method GET -Uri $groupUri -ErrorAction Stop
                        
                        $orderID = $null
                        if ($group.membershipRule) {
                            $orderID = Extract-OrderIDFromQuery -QueryExpression $group.membershipRule
                        }
                        
                        $groupData += @{
                            GroupName = $group.displayName
                            GroupID = $groupID
                            OrderID = $orderID
                            MembershipRule = $group.membershipRule
                        }
                    }
                    catch {
                        Write-Verbose "Failed to get details for group $groupID : $_"
                    }
                }
            }
        }
        
        return $groupData
    }
    catch {
        Write-Error "Failed to get group assignments: $_"
        return @()
    }
}

# ==================== WPF Form Creation ====================

function New-WPFWindow {
    <#
    .SYNOPSIS
    Creates the main WPF window
    #>
    
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Autopilot Registration GUID Tool"
        Height="700"
        Width="900"
        WindowStartupLocation="CenterScreen"
        Background="#F5F5F5">
    <Window.Resources>
        <Style x:Key="CustomButton" TargetType="Button">
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" 
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="3">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                            Opacity="{TemplateBinding Opacity}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Opacity" Value="0.85"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Opacity" Value="0.7"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.6"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <!-- Title -->
        <Border Grid.Row="0" Background="#0078D4" Padding="20">
            <TextBlock Text="Autopilot Registration GUID Tool" FontSize="24" FontWeight="Bold" Foreground="White"/>
        </Border>
        
        <!-- Device Info Section -->
        <Border Grid.Row="1" Background="White" Margin="10" Padding="15" BorderBrush="#E0E0E0" BorderThickness="0,0,0,1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                
                <!-- Left Column: Device Info -->
                <Grid Grid.Column="0" Margin="0,0,20,0">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" Text="Device Information" FontSize="13" FontWeight="Bold" Margin="0,0,0,8"/>
                    <Grid Grid.Row="1" Margin="0,0,0,5">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="120"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Grid.Column="0" Text="Computer:" FontWeight="SemiBold"/>
                        <TextBlock Grid.Column="1" x:Name="ComputerNameText" Text="Loading..."/>
                    </Grid>
                    <Grid Grid.Row="2" Margin="0,0,0,5">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="120"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Grid.Column="0" Text="IP Address:" FontWeight="SemiBold"/>
                        <TextBlock Grid.Column="1" x:Name="IPAddressText" Text="Loading..."/>
                    </Grid>
                    <Grid Grid.Row="3">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="120"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Grid.Column="0" Text="Serial Number:" FontWeight="SemiBold"/>
                        <TextBlock Grid.Column="1" x:Name="SerialNumberText" Text="Loading..."/>
                    </Grid>
                </Grid>
                
                <!-- Right Column: Status -->
                <Grid Grid.Column="1">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" Text="System Status" FontSize="13" FontWeight="Bold" Margin="0,0,0,8"/>
                    <Grid Grid.Row="1" Margin="0,0,0,8">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="16"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Ellipse Grid.Column="0" Width="12" Height="12" x:Name="InternetStatusIndicator" Fill="#FFC107"/>
                        <TextBlock Grid.Column="1" x:Name="InternetStatusText" Text="Internet: Checking..." Margin="8,0,0,0" VerticalAlignment="Center"/>
                    </Grid>
                    <Grid Grid.Row="2">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="16"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Ellipse Grid.Column="0" Width="12" Height="12" x:Name="GraphStatusIndicator" Fill="#D32F2F"/>
                        <TextBlock Grid.Column="1" x:Name="GraphStatusText" Text="Graph API: Not Connected" Margin="8,0,0,0" VerticalAlignment="Center"/>
                    </Grid>
                </Grid>
            </Grid>
        </Border>
        
        <!-- Main Content -->
        <Grid Grid.Row="2" Margin="10">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            
            <Button Grid.Row="0" x:Name="ConnectGraphButton" Content="Connect to Graph API" Height="40" Background="#0078D4" Foreground="White" FontSize="14" Margin="0,0,0,15" Cursor="Hand" Style="{DynamicResource CustomButton}"/>
            
            <Border Grid.Row="1" Background="White" BorderBrush="#E0E0E0" BorderThickness="1" Padding="15">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    
                    <TextBlock Grid.Row="0" Text="Autopilot Profiles" FontSize="13" FontWeight="Bold" Margin="0,0,0,10"/>
                    
                    <Grid Grid.Row="1" Margin="0,0,0,10">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Grid.Column="0" Text="Profile:" FontWeight="SemiBold" VerticalAlignment="Center"/>
                        <ComboBox Grid.Column="1" x:Name="ProfileDropdown" Margin="10,0,0,0" Height="32" IsEnabled="False"/>
                    </Grid>
                    
                    <Border Grid.Row="2" Background="#F5F5F5" BorderBrush="#E0E0E0" BorderThickness="1" Padding="10" Margin="0,0,0,10">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <TextBlock Grid.Row="0" Text="Group Tag (OrderID):" FontSize="12" FontWeight="SemiBold" Margin="0,0,0,5"/>
                            <TextBlock Grid.Row="1" x:Name="GroupTagText" Text="No profile selected" FontSize="16" Foreground="#0078D4" FontWeight="Bold" Margin="0,0,0,10"/>
                            
                            <CheckBox Grid.Row="2" x:Name="WaitForRegistrationCheckbox" Content="Wait for registration (Profile Assignment)" VerticalAlignment="Center" Margin="0,0,0,5" IsEnabled="False"/>
                            <CheckBox Grid.Row="3" x:Name="RebootCheckbox" Content="Reboot after registration" VerticalAlignment="Center" IsEnabled="False"/>
                        </Grid>
                    </Border>
                    
                    <TextBlock Grid.Row="3" Text="Assigned Groups:" FontSize="12" FontWeight="SemiBold" Margin="0,0,0,5"/>
                    <ListBox Grid.Row="4" x:Name="GroupsList" Background="#FAFAFA" BorderBrush="#E0E0E0"/>
                </Grid>
            </Border>
        </Grid>
        
        <!-- Footer -->
        <Border Grid.Row="3" Background="White" BorderBrush="#E0E0E0" BorderThickness="0,1,0,0" Padding="10">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                
                <Button Grid.Column="1" x:Name="RegisterDeviceButton" Content="Register Device" Width="140" Height="32" Background="#0078D4" Foreground="White" Margin="0,0,10,0" Cursor="Hand" IsEnabled="False" Style="{DynamicResource CustomButton}"/>
                <Button Grid.Column="2" x:Name="CleanupButton" Content="Cleanup" Width="100" Height="32" Background="#FF8C00" Foreground="White" Margin="0,0,10,0" Cursor="Hand" IsEnabled="True" Style="{DynamicResource CustomButton}"/>
                <Button Grid.Column="3" x:Name="RefreshButton" Content="Refresh Profiles" Width="130" Height="32" Background="#107C10" Foreground="White" Margin="0,0,10,0" Cursor="Hand" IsEnabled="False" Style="{DynamicResource CustomButton}"/>
                <Button Grid.Column="4" x:Name="ExitButton" Content="Exit" Width="90" Height="32" Background="#D32F2F" Foreground="White" Cursor="Hand" Style="{DynamicResource CustomButton}"/>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

    return $xaml
}



# ==================== Main Script Execution ====================

try {
    # Add Windows Forms and WPF assemblies
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    
    # Show splash screen with initialization progress
    $splashXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Initializing..."
        Height="200"
        Width="400"
        WindowStartupLocation="CenterScreen"
        Background="#F5F5F5"
        WindowStyle="None"
        AllowsTransparency="True">
    <Grid Background="White">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <TextBlock Grid.Row="0" Text="Autopilot Registration Tool" FontSize="16" FontWeight="Bold" Foreground="#0078D4" Margin="20,20,20,0" TextAlignment="Center"/>
        <TextBlock Grid.Row="1" x:Name="StatusText" Text="Installing dependencies..." FontSize="12" Foreground="#333333" Margin="20,15,20,0" TextAlignment="Center"/>
        <ProgressBar Grid.Row="2" x:Name="InitProgress" Height="8" Margin="20,20,20,20" Background="#E0E0E0" Foreground="#0078D4" IsIndeterminate="True"/>
    </Grid>
</Window>
"@
    
    try {
        $splashReader = [System.Xml.XmlNodeReader]::new([xml]$splashXaml)
        $splashWindow = [System.Windows.Markup.XamlReader]::Load($splashReader)
        
        if ($splashWindow -eq $null) {
            throw "Splash window failed to load"
        }
        
        $statusText = $splashWindow.FindName("StatusText")
        
        if ($statusText -eq $null) {
            throw "StatusText element not found in splash window"
        }
        
        $splashWindow.Show()
        Start-Sleep -Milliseconds 100
        
        # Use window dispatcher for UI updates
        $dispatcher = $splashWindow.Dispatcher
        
        # Initialize Graph modules
        if ($statusText -ne $null -and $dispatcher -ne $null) {
            $statusText.Text = "Installing Microsoft Graph modules..."
            try {
                $dispatcher.Invoke([System.Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
            }
            catch {
                # Dispatcher may not be available, continue without it
            }
        }
        
        if (-not (Initialize-GraphModules)) {
            [System.Windows.Forms.MessageBox]::Show("Failed to initialize Graph API modules. Script will exit.", "Initialization Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            if ($splashWindow) { $splashWindow.Close() }
            exit
        }
        
        # Pre-install Get-WindowsAutopilotinfo script
        if ($statusText -ne $null) {
            $statusText.Text = "Installing Get-WindowsAutopilotinfo script..."
            try {
                $dispatcher.Invoke([System.Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
            }
            catch {
                # Dispatcher may not be available, continue without it
            }
        }
        
        try {
            # Only install if not already installed
            if (-not (Get-InstalledScript -Name Get-WindowsAutopilotinfo -ErrorAction SilentlyContinue)) {
                Install-Script -Name Get-WindowsAutopilotinfo -Force -ErrorAction Stop
                Write-Verbose "Get-WindowsAutopilotinfo script installed successfully"
            } else {
                Write-Verbose "Get-WindowsAutopilotinfo script already installed"
            }
        }
        catch {
            Write-Verbose "Get-WindowsAutopilotinfo installation skipped: $_"
        }
        
        # Close splash window
        if ($splashWindow) { $splashWindow.Close() }
    }
    catch {
        $errorMsg = $_.Exception.Message
        Write-Warning "An error occurred during initialization: $errorMsg"
        
        # Show error dialog but don't exit - let user try again
        [System.Windows.Forms.MessageBox]::Show("Initialization warning: `n$errorMsg`n`nThe application will continue but some features may not work properly.", "Warning", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        
        # Continue with basic window creation even if some initialization failed
        try {
            # Create WPF window
            $xaml = New-WPFWindow
            $xmlReader = [System.Xml.XmlNodeReader]::new([xml]$xaml)
            $window = [System.Windows.Markup.XamlReader]::Load($xmlReader)
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show("Fatal error: Could not create main window.`n$_", "Fatal Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            if ($splashWindow) { $splashWindow.Close() }
            exit 1
        }
    }
    
    # Create WPF window
    $xaml = New-WPFWindow
    $xmlReader = [System.Xml.XmlNodeReader]::new([xml]$xaml)
    $window = [System.Windows.Markup.XamlReader]::Load($xmlReader)
    
    if ($window -eq $null) {
        throw "Failed to create main window"
    }
    
    # Get control references with safety checks
    $ComputerNameText = $window.FindName("ComputerNameText")
    $IPAddressText = $window.FindName("IPAddressText")
    $SerialNumberText = $window.FindName("SerialNumberText")
    $InternetStatusIndicator = $window.FindName("InternetStatusIndicator")
    $InternetStatusText = $window.FindName("InternetStatusText")
    $GraphStatusIndicator = $window.FindName("GraphStatusIndicator")
    $GraphStatusText = $window.FindName("GraphStatusText")
    $ConnectGraphButton = $window.FindName("ConnectGraphButton")
    $ProfileDropdown = $window.FindName("ProfileDropdown")
    $GroupTagText = $window.FindName("GroupTagText")
    $GroupsList = $window.FindName("GroupsList")
    $WaitForRegistrationCheckbox = $window.FindName("WaitForRegistrationCheckbox")
    $RebootCheckbox = $window.FindName("RebootCheckbox")
    $RegisterDeviceButton = $window.FindName("RegisterDeviceButton")
    $CleanupButton = $window.FindName("CleanupButton")
    $RefreshButton = $window.FindName("RefreshButton")
    $ExitButton = $window.FindName("ExitButton")
    
    # Verify critical controls were found
    if ($ComputerNameText -eq $null -or $RegisterDeviceButton -eq $null -or $ConnectGraphButton -eq $null) {
        throw "Critical UI controls not found - XAML may be corrupted"
    }
    
    # Populate device information
    $deviceInfo = Get-DeviceInformation
    $ComputerNameText.Text = $deviceInfo.ComputerName
    $IPAddressText.Text = $deviceInfo.IPAddress
    $SerialNumberText.Text = $deviceInfo.SerialNumber
    
    # Check internet connectivity
    $internetConnected = Test-InternetConnectivity
    if ($internetConnected) {
        $InternetStatusIndicator.Fill = "#4CAF50"
        $InternetStatusText.Text = "Internet: Connected"
    }
    else {
        $InternetStatusIndicator.Fill = "#D32F2F"
        $InternetStatusText.Text = "Internet: Disconnected"
    }
    
    # Connect to Graph API button event
    $ConnectGraphButton.Add_Click({
        $ConnectGraphButton.IsEnabled = $false
        $ConnectGraphButton.Content = "Connecting..."
        
        if (Connect-ToGraphAPI) {
            $GraphStatusIndicator.Fill = "#4CAF50"
            $GraphStatusText.Text = "Graph API: Connected"
            $ConnectGraphButton.Visibility = [System.Windows.Visibility]::Collapsed
            $RefreshButton.IsEnabled = $true
            $ProfileDropdown.IsEnabled = $true
            
            # Load Autopilot profiles
            $profiles = Get-AutopilotProfilesV2
            if ($profiles.Count -eq 0) {
                $profiles = Get-AutopilotProfiles
            }
            
            if ($profiles.Count -gt 0) {
                foreach ($profile in $profiles) {
                    [void]$ProfileDropdown.Items.Add($profile.Name)
                }
                [System.Windows.Forms.MessageBox]::Show("Successfully connected! Found $($profiles.Count) profile(s).", "Connection Successful", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            }
            else {
                [System.Windows.Forms.MessageBox]::Show("Connected to Graph API, but no profiles found.", "No Profiles", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            }
        }
        else {
            $GraphStatusIndicator.Fill = "#D32F2F"
            $GraphStatusText.Text = "Graph API: Connection Failed"
            $ConnectGraphButton.IsEnabled = $true
            $ConnectGraphButton.Content = "Connect to Graph API"
            [System.Windows.Forms.MessageBox]::Show("Failed to connect to Graph API. Please try again.", "Connection Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })
    
    # Profile dropdown selection changed
    $ProfileDropdown.Add_SelectionChanged({
        if ($ProfileDropdown.SelectedIndex -ge 0) {
            $selectedProfile = $global:autopilotProfiles[$ProfileDropdown.SelectedIndex]
            
            # Get group assignments and extract OrderID
            $groupAssignments = Get-GroupAssignmentsForProfile -ProfileID $selectedProfile.ID
            
            $GroupsList.Items.Clear()
            $orderIDs = @()
            
            foreach ($group in $groupAssignments) {
                $displayText = "$($group.GroupName)"
                if ($group.OrderID) {
                    $displayText += " (OrderID: $($group.OrderID))"
                    $orderIDs += $group.OrderID
                }
                else {
                    if ($group.MembershipRule) {
                        $displayText += " (Rule: $($group.MembershipRule.Substring(0, [Math]::Min(50, $group.MembershipRule.Length)))...)"
                    }
                }
                [void]$GroupsList.Items.Add($displayText)
            }
            
            # Display the first OrderID or combined
            if ($orderIDs.Count -gt 0) {
                $GroupTagText.Text = $orderIDs[0]
                $script:selectedGroupTag = $orderIDs[0]
            }
            else {
                $GroupTagText.Text = "No OrderID found"
                $script:selectedGroupTag = ""
            }
            
            # Enable checkboxes and register button
            $WaitForRegistrationCheckbox.IsEnabled = $true
            $RebootCheckbox.IsEnabled = $true
            $RegisterDeviceButton.IsEnabled = $true
        }
        else {
            # Disable if no profile selected
            $WaitForRegistrationCheckbox.IsEnabled = $false
            $RebootCheckbox.IsEnabled = $false
            $RegisterDeviceButton.IsEnabled = $false
            $script:selectedGroupTag = ""
        }
    })
    
    # Refresh profiles button
    $RefreshButton.Add_Click({
        $RefreshButton.IsEnabled = $false
        $RefreshButton.Content = "Refreshing..."
        
        $ProfileDropdown.Items.Clear()
        $profiles = Get-AutopilotProfilesV2
        
        foreach ($profile in $profiles) {
            [void]$ProfileDropdown.Items.Add($profile.Name)
        }
        
        $RefreshButton.Content = "Refresh Profiles"
        $RefreshButton.IsEnabled = $true
        [System.Windows.Forms.MessageBox]::Show("Profiles refreshed!", "Refresh Complete", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    })
    
    # Register Device button
    $RegisterDeviceButton.Add_Click({
        try {
            if ([string]::IsNullOrWhiteSpace($script:selectedGroupTag)) {
                [System.Windows.Forms.MessageBox]::Show("No Group Tag (OrderID) found. Please select a profile with a Group Tag.", "Missing Group Tag", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                return
            }
            
            $RegisterDeviceButton.IsEnabled = $false
            $RegisterDeviceButton.Content = "Registering..."
        
        # Create progress window
        $progressXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Device Registration"
        Height="400"
        Width="600"
        WindowStartupLocation="CenterOwner"
        Background="#F5F5F5">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <Border Grid.Row="0" Background="#0078D4" Padding="15">
            <TextBlock Text="Registering Device with Windows Autopilot" FontSize="14" FontWeight="Bold" Foreground="White"/>
        </Border>
        
        <TextBox Grid.Row="1" x:Name="OutputText" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" 
                 FontFamily="Consolas" FontSize="10" Background="White" BorderBrush="#E0E0E0" Margin="10"/>
        
        <ProgressBar Grid.Row="2" x:Name="RegProgress" Height="8" Margin="10" Background="#E0E0E0" 
                     Foreground="#0078D4" IsIndeterminate="True"/>
        
        <Button Grid.Row="3" x:Name="CloseButton" Content="Close" Width="100" Height="32" 
                Background="#D32F2F" Foreground="White" Margin="10" HorizontalAlignment="Right" IsEnabled="False"/>
    </Grid>
</Window>
"@
        
        try {
            $progressReader = [System.Xml.XmlNodeReader]::new([xml]$progressXaml)
            $progressWindow = [System.Windows.Markup.XamlReader]::Load($progressReader)
            
            if ($progressWindow -eq $null) {
                throw "Failed to create progress window"
            }
            
            $outputText = $progressWindow.FindName("OutputText")
            $closeButton = $progressWindow.FindName("CloseButton")
            
            if ($outputText -eq $null) {
                throw "OutputText element not found in progress window"
            }
            
            if ($closeButton -eq $null) {
                throw "CloseButton element not found in progress window"
            }
            
            $closeButton.Add_Click({
                $progressWindow.Close()
            })
            
            # Show progress window
            $progressWindow.Owner = $window
            $progressWindow.Show()
            
            try {
                $progressWindow.Dispatcher.Invoke([System.Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
            }
            catch {
                # Ignore dispatcher errors, continue without UI updates
                Write-Verbose "Dispatcher invoke failed: $_"
            }
            
            # Build command parameters using hashtable for proper splatting
            $params = @{
                Online = $true
                GroupTag = $script:selectedGroupTag
            }
            
            if ($WaitForRegistrationCheckbox.IsChecked) {
                $params.Add("Assign", $true)
            }
            
            if ($RebootCheckbox.IsChecked) {
                $params.Add("Reboot", $true)
            }
            
            # Run Get-WindowsAutopilotinfo and capture output
            if ($outputText -ne $null) {
                try {
                    $outputText.AppendText("Starting device registration...`r`n")
                    $outputText.AppendText("Group Tag: $($script:selectedGroupTag)`r`n")
                    if ($WaitForRegistrationCheckbox.IsChecked) { $outputText.AppendText("Wait for Assignment: Yes`r`n") }
                    if ($RebootCheckbox.IsChecked) { $outputText.AppendText("Reboot After: Yes`r`n") }
                    $outputText.AppendText("`r`n")
                    $outputText.ScrollToEnd()
                }
                catch {
                    # Ignore UI update errors
                    Write-Verbose "UI update failed: $_"
                }
            }
            $progressWindow.Dispatcher.Invoke([System.Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
            
            # Add PowerShell Scripts directory to PATH to ensure Get-WindowsAutopilotinfo is found
            $originalPath = $env:PATH
            try {
                $scriptsPath = "C:\Program Files\WindowsPowerShell\Scripts"
                if ($env:PATH -notlike "*$scriptsPath*") {
                    $env:PATH += ";$scriptsPath"
                    if ($outputText -ne $null) {
                        $outputText.AppendText("Added PowerShell Scripts directory to PATH`r`n")
                        $outputText.ScrollToEnd()
                    }
                }
            }
            catch {
                if ($outputText -ne $null) {
                    $outputText.AppendText("Warning: Could not modify PATH: $($_.Exception.Message)`r`n")
                    $outputText.ScrollToEnd()
                }
            }
            
            # Execute Get-WindowsAutopilotinfo with simplified output capture
            if ($outputText -ne $null) {
                try {
                    $outputText.AppendText("Executing Get-WindowsAutopilotinfo...`r`n`r`n")
                    $outputText.ScrollToEnd()
                }
                catch {
                    # Ignore UI update errors
                    Write-Verbose "Pre-execution UI update failed: $_"
                }
            }
            
            try {
                # Build command string
                $cmdArgs = @("-Online", "-GroupTag", $script:selectedGroupTag)
                if ($WaitForRegistrationCheckbox.IsChecked) { $cmdArgs += "-Assign" }
                if ($RebootCheckbox.IsChecked) { $cmdArgs += "-Reboot" }
                
                # Execute using Start-Process with output redirection
                $tempFile = [System.IO.Path]::GetTempFileName()
                $cmdString = "Get-WindowsAutopilotinfo $($cmdArgs -join ' ') 2>&1"
                
                $processParams = @{
                    FilePath = "powershell.exe"
                    ArgumentList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $cmdString)
                    RedirectStandardOutput = $tempFile
                    Wait = $true
                    WindowStyle = "Hidden"
                    PassThru = $true
                }
                
                if ($outputText -ne $null) {
                    try {
                        $outputText.AppendText("Running command: $cmdString`r`n`r`n")
                        $outputText.ScrollToEnd()
                    }
                    catch {
                        Write-Verbose "Command display update failed: $_"
                    }
                }
                
                $process = Start-Process @processParams
                
                # Read and display output
                if (Test-Path $tempFile) {
                    $output = Get-Content $tempFile -Raw
                    if ($outputText -ne $null -and $output) {
                        try {
                            $outputText.AppendText($output)
                            $outputText.ScrollToEnd()
                        }
                        catch {
                            Write-Verbose "Output display update failed: $_"
                        }
                    }
                    Remove-Item $tempFile -ErrorAction SilentlyContinue
                }
                
                if ($outputText -ne $null) {
                    try {
                        $outputText.AppendText("`r`nProcess completed with exit code: $($process.ExitCode)`r`n")
                        $outputText.ScrollToEnd()
                    }
                    catch {
                        Write-Verbose "Process completion display failed: $_"
                    }
                }
            }
            catch {
                if ($outputText -ne $null) {
                    try {
                        $outputText.AppendText("Execution Error: $($_.Exception.Message)`r`n")
                        $outputText.ScrollToEnd()
                    }
                    catch {
                        Write-Verbose "Execution error display failed: $_"
                    }
                }
            }
            
            if ($outputText -ne $null) {
                try {
                    $outputText.AppendText("`r`nDevice registration completed!`r`n")
                    $outputText.ScrollToEnd()
                }
                catch {
                    # Ignore final UI update errors
                    Write-Verbose "Final UI update failed: $_"
                }
            }
            if ($closeButton -ne $null) {
                $closeButton.IsEnabled = $true
            }
            
        }
        catch {
            # Handle any errors in progress window creation or execution
            $errorMessage = "Registration failed: $($_.Exception.Message)"
            Write-Warning $errorMessage
            
            # Try to show error in progress window first, fallback to message box
            if ($outputText -ne $null) {
                try {
                    $outputText.AppendText("`r`n$errorMessage`r`n")
                    $outputText.ScrollToEnd()
                }
                catch {
                    # If UI update fails, show message box
                    [System.Windows.Forms.MessageBox]::Show($errorMessage, "Registration Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                }
            }
            else {
                # No progress window available, show message box
                [System.Windows.Forms.MessageBox]::Show($errorMessage, "Registration Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
            
            if ($closeButton -ne $null) {
                try {
                    $closeButton.IsEnabled = $true
                }
                catch {
                    # Ignore if we can't enable the close button
                }
            }
        }
        finally {
            # Restore original PATH
            try {
                if ($originalPath) {
                    $env:PATH = $originalPath
                }
            }
            catch {
                # Ignore PATH restoration errors
            }
            
            # Restore button state
            try {
                $RegisterDeviceButton.IsEnabled = $true
                $RegisterDeviceButton.Content = "Register Device"
            }
            catch {
                # Ignore button state restoration errors
            }
        }
    }
    catch {
        # Catch any errors in the entire event handler
        $fatalError = "Fatal error in registration handler: $($_.Exception.Message)"
        Write-Error $fatalError
        
        try {
            [System.Windows.Forms.MessageBox]::Show($fatalError, "Fatal Registration Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
        catch {
            # Can't even show a message box, write to console
            Write-Host $fatalError -ForegroundColor Red
        }
        
        # Try to restore button state even in fatal error
        try {
            $RegisterDeviceButton.IsEnabled = $true
            $RegisterDeviceButton.Content = "Register Device"
        }
        catch {
            # Ignore final restoration errors
        }
    }
    })
    
    # Cleanup button
    $CleanupButton.Add_Click({
        $result = [System.Windows.Forms.MessageBox]::Show("This will remove:`n- Microsoft.Graph.Authentication module`n- Microsoft.Graph.DeviceManagement module`n- Get-WindowsAutopilotinfo script`n- Any cached tokens`n`nContinue?", "Confirm Cleanup", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
        
        if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
            return
        }
        
        $CleanupButton.IsEnabled = $false
        $CleanupButton.Content = "Cleaning..."
        
        try {
            Write-Host "Starting cleanup process..." -ForegroundColor Yellow
            
            # Disconnect from Graph API
            try {
                Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
                Write-Host "Disconnected from Microsoft Graph API" -ForegroundColor Green
            }
            catch { }
            
            # Uninstall Microsoft Graph modules
            $modulesToRemove = @("Microsoft.Graph.Authentication", "Microsoft.Graph.DeviceManagement")
            foreach ($module in $modulesToRemove) {
                try {
                    if (Get-Module -ListAvailable -Name $module -ErrorAction SilentlyContinue) {
                        Write-Host "Uninstalling $module..." -ForegroundColor Yellow
                        Uninstall-Module -Name $module -Force -AllVersions -ErrorAction Stop
                        Write-Host "Successfully uninstalled $module" -ForegroundColor Green
                    }
                }
                catch {
                    Write-Host "Warning: Could not uninstall $module : $_" -ForegroundColor Yellow
                }
            }
            
            # Uninstall Get-WindowsAutopilotinfo script
            try {
                if (Get-InstalledScript -Name Get-WindowsAutopilotinfo -ErrorAction SilentlyContinue) {
                    Write-Host "Uninstalling Get-WindowsAutopilotinfo script..." -ForegroundColor Yellow
                    Uninstall-Script -Name Get-WindowsAutopilotinfo -Force -ErrorAction Stop
                    Write-Host "Successfully uninstalled Get-WindowsAutopilotinfo script" -ForegroundColor Green
                }
            }
            catch {
                Write-Host "Warning: Could not uninstall Get-WindowsAutopilotinfo script : $_" -ForegroundColor Yellow
            }
            
            # Remove cached tokens
            try {
                $tokenPath = "$env:LOCALAPPDATA\Microsoft\Powershell\Powershell*.json"
                Get-Item -Path $tokenPath -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
                Write-Host "Cleared cached authentication tokens" -ForegroundColor Green
            }
            catch { }
            
            # Update status
            $global:graphConnected = $false
            $GraphStatusIndicator.Fill = "#D32F2F"
            $GraphStatusText.Text = "Graph API: Not Connected"
            $ConnectGraphButton.Visibility = [System.Windows.Visibility]::Visible
            $RefreshButton.IsEnabled = $false
            $ProfileDropdown.IsEnabled = $false
            $ProfileDropdown.Items.Clear()
            $GroupTagText.Text = "No profile selected"
            $GroupsList.Items.Clear()
            
            [System.Windows.Forms.MessageBox]::Show("Cleanup completed successfully!", "Cleanup Done", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show("Error during cleanup: $_", "Cleanup Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
        finally {
            $CleanupButton.IsEnabled = $true
            $CleanupButton.Content = "Cleanup"
        }
    })
    
    # Exit button
    $ExitButton.Add_Click({
        Disconnect-FromGraphAPI | Out-Null
        $window.Close()
    })
    
    # Window closing event
    $window.Add_Closing({
        Disconnect-FromGraphAPI | Out-Null
    })
    
    # Show window
    $window.ShowDialog() | Out-Null
}
catch {
    $errorMsg = $_.Exception.Message
    Write-Error "An error occurred: $errorMsg"
    Write-Error "Error Details: $($_.Exception.InnerException)"
    [System.Windows.Forms.MessageBox]::Show("An error occurred: `n$errorMsg", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}
finally {
    # Cleanup
    Disconnect-FromGraphAPI | Out-Null
    Write-Host "Autopilot Registration GUID Tool closed."
}
