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
        "Microsoft.Graph.DeviceManagement",
        "Microsoft.Graph.Groups"
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
            "DeviceManagementServiceConfig.ReadWrite.All",
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

function Get-EntraIDGroups {
    <#
    .SYNOPSIS
    Retrieves non-dynamic EntraID groups from Microsoft Graph
    #>
    try {
        # Query for groups that are not dynamic (no membershipRule)
        $uri = "https://graph.microsoft.com/v1.0/groups?`$filter=groupTypes/any(c:c eq 'Unified') or mailEnabled eq false&`$select=id,displayName,membershipRule,membershipRuleProcessingState&`$top=999"
        $groups = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
        
        $nonDynamicGroups = @()
        if ($groups.value) {
            foreach ($group in $groups.value) {
                # Include only non-dynamic groups (no membershipRule or empty membershipRule)
                if ([string]::IsNullOrWhiteSpace($group.membershipRule)) {
                    $nonDynamicGroups += @{
                        Name = $group.displayName
                        ID = $group.id
                    }
                }
            }
        }
        
        # Sort groups by name for better user experience
        return $nonDynamicGroups | Sort-Object Name
    }
    catch {
        Write-Error "Failed to retrieve EntraID groups: $_"
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
        Height="610"
        Width="760"
        ResizeMode="NoResize"
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
        <Border Grid.Row="0" Background="#0078D4" Padding="12">
            <TextBlock Text="Autopilot Registration GUID Tool" FontSize="20" FontWeight="Bold" Foreground="White"/>
        </Border>
        
        <!-- Device Info Section -->
        <Border Grid.Row="1" Background="White" Margin="8" Padding="10" BorderBrush="#E0E0E0" BorderThickness="0,0,0,1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                
                <!-- Left Column: Device Info -->
                <Grid Grid.Column="0" Margin="0,0,15,0">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" Text="Device Information" FontSize="12" FontWeight="Bold" Margin="0,0,0,5"/>
                    <Grid Grid.Row="1" Margin="0,0,0,3">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="100"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Grid.Column="0" Text="Computer:" FontWeight="SemiBold"/>
                        <TextBlock Grid.Column="1" x:Name="ComputerNameText" Text="Loading..."/>
                    </Grid>
                    <Grid Grid.Row="2" Margin="0,0,0,3">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="100"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Grid.Column="0" Text="IP Address:" FontWeight="SemiBold"/>
                        <TextBlock Grid.Column="1" x:Name="IPAddressText" Text="Loading..."/>
                    </Grid>
                    <Grid Grid.Row="3">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="100"/>
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
                    <TextBlock Grid.Row="0" Text="System Status" FontSize="12" FontWeight="Bold" Margin="0,0,0,5"/>
                    <Grid Grid.Row="1" Margin="0,0,0,5">
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
        <Grid Grid.Row="2" Margin="8">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            
            <Border Grid.Row="1" Background="White" BorderBrush="#E0E0E0" BorderThickness="1" Padding="10">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    
                    <TextBlock Grid.Row="0" Margin="0,0,0,8">
                        <Run Text="Autopilot Profiles" FontSize="12" FontWeight="Bold"/>
                        <Run x:Name="ProfileCountText" Text="" FontSize="10" FontWeight="Normal"/>
                    </TextBlock>
                    
                    <Border Grid.Row="1" Background="#F5F5F5" BorderBrush="#E0E0E0" BorderThickness="1" Padding="8" Margin="0,0,0,8">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            
                            <Grid Grid.Row="0" Margin="0,0,0,8">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock Grid.Column="0" Text="Profile:" FontWeight="SemiBold" VerticalAlignment="Center"/>
                                <ComboBox Grid.Column="1" x:Name="ProfileDropdown" Margin="8,0,0,0" Height="22" Background="White" IsEnabled="False"/>
                            </Grid>
                            
                            <TextBlock Grid.Row="1" Text="Assigned Groups:" FontSize="11" FontWeight="SemiBold" Margin="0,0,0,3"/>
                            <ListBox Grid.Row="2" x:Name="GroupsList" Background="#FAFAFA" BorderBrush="#E0E0E0" Margin="0,0,0,8" Height="60" ScrollViewer.VerticalScrollBarVisibility="Auto" ScrollViewer.HorizontalScrollBarVisibility="Disabled" ScrollViewer.CanContentScroll="True">
                                <ListBox.ItemContainerStyle>
                                    <Style TargetType="ListBoxItem">
                                        <Setter Property="Height" Value="20"/>
                                        <Setter Property="Padding" Value="4,1"/>
                                    </Style>
                                </ListBox.ItemContainerStyle>
                            </ListBox>
                            
                            <Grid Grid.Row="3">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock Grid.Column="0" Text="Group Tag (OrderID):" FontSize="11" FontWeight="SemiBold" VerticalAlignment="Center" Margin="0,0,8,0"/>
                                <TextBlock Grid.Column="1" x:Name="GroupTagText" Text="No profile selected" FontSize="11" Foreground="#0078D4" FontWeight="Bold" VerticalAlignment="Center"/>
                            </Grid>
                        </Grid>
                    </Border>
                    
                    <TextBlock Grid.Row="2" Text="Script Options" FontSize="12" FontWeight="Bold" Margin="0,0,0,8"/>
                    
                    <Border Grid.Row="3" Background="#F5F5F5" BorderBrush="#E0E0E0" BorderThickness="1" Padding="8" Margin="0,0,0,8">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>  
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            
                            <!-- Computer Name Assignment -->
                            <Grid Grid.Row="0" Margin="0,0,0,6">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <CheckBox Grid.Column="0" x:Name="ComputerNameCheckbox" Content="Assign Computer Name:" VerticalAlignment="Center" IsEnabled="False"/>
                                <TextBox Grid.Column="1" x:Name="ComputerNameTextBox" Height="22" Margin="8,0,0,0" VerticalAlignment="Center" IsEnabled="False" MaxLength="15" ToolTip="Enter computer name (4-15 chars, letters/numbers/hyphens only, cannot start/end with hyphen or be all numbers)"/>
                            </Grid>
                            
                            <!-- Group Assignment -->
                            <Grid Grid.Row="1" Margin="0,0,0,6">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <CheckBox Grid.Column="0" x:Name="AssignGroupCheckbox" Content="Assign to Group:" VerticalAlignment="Center" IsEnabled="False"/>
                                <ComboBox Grid.Column="1" x:Name="GroupDropdown" Height="22" Margin="8,0,0,0" VerticalAlignment="Center" IsEnabled="False" IsEditable="True" IsTextSearchEnabled="True" ToolTip="Select an EntraID group (non-dynamic only)" ScrollViewer.VerticalScrollBarVisibility="Auto" ScrollViewer.CanContentScroll="True">
                                    <ComboBox.Resources>
                                        <Style TargetType="ComboBox">
                                            <Setter Property="MaxDropDownHeight" Value="60"/>
                                            <Setter Property="ScrollViewer.VerticalScrollBarVisibility" Value="Auto"/>
                                        </Style>
                                    </ComboBox.Resources>
                                </ComboBox>
                            </Grid>
                            
                            <!-- Script Options -->
                            <CheckBox Grid.Row="2" x:Name="WaitForRegistrationCheckbox" Content="Wait for registration (Profile Assignment)" VerticalAlignment="Center" Margin="0,0,0,3" IsEnabled="False"/>
                            <CheckBox Grid.Row="3" x:Name="RebootCheckbox" Content="Reboot after registration" VerticalAlignment="Center" IsEnabled="False"/>
                        </Grid>
                    </Border>
                </Grid>
            </Border>
        </Grid>
        
        <!-- Footer -->
        <Border Grid.Row="3" Background="White" BorderBrush="#E0E0E0" BorderThickness="0,1,0,0" Padding="8">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                
                <Button Grid.Column="1" x:Name="RegisterDeviceButton" Content="Connect" Width="100" Height="28" Background="#0078D4" Foreground="White" Margin="0,0,8,0" Cursor="Hand" IsEnabled="True" Style="{DynamicResource CustomButton}"/>
                <Button Grid.Column="2" x:Name="CleanupButton" Content="Cleanup" Width="100" Height="28" Background="#FF8C00" Foreground="White" Margin="0,0,8,0" Cursor="Hand" IsEnabled="True" Style="{DynamicResource CustomButton}"/>
                <Button Grid.Column="3" x:Name="RefreshButton" Content="Refresh" Width="100" Height="28" Background="#107C10" Foreground="White" Margin="0,0,8,0" Cursor="Hand" IsEnabled="False" Style="{DynamicResource CustomButton}"/>
                <Button Grid.Column="4" x:Name="ExitButton" Content="Exit" Width="100" Height="28" Background="#D32F2F" Foreground="White" Cursor="Hand" Style="{DynamicResource CustomButton}"/>
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
    $ProfileDropdown = $window.FindName("ProfileDropdown")
    $GroupTagText = $window.FindName("GroupTagText")
    $GroupsList = $window.FindName("GroupsList")
    $WaitForRegistrationCheckbox = $window.FindName("WaitForRegistrationCheckbox")
    $RebootCheckbox = $window.FindName("RebootCheckbox")
    $ComputerNameCheckbox = $window.FindName("ComputerNameCheckbox")
    $ComputerNameTextBox = $window.FindName("ComputerNameTextBox")
    $AssignGroupCheckbox = $window.FindName("AssignGroupCheckbox")
    $GroupDropdown = $window.FindName("GroupDropdown")
    $RegisterDeviceButton = $window.FindName("RegisterDeviceButton")
    $CleanupButton = $window.FindName("CleanupButton")
    $RefreshButton = $window.FindName("RefreshButton")
    $ExitButton = $window.FindName("ExitButton")
    $ProfileCountText = $window.FindName("ProfileCountText")
    
    # Verify critical controls were found
    if ($ComputerNameText -eq $null -or $RegisterDeviceButton -eq $null) {
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
    
    # Helper function to handle Graph API connection
    function Invoke-GraphConnection {
        $window.Dispatcher.Invoke([System.Action]{
            $RegisterDeviceButton.IsEnabled = $false
            $RegisterDeviceButton.Content = "Connecting..."
        })
        
        if (Connect-ToGraphAPI) {
            $GraphStatusIndicator.Fill = "#4CAF50"
            $GraphStatusText.Text = "Graph API: Connected"
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
                # Update profile count text instead of popup
                $ProfileCountText.Text = " ($($profiles.Count) profiles found)"
            }
            else {
                $ProfileCountText.Text = " (no profiles found)"
            }
            
            # Load EntraID groups for assignment
            $entraGroups = Get-EntraIDGroups
            if ($entraGroups.Count -gt 0) {
                foreach ($group in $entraGroups) {
                    $groupItem = New-Object System.Windows.Controls.ComboBoxItem
                    $groupItem.Content = $group.Name
                    $groupItem.Tag = $group.ID
                    [void]$GroupDropdown.Items.Add($groupItem)
                }
            }
            
            # Update button for registration mode
            $window.Dispatcher.Invoke([System.Action]{
                $RegisterDeviceButton.Content = "Register"
                $RegisterDeviceButton.IsEnabled = $false  # Will be enabled when profile is selected
            })
        }
        else {
            $GraphStatusIndicator.Fill = "#D32F2F"
            $GraphStatusText.Text = "Graph API: Connection Failed"
            $window.Dispatcher.Invoke([System.Action]{
                $RegisterDeviceButton.IsEnabled = $true
                $RegisterDeviceButton.Content = "Connect"
            })
            [System.Windows.Forms.MessageBox]::Show("Failed to connect to Graph API. Please try again.", "Connection Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    }
    
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
            
            # Display the first OrderID or combined and select the first item
            if ($orderIDs.Count -gt 0) {
                $GroupTagText.Text = $orderIDs[0]
                $script:selectedGroupTag = $orderIDs[0]
                # Auto-select the first group in the list to show which one is being used
                $GroupsList.SelectedIndex = 0
            }
            else {
                $GroupTagText.Text = "No OrderID found"
                $script:selectedGroupTag = ""
                $GroupsList.SelectedIndex = -1
            }
            
            # Enable checkboxes and register button
            $WaitForRegistrationCheckbox.IsEnabled = $true
            $RebootCheckbox.IsEnabled = $true
            $ComputerNameCheckbox.IsEnabled = $true
            $AssignGroupCheckbox.IsEnabled = $true
            $RegisterDeviceButton.IsEnabled = $true
        }
        else {
            # Disable if no profile selected
            $WaitForRegistrationCheckbox.IsEnabled = $false
            $RebootCheckbox.IsEnabled = $false
            $ComputerNameCheckbox.IsEnabled = $false
            $ComputerNameTextBox.IsEnabled = $false
            $AssignGroupCheckbox.IsEnabled = $false
            $GroupDropdown.IsEnabled = $false
            $RegisterDeviceButton.IsEnabled = $false
            $GroupsList.Items.Clear()
            $GroupsList.SelectedIndex = -1
            $script:selectedGroupTag = ""
        }
    })
    
    # Assigned Groups selection changed - update Group Tag based on selected group
    $GroupsList.Add_SelectionChanged({
        if ($GroupsList.SelectedIndex -ge 0 -and $GroupsList.SelectedItem) {
            $selectedGroupText = $GroupsList.SelectedItem.ToString()
            # Extract OrderID from the selected group text (format: "GroupName (OrderID: 12345)")
            if ($selectedGroupText -match "OrderID:\s*([^)]+)") {
                $extractedOrderID = $matches[1].Trim()
                $GroupTagText.Text = $extractedOrderID
                $script:selectedGroupTag = $extractedOrderID
            }
        }
    })
    
    # Computer Name checkbox event handler
    $ComputerNameCheckbox.Add_Checked({
        $ComputerNameTextBox.IsEnabled = $true
        $ComputerNameTextBox.Focus()
    })
    
    $ComputerNameCheckbox.Add_Unchecked({
        $ComputerNameTextBox.IsEnabled = $false
        $ComputerNameTextBox.Text = ""
    })
    
    # Computer Name text box validation
    # Computer name validation function
    function Test-WindowsComputerName($name) {
        if ([string]::IsNullOrWhiteSpace($name)) { return $false, "Computer name cannot be empty" }
        if ($name.Length -lt 4 -or $name.Length -gt 15) { return $false, "Must be 4-15 characters long" }
        if ($name -notmatch '^[a-zA-Z0-9-]+$') { return $false, "Only letters, numbers, and hyphens allowed" }
        if ($name.StartsWith('-') -or $name.EndsWith('-')) { return $false, "Cannot start or end with hyphen" }
        if ($name -match '^[0-9-]+$') { return $false, "Cannot be all numbers and hyphens" }
        return $true, "Valid computer name"
    }

    $ComputerNameTextBox.Add_TextChanged({
        $text = $ComputerNameTextBox.Text
        if ($text.Length -eq 0) {
            $ComputerNameTextBox.Background = "White"
            $ComputerNameTextBox.ToolTip = "Enter computer name (4-15 chars, letters/numbers/hyphens only, cannot start/end with hyphen or be all numbers)"
        } else {
            $isValid, $message = Test-WindowsComputerName $text
            if (-not $isValid) {
                $ComputerNameTextBox.Background = "#FFEBEE"
                $ComputerNameTextBox.ToolTip = "Invalid: $message"
            } else {
                $ComputerNameTextBox.Background = "#E8F5E8"
                $ComputerNameTextBox.ToolTip = "Valid computer name"
            }
        }
    })
    
    # Assign Group checkbox event handlers
    $AssignGroupCheckbox.Add_Checked({
        $GroupDropdown.IsEnabled = $true
        $GroupDropdown.Focus()
    })
    
    $AssignGroupCheckbox.Add_Unchecked({
        $GroupDropdown.IsEnabled = $false
        $GroupDropdown.SelectedIndex = -1
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
        
        # Update profile count text
        $ProfileCountText.Text = " ($($profiles.Count) profiles found)"
        
        $RefreshButton.Content = "Refresh"
        $RefreshButton.IsEnabled = $true
        [System.Windows.Forms.MessageBox]::Show("Profiles refreshed!", "Refresh Complete", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    })
    
    # Register Device button (handles both connection and registration)
    $RegisterDeviceButton.Add_Click({
        try {
            # Check if we need to connect to Graph API first
            if (-not $global:graphConnected) {
                Invoke-GraphConnection
                return
            }
            
            # Handle device registration
            if ([string]::IsNullOrWhiteSpace($script:selectedGroupTag)) {
                [System.Windows.Forms.MessageBox]::Show("No Group Tag (OrderID) found. Please select a profile with a Group Tag.", "Missing Group Tag", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                return
            }
            
            # Validate computer name if checkbox is checked
            if ($ComputerNameCheckbox.IsChecked) {
                $computerName = $ComputerNameTextBox.Text.Trim()
                $isValid, $message = Test-WindowsComputerName $computerName
                if (-not $isValid) {
                    [System.Windows.Forms.MessageBox]::Show("Computer name validation failed: $message`n`nWindows computer name rules:`n• 4-15 characters long`n• Only letters, numbers, and hyphens`n• Cannot start or end with hyphen`n• Cannot be all numbers", "Invalid Computer Name", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                    $ComputerNameTextBox.Focus()
                    return
                }
            }
            
            # Validate group assignment if checkbox is checked
            if ($AssignGroupCheckbox.IsChecked) {
                if ($GroupDropdown.SelectedIndex -lt 0 -or $GroupDropdown.SelectedItem -eq $null) {
                    [System.Windows.Forms.MessageBox]::Show("Please select a group or uncheck the 'Assign to Group' option.", "Group Selection Required", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                    $GroupDropdown.Focus()
                    return
                }
            }
            
            $window.Dispatcher.Invoke([System.Action]{
                $RegisterDeviceButton.IsEnabled = $false
                $RegisterDeviceButton.Content = "Registering..."
            })
        
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
            
            # Store PowerShell reference at window level for cleanup
            $progressWindow.Tag = @{}
            
            $closeButton.Add_Click({
                try {
                    Write-Host "Close button clicked, attempting to stop processes..." -ForegroundColor Yellow
                    
                    # Stop any running PowerShell processes stored in window tag
                    if ($progressWindow -and $progressWindow.Tag -and $progressWindow.Tag.PowerShell) {
                        try {
                            $progressWindow.Tag.PowerShell.Stop()
                            Write-Host "Stopped PowerShell process" -ForegroundColor Green
                        }
                        catch {
                            Write-Host "Could not stop PowerShell process: $_" -ForegroundColor Yellow
                        }
                    }
                    
                    # Force close the window immediately
                    if ($progressWindow -and -not $progressWindow.Dispatcher.HasShutdownStarted) {
                        $progressWindow.Close()
                        Write-Host "Progress window closed" -ForegroundColor Green
                    }
                }
                catch {
                    Write-Host "Error in close handler: $_" -ForegroundColor Red
                    # Try to hide the window if close fails
                    try {
                        if ($progressWindow) {
                            $progressWindow.Hide()
                        }
                    }
                    catch {
                        Write-Host "Could not hide progress window" -ForegroundColor Red
                    }
                }
            })
            
            # Show progress window (non-blocking to prevent ShowDialog issues)
            $progressWindow.Owner = $window
            try {
                $progressWindow.Show()
                $progressWindow.Activate()
            }
            catch {
                Write-Warning "Could not display progress window: $_"
                [System.Windows.Forms.MessageBox]::Show("Could not display progress window: $_", "Display Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                return
            }
            
            # Helper function to update UI safely on dispatch thread
            $updateUI = {
                param($text)
                $progressWindow.Dispatcher.Invoke([System.Action]{
                    $outputText.AppendText($text)
                    $outputText.ScrollToEnd()
                }, [System.Windows.Threading.DispatcherPriority]::Normal)
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
            
            if ($ComputerNameCheckbox.IsChecked) {
                $assignedComputerName = $ComputerNameTextBox.Text.Trim()
                $params.Add("AssignedComputerName", $assignedComputerName)
            }
            
            if ($AssignGroupCheckbox.IsChecked) {
                $selectedGroupItem = $GroupDropdown.SelectedItem
                if ($selectedGroupItem -and $selectedGroupItem.Content) {
                    $params.Add("AddToGroup", $selectedGroupItem.Content)
                }
            }
            
            # Run Get-WindowsAutopilotinfo and capture output
            try {
                & $updateUI "Starting device registration...`r`n"
                & $updateUI "Group Tag: $($script:selectedGroupTag)`r`n"
                if ($WaitForRegistrationCheckbox.IsChecked) { & $updateUI "Wait for Assignment: Yes`r`n" }
                if ($RebootCheckbox.IsChecked) { & $updateUI "Reboot After: Yes`r`n" }
                if ($ComputerNameCheckbox.IsChecked) { & $updateUI "Assigned Computer Name: $($ComputerNameTextBox.Text.Trim())`r`n" }
                if ($AssignGroupCheckbox.IsChecked -and $GroupDropdown.SelectedItem) { 
                    & $updateUI "Assign to Group: $($GroupDropdown.SelectedItem.Content)`r`n" 
                }
                & $updateUI "`r`n"
            }
            catch {
                Write-Warning "Initial UI update failed: $_"
            }
            
            # Add PowerShell Scripts directory to PATH to ensure Get-WindowsAutopilotinfo is found
            $originalPath = $env:PATH
            try {
                $scriptsPath = "C:\Program Files\WindowsPowerShell\Scripts"
                if ($env:PATH -notlike "*$scriptsPath*") {
                    $env:PATH += ";$scriptsPath"
                    & $updateUI "Added PowerShell Scripts directory to PATH`r`n"
                }
            }
            catch {
                & $updateUI "Warning: Could not modify PATH: $($_.Exception.Message)`r`n"
            }
            
            # Execute Get-WindowsAutopilotinfo with better output capture
            & $updateUI "Executing Get-WindowsAutopilotinfo...`r`n`r`n"
            
            try {
                # Build command arguments
                $cmdArgs = @("-Online", "-GroupTag", "`"$($script:selectedGroupTag)`"")
                if ($WaitForRegistrationCheckbox.IsChecked) { $cmdArgs += "-Assign" }
                if ($RebootCheckbox.IsChecked) { $cmdArgs += "-Reboot" }
                if ($ComputerNameCheckbox.IsChecked) { $cmdArgs += "-AssignedComputerName"; $cmdArgs += "`"$($ComputerNameTextBox.Text.Trim())`"" }
                if ($AssignGroupCheckbox.IsChecked -and $GroupDropdown.SelectedItem) { 
                    $cmdArgs += "-AddToGroup"; $cmdArgs += "`"$($GroupDropdown.SelectedItem.Content)`"" 
                }
                
                $cmdString = "Get-WindowsAutopilotinfo $($cmdArgs -join ' ')"
                & $updateUI "Running command: $cmdString`r`n`r`n"
                
                # Create a runspace for the command to capture output in real-time
                $runspace = [runspacefactory]::CreateRunspace()
                $runspace.Open()
                $runspace.SessionStateProxy.SetVariable("GroupTag", $script:selectedGroupTag)
                $runspace.SessionStateProxy.SetVariable("WaitForAssignment", $WaitForRegistrationCheckbox.IsChecked)
                $runspace.SessionStateProxy.SetVariable("RebootAfter", $RebootCheckbox.IsChecked)
                $runspace.SessionStateProxy.SetVariable("UseComputerName", $ComputerNameCheckbox.IsChecked)
                if ($ComputerNameCheckbox.IsChecked) {
                    $runspace.SessionStateProxy.SetVariable("AssignedComputerName", $ComputerNameTextBox.Text.Trim())
                }
                $runspace.SessionStateProxy.SetVariable("UseGroupAssignment", $AssignGroupCheckbox.IsChecked)
                if ($AssignGroupCheckbox.IsChecked -and $GroupDropdown.SelectedItem) {
                    $runspace.SessionStateProxy.SetVariable("AddToGroupName", $GroupDropdown.SelectedItem.Content)
                }
                
                # Set environment variable to suppress Graph welcome messages
                $runspace.SessionStateProxy.SetVariable("env:POWERSHELL_TELEMETRY_OPTOUT", "1")
                $runspace.SessionStateProxy.SetVariable("env:MSAL_LOG_LEVEL", "None")
                
                $powershell = [powershell]::Create()
                $powershell.Runspace = $runspace
                
                # Store PowerShell reference in window tag for close button access
                $progressWindow.Tag.PowerShell = $powershell
                
                # Add the command with proper parameters
                [void]$powershell.AddScript({
                    # Suppress Graph welcome messages in this runspace
                    $env:POWERSHELL_TELEMETRY_OPTOUT = "1"
                    $env:MSAL_LOG_LEVEL = "None"
                    
                    $params = @{
                        Online = $true
                        GroupTag = $GroupTag
                    }
                    
                    if ($WaitForAssignment) { $params.Add("Assign", $true) }
                    if ($RebootAfter) { $params.Add("Reboot", $true) }
                    if ($UseComputerName -and $AssignedComputerName) { $params.Add("AssignedComputerName", $AssignedComputerName) }
                    if ($UseGroupAssignment -and $AddToGroupName) { $params.Add("AddToGroup", $AddToGroupName) }
                    
                    try {
                        # Enable verbose output to capture progress messages
                        $VerbosePreference = "Continue"
                        $InformationPreference = "Continue"
                        
                        # Run the command with verbose output (Graph connection handled by Get-WindowsAutopilotinfo)
                        Get-WindowsAutopilotinfo @params -Verbose
                    }
                    catch {
                        Write-Error "Error running Get-WindowsAutopilotinfo: $($_.Exception.Message)"
                        throw
                    }
                })
                
                # Execute asynchronously and capture output
                $asyncResult = $powershell.BeginInvoke()
                
                # Monitor progress with real-time output capture
                $timeout = 1800 # 30 minutes timeout
                $start = Get-Date
                $lastOutputCheck = Get-Date
                
                while (-not $asyncResult.IsCompleted) {
                    Start-Sleep -Milliseconds 1000
                    $elapsed = ((Get-Date) - $start).TotalSeconds
                    
                    if ($elapsed -gt $timeout) {
                        & $updateUI "Operation timed out after $timeout seconds`r`n"
                        $powershell.Stop()
                        break
                    }
                    
                    # Check for new output every 2 seconds
                    if (((Get-Date) - $lastOutputCheck).TotalSeconds -gt 2) {
                        $lastOutputCheck = Get-Date
                        
                        # Capture any new verbose output (real-time progress)
                        if ($powershell.Streams.Verbose.Count -gt 0) {
                            $newVerbose = $powershell.Streams.Verbose | Where-Object { $_.Message -ne $null }
                            foreach ($verbose in $newVerbose) {
                                & $updateUI "$($verbose.Message)`r`n"
                            }
                            $powershell.Streams.Verbose.Clear()
                        }
                        
                        # Capture any new information output
                        if ($powershell.Streams.Information.Count -gt 0) {
                            $newInfo = $powershell.Streams.Information | Where-Object { $_.MessageData -ne $null }
                            foreach ($info in $newInfo) {
                                & $updateUI "$($info.MessageData)`r`n"
                            }
                            $powershell.Streams.Information.Clear()
                        }
                        
                        # Capture any new warning output
                        if ($powershell.Streams.Warning.Count -gt 0) {
                            $newWarnings = $powershell.Streams.Warning | Where-Object { $_.Message -ne $null }
                            foreach ($warning in $newWarnings) {
                                & $updateUI "WARNING: $($warning.Message)`r`n"
                            }
                            $powershell.Streams.Warning.Clear()
                        }
                        
                        # Capture any errors immediately
                        if ($powershell.Streams.Error.Count -gt 0) {
                            $newErrors = $powershell.Streams.Error | Where-Object { $_.Exception -ne $null }
                            foreach ($error in $newErrors) {
                                & $updateUI "ERROR: $($error.Exception.Message)`r`n"
                            }
                            $powershell.Streams.Error.Clear()
                        }
                    }
                    
                    # Update progress indicator
                    try {
                        $progressWindow.Dispatcher.Invoke([System.Action]{
                            # Keep the progress bar animated
                        }, [System.Windows.Threading.DispatcherPriority]::Background)
                    }
                    catch {
                        # Ignore dispatcher errors
                    }
                }
                
                # Get the final results
                if ($asyncResult.IsCompleted) {
                    $result = $powershell.EndInvoke($asyncResult)
                    
                    if ($result) {
                        & $updateUI "`r`nFinal command output:`r`n"
                        foreach ($line in $result) {
                            & $updateUI "$line`r`n"
                        }
                    }
                    
                    # Check for any remaining streams
                    if ($powershell.Streams.Error.Count -gt 0) {
                        & $updateUI "`r`nFinal Errors:`r`n"
                        foreach ($error in $powershell.Streams.Error) {
                            & $updateUI "ERROR: $error`r`n"
                        }
                    }
                    
                    if ($powershell.Streams.Warning.Count -gt 0) {
                        & $updateUI "`r`nFinal Warnings:`r`n"
                        foreach ($warning in $powershell.Streams.Warning) {
                            & $updateUI "WARNING: $warning`r`n"
                        }
                    }
                    
                    if ($powershell.Streams.Verbose.Count -gt 0) {
                        & $updateUI "`r`nFinal Verbose Output:`r`n"
                        foreach ($verbose in $powershell.Streams.Verbose) {
                            & $updateUI "VERBOSE: $verbose`r`n"
                        }
                    }
                }
                
                # Cleanup
                $powershell.Dispose()
                $runspace.Close()
                $runspace.Dispose()
                $progressWindow.Tag.PowerShell = $null
                
                & $updateUI "`r`nDevice registration completed!`r`n"
            }
            catch {
                & $updateUI "Execution Error: $($_.Exception.Message)`r`n"
                & $updateUI "Stack Trace: $($_.Exception.StackTrace)`r`n"
            }
            # Stop progress bar and enable close button when done
            try {
                $progressWindow.Dispatcher.Invoke([System.Action]{
                    $regProgress = $progressWindow.FindName("RegProgress")
                    if ($regProgress) {
                        $regProgress.IsIndeterminate = $false
                        $regProgress.Value = 100
                    }
                    $closeButton.IsEnabled = $true
                }, [System.Windows.Threading.DispatcherPriority]::Normal)
            }
            catch {
                # If UI update fails, just continue - window might be closed
                Write-Verbose "Could not update progress bar or enable close button: $_"
            }
            
        }
        catch {
            # Handle any errors in progress window creation or execution
            $errorMessage = "Registration failed: $($_.Exception.Message)"
            Write-Warning $errorMessage
            
            # Try to show error in progress window first, fallback to message box
            try {
                if ($updateUI -ne $null) {
                    & $updateUI "`r`n$errorMessage`r`n"
                }
            }
            catch {
                # If UI update fails, show message box
                [System.Windows.Forms.MessageBox]::Show($errorMessage, "Registration Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
            
            # Stop progress bar and enable close button even on error
            try {
                if ($progressWindow -and -not $progressWindow.Dispatcher.HasShutdownStarted) {
                    $progressWindow.Dispatcher.Invoke([System.Action]{
                        $regProgress = $progressWindow.FindName("RegProgress")
                        if ($regProgress) {
                            $regProgress.IsIndeterminate = $false
                            $regProgress.Foreground = "#D32F2F"  # Red color for error
                            $regProgress.Value = 100  # Show as full red bar for error
                        }
                        $closeButton.IsEnabled = $true
                    }, [System.Windows.Threading.DispatcherPriority]::Normal)
                }
            }
            catch {
                # Ignore if we can't enable the close button - window might be closed
                Write-Verbose "Could not update progress bar or enable close button on error: $_"
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
            
            # Restore button state on main UI thread
            try {
                $window.Dispatcher.Invoke([System.Action]{
                    $RegisterDeviceButton.IsEnabled = $true
                    $RegisterDeviceButton.Content = "Register"
                }, [System.Windows.Threading.DispatcherPriority]::Normal)
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
            $window.Dispatcher.Invoke([System.Action]{
                $RegisterDeviceButton.IsEnabled = $true
                $RegisterDeviceButton.Content = "Register"
            }, [System.Windows.Threading.DispatcherPriority]::Normal)
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
            Write-Host "Starting AGGRESSIVE cleanup process..." -ForegroundColor Yellow
            
            # Step 1: Disconnect from Graph API
            try {
                Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
                Write-Host "Disconnected from Microsoft Graph API" -ForegroundColor Green
            }
            catch { }
            
            # Step 2: Stop ALL PowerShell processes to release module locks
            try {
                Write-Host "Terminating ALL PowerShell processes (except current)..." -ForegroundColor Yellow
                $currentPID = $PID
                Get-Process -Name "powershell*" -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $currentPID } | ForEach-Object {
                    try {
                        $_.Kill()
                        Write-Host "Killed PowerShell process PID: $($_.Id)" -ForegroundColor Green
                    }
                    catch {
                        Write-Host "Could not kill PowerShell process PID: $($_.Id)" -ForegroundColor Yellow
                    }
                }
                Start-Sleep -Seconds 3
            }
            catch {
                Write-Host "Warning: Error terminating PowerShell processes: $($_.Exception.Message)" -ForegroundColor Yellow
            }
            
            # Step 3: Force remove ALL Graph modules from memory
            Write-Host "FORCE removing ALL Graph-related modules from memory..." -ForegroundColor Yellow
            try {
                # Get ALL modules that might be Graph-related
                $allModules = Get-Module | Where-Object { 
                    $_.Name -like "*Graph*" -or 
                    $_.Name -like "*Intune*" -or 
                    $_.Name -like "*Autopilot*" -or
                    $_.Name -eq "WindowsAutopilotIntune"
                }
                
                foreach ($mod in $allModules) {
                    try {
                        Remove-Module -Name $mod.Name -Force -ErrorAction Stop
                        Write-Host "FORCE removed module: $($mod.Name)" -ForegroundColor Green
                    }
                    catch {
                        try {
                            # Try even more aggressive removal
                            [System.Reflection.Assembly]::LoadFrom($mod.Path) | Out-Null
                            Remove-Module -Name $mod.Name -Force -ErrorAction Stop
                            Write-Host "FORCE removed (2nd attempt): $($mod.Name)" -ForegroundColor Green
                        }
                        catch {
                            Write-Host "Could not remove module: $($mod.Name) - $($_.Exception.Message)" -ForegroundColor Red
                        }
                    }
                }
                
                # Force garbage collection multiple times
                for ($i = 1; $i -le 3; $i++) {
                    [System.GC]::Collect()
                    [System.GC]::WaitForPendingFinalizers()
                    [System.GC]::Collect()
                    Start-Sleep -Seconds 1
                    Write-Host "Garbage collection pass $i completed" -ForegroundColor Gray
                }
            }
            catch {
                Write-Host "Warning: Error during aggressive module removal: $($_.Exception.Message)" -ForegroundColor Yellow
            }
            
            # Step 4: AGGRESSIVE module uninstallation
            $modulesToRemove = @(
                "Microsoft.Graph.Authentication",
                "Microsoft.Graph.DeviceManagement", 
                "Microsoft.Graph.Groups",
                "Microsoft.Graph.Intune",
                "Microsoft.Graph.Identity.DirectoryManagement",
                "Microsoft.Graph.Users",
                "Microsoft.Graph.Applications",
                "Microsoft.Graph.Core",
                "Microsoft.Graph.Profile",
                "Microsoft.Graph.Beta.DeviceManagement",
                "Microsoft.Graph.Beta.Identity.DirectoryManagement",
                "Microsoft.Graph.Beta.Groups",
                "Microsoft.Graph",
                "WindowsAutopilotIntune"
            )
            
            Write-Host "Starting AGGRESSIVE uninstallation of $($modulesToRemove.Count) modules..." -ForegroundColor Yellow
            
            foreach ($module in $modulesToRemove) {
                try {
                    $installedVersions = Get-Module -ListAvailable -Name $module -ErrorAction SilentlyContinue
                    if ($installedVersions) {
                        Write-Host "AGGRESSIVE uninstall of $module..." -ForegroundColor Yellow
                        
                        # Method 1: Nuclear uninstall - all versions at once
                        try {
                            Uninstall-Module -Name $module -AllVersions -Force -ErrorAction Stop
                            Write-Host "SUCCESS: Uninstalled all versions of $module" -ForegroundColor Green
                            continue
                        }
                        catch {
                            Write-Host "Method 1 failed for $module, trying individual versions..." -ForegroundColor Yellow
                        }
                        
                        # Method 2: Individual version removal with retries
                        $successCount = 0
                        foreach ($version in $installedVersions) {
                            for ($retry = 1; $retry -le 3; $retry++) {
                                try {
                                    Uninstall-Module -Name $module -RequiredVersion $version.Version -Force -ErrorAction Stop
                                    Write-Host "SUCCESS: Uninstalled $module v$($version.Version) (attempt $retry)" -ForegroundColor Green
                                    $successCount++
                                    break
                                }
                                catch {
                                    Write-Host "Attempt $retry failed for $module v$($version.Version): $($_.Exception.Message)" -ForegroundColor Yellow
                                    if ($retry -eq 3) {
                                        Write-Host "FAILED: Could not uninstall $module v$($version.Version) after 3 attempts" -ForegroundColor Red
                                    }
                                    Start-Sleep -Seconds 1
                                }
                            }
                        }
                        
                        if ($successCount -eq 0) {
                            Write-Host "FAILED: Could not uninstall any version of $module" -ForegroundColor Red
                        } else {
                            Write-Host "PARTIAL SUCCESS: Uninstalled $successCount/$($installedVersions.Count) versions of $module" -ForegroundColor Yellow
                        }
                    }
                    else {
                        Write-Host "$module - not installed (OK)" -ForegroundColor Gray
                    }
                }
                catch {
                    Write-Host "CRITICAL ERROR checking $module : $($_.Exception.Message)" -ForegroundColor Red
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
            # Update the register button text
            $RegisterDeviceButton.Content = "Connect"
            $RegisterDeviceButton.IsEnabled = $true
            $RefreshButton.IsEnabled = $false
            $ProfileDropdown.IsEnabled = $false
            $ProfileDropdown.Items.Clear()
            $ProfileCountText.Text = ""
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
        param($sender, $e)
        try {
            Disconnect-FromGraphAPI | Out-Null
        }
        catch {
            # Ignore disconnect errors when closing
            Write-Verbose "Disconnect error during close: $_"
        }
    })
    
    # Show window
    try {
        $result = $window.ShowDialog()
    }
    catch {
        Write-Warning "Window ShowDialog error: $($_.Exception.Message)"
        # Try to show with Show() instead if ShowDialog fails
        try {
            $window.Show()
            # Keep the application running
            [System.Windows.Threading.Dispatcher]::Run()
        }
        catch {
            Write-Error "Could not display main window: $_"
        }
    }
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
