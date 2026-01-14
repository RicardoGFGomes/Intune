# Certificate to CSP Tool with GUI and Intune Integration
param (
    [string]$CertificatePath,
    [string]$Scope,
    [string]$CertificateType,
    [string]$OutputPath,
    [switch]$AppendToFile
)

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Security

[xml]$xaml = @"
<Window 
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Certificate to CSP Tool with Intune Integration" 
    Height="700" 
    Width="650"
    WindowStartupLocation="CenterScreen"
    ResizeMode="NoResize">
    <Grid Margin="15">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Title -->
        <Label Grid.Row="0" Content="Certificate to CSP Tool" FontSize="20" FontWeight="Bold" HorizontalAlignment="Center" Margin="0,0,0,15"/>

        <!-- Certificate File Selection -->
        <Grid Grid.Row="1" Margin="0,0,0,10">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <Label Grid.Column="0" Content="Certificate File:" VerticalAlignment="Center" FontWeight="Bold" Margin="0,0,10,0"/>
            <TextBox Grid.Column="1" Name="CertificatePathTextBox" Height="25" VerticalAlignment="Center" Margin="0,0,10,0"/>
            <Button Grid.Column="2" Name="BrowseButton" Content="Browse..." Width="80" Height="25"/>
        </Grid>

        <!-- Scope Selection -->
        <Grid Grid.Row="2" Margin="0,0,0,10">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <Label Grid.Column="0" Content="Scope:" VerticalAlignment="Center" FontWeight="Bold" Margin="0,0,10,0"/>
            <ComboBox Grid.Column="1" Name="ScopeComboBox" Height="25" SelectedIndex="1">
                <ComboBoxItem Content="User"/>
                <ComboBoxItem Content="Device"/>
            </ComboBox>
        </Grid>

        <!-- Certificate Type Selection -->
        <Grid Grid.Row="3" Margin="0,0,0,10">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <Label Grid.Column="0" Content="Certificate Type:" VerticalAlignment="Center" FontWeight="Bold" Margin="0,0,10,0"/>
            <ComboBox Grid.Column="1" Name="CertTypeComboBox" Height="25" SelectedIndex="2">
                <ComboBoxItem Content="Root"/>
                <ComboBoxItem Content="CA"/>
                <ComboBoxItem Content="TrustedPublisher"/>
                <ComboBoxItem Content="TrustedPeople"/>
                <ComboBoxItem Content="UntrustedCertificates"/>
            </ComboBox>
        </Grid>

        <!-- This section intentionally left empty - buttons moved to status bar -->
        <Grid Grid.Row="4" Margin="0,0,0,10" Visibility="Collapsed">
        </Grid>

        <!-- Output Options -->
        <Grid Grid.Row="5" Margin="0,0,0,10">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <Label Grid.Column="0" Content="Output:" VerticalAlignment="Center" FontWeight="Bold" Margin="0,0,10,0"/>
            <StackPanel Grid.Column="1" Orientation="Horizontal">
                <RadioButton Name="ConsoleRadioButton" Content="Display in Window" IsChecked="True" VerticalAlignment="Center" Margin="0,0,20,0"/>
                <RadioButton Name="FileRadioButton" Content="Save to File" VerticalAlignment="Center" Margin="0,0,20,0"/>
                <RadioButton Name="IntuneRadioButton" Content="Create in Intune" VerticalAlignment="Center"/>
            </StackPanel>
        </Grid>

        <!-- Output Options Details -->
        <Grid Grid.Row="6" Margin="0,0,0,10">
            <!-- File Output Grid -->
            <Grid Name="FileOutputGrid" Visibility="Collapsed">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                
                <!-- File path selection -->
                <Grid Grid.Row="0" Margin="0,0,0,5">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <Label Grid.Column="0" Content="Output File:" VerticalAlignment="Center" FontWeight="Bold" Margin="0,0,10,0"/>
                    <TextBox Grid.Column="1" Name="OutputPathTextBox" Height="25" VerticalAlignment="Center" Margin="0,0,10,0"/>
                    <Button Grid.Column="2" Name="OutputBrowseButton" Content="Browse..." Width="80" Height="25" Margin="0,0,5,0"/>
                    <Button Grid.Column="3" Name="AddToFileButton" Content="Save" Width="60" Height="25"/>
                </Grid>
                
                <!-- Append checkbox -->
                <CheckBox Grid.Row="1" Name="AppendToFileCheckBox" Content="Append to existing file (unchecked will overwrite)" 
                          IsChecked="True" Margin="20,0,0,0" FontSize="11"/>
            </Grid>

            <!-- Intune Output Grid -->
            <Grid Name="IntuneOutputGrid" Visibility="Collapsed">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                
                <!-- Connection Phase -->
                <Grid Grid.Row="0" Name="ConnectionPhaseGrid" Margin="0,0,0,5">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <Label Grid.Column="0" Content="Graph API:" VerticalAlignment="Center" FontWeight="Bold" Margin="0,0,10,0"/>
                    <Label Grid.Column="1" Name="ConnectionStatusLabel" Content="Not connected" VerticalAlignment="Center" FontStyle="Italic" Foreground="Red"/>
                    <Button Grid.Column="2" Name="ConnectToGraphButton" Content="Connect" Width="140" Height="25"/>
                </Grid>
                
                <!-- Intune Operation Type -->
                <Grid Grid.Row="1" Name="OperationTypeGrid" Margin="0,0,0,10" Visibility="Collapsed">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <Label Grid.Column="0" Content="Operation:" VerticalAlignment="Center" FontWeight="Bold" Margin="0,0,10,0"/>
                    <StackPanel Grid.Column="1" Orientation="Horizontal">
                        <RadioButton Name="CreateNewPolicyRadioButton" Content="Create new Custom policy" IsChecked="True" VerticalAlignment="Center" Margin="0,0,20,0"/>
                        <RadioButton Name="AddToExistingPolicyRadioButton" Content="Add to Existing policy" VerticalAlignment="Center"/>
                    </StackPanel>
                </Grid>
                
                <!-- New Policy Configuration Phase -->
                <Grid Grid.Row="2" Name="NewPolicyConfigurationGrid" Margin="0,0,0,5" Visibility="Collapsed">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    
                    <!-- Policy Name -->
                    <Grid Grid.Row="0" Margin="0,0,0,5">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="150"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Label Grid.Column="0" Content="Policy Name:" VerticalAlignment="Center" FontWeight="Bold" Margin="0,0,10,0"/>
                        <TextBox Grid.Column="1" Name="PolicyNameTextBox" Height="25" VerticalAlignment="Center"/>
                    </Grid>
                    
                    <!-- Configuration Name -->
                    <Grid Grid.Row="1" Margin="0,0,0,5">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="150"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Label Grid.Column="0" Content="OMA-URI Name:" VerticalAlignment="Center" FontWeight="Bold" Margin="0,0,10,0"/>
                        <TextBox Grid.Column="1" Name="ConfigNameTextBox" Height="25" VerticalAlignment="Center"/>
                    </Grid>
                    
                    <!-- Configuration Description -->
                    <Grid Grid.Row="2" Margin="0,0,0,5">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="150"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Label Grid.Column="0" Content="OMA-URI Description:" VerticalAlignment="Center" FontWeight="Bold" Margin="0,0,10,0"/>
                        <TextBox Grid.Column="1" Name="ConfigDescriptionTextBox" Height="25" VerticalAlignment="Center"/>
                    </Grid>
                    
                    <!-- Create Button -->
                    <Grid Grid.Row="3" Margin="0,5,0,0">
                        <Button Name="CreateIntuneConfigButton" Content="Create" Width="60" Height="25" HorizontalAlignment="Right" IsEnabled="False"/>
                    </Grid>
                </Grid>
                
                <!-- Existing Policy Configuration Phase -->
                <Grid Grid.Row="3" Name="ExistingPolicyConfigurationGrid" Margin="0,0,0,5" Visibility="Collapsed">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    
                    <!-- Existing Policies Dropdown -->
                    <Grid Grid.Row="0" Margin="0,0,0,5">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <Label Grid.Column="0" Content="Select Policy:" VerticalAlignment="Center" FontWeight="Bold" Margin="0,0,10,0"/>
                        <ComboBox Grid.Column="1" Name="ExistingPoliciesComboBox" Height="25" VerticalAlignment="Center" Margin="0,0,10,0"/>
                        <Button Grid.Column="2" Name="RefreshPoliciesButton" Content="Refresh" Width="60" Height="25" Margin="0,0,10,0"/>
                        <Button Grid.Column="3" Name="AddToExistingConfigButton" Content="Add" Width="60" Height="25" IsEnabled="False"/>
                    </Grid>
                    
                    <!-- Selected Policy Info -->
                    <TextBox Grid.Row="1" Name="SelectedPolicyInfoTextBox" Height="60" IsReadOnly="True" Background="LightGray" 
                             TextWrapping="Wrap" Margin="0,0,0,5" FontSize="10"/>
                    
                    <!-- OMA-URI Name -->
                    <Grid Grid.Row="2" Margin="0,0,0,5">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="150"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Label Grid.Column="0" Content="OMA-URI Name:" VerticalAlignment="Center" FontWeight="Bold" Margin="0,0,10,0"/>
                        <TextBox Grid.Column="1" Name="ConfigNameTextBoxExisting" Height="25" VerticalAlignment="Center"/>
                    </Grid>
                    
                    <!-- OMA-URI Description -->
                    <Grid Grid.Row="3" Margin="0,0,0,5">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="150"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Label Grid.Column="0" Content="OMA-URI Description:" VerticalAlignment="Center" FontWeight="Bold" Margin="0,0,10,0"/>
                        <TextBox Grid.Column="1" Name="ConfigDescriptionTextBoxExisting" Height="25" VerticalAlignment="Center"/>
                    </Grid>
                </Grid>
            </Grid>
        </Grid>

        <!-- Results Display -->
        <Grid Grid.Row="7" Name="ResultsDisplayGrid" Margin="0,0,0,10">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="5"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            
            <!-- Certificate Details -->
            <GroupBox Grid.Row="0" Header="Certificate Details" FontWeight="Bold">
                <Grid Margin="10">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    
                    <!-- Certificate Path -->
                    <Label Grid.Row="0" Grid.Column="0" Content="Certificate Path:" FontWeight="Bold" VerticalAlignment="Center" Margin="0,0,10,5"/>
                    <TextBox Grid.Row="0" Grid.Column="1" Name="CertPathResultTextBox" Height="25" IsReadOnly="True" Background="LightGray" Margin="0,0,0,5" FontFamily="Consolas" FontSize="10"/>
                    
                    <!-- Certificate Thumbprint -->
                    <Label Grid.Row="1" Grid.Column="0" Content="Certificate Thumbprint:" FontWeight="Bold" VerticalAlignment="Center" Margin="0,0,10,5"/>
                    <TextBox Grid.Row="1" Grid.Column="1" Name="ThumbprintResultTextBox" Height="25" IsReadOnly="True" Background="LightGray" Margin="0,0,0,5" FontFamily="Consolas" FontSize="10"/>
                    
                    <!-- Intune OMA-URI -->
                    <Label Grid.Row="2" Grid.Column="0" Content="Intune OMA-URI:" FontWeight="Bold" VerticalAlignment="Center" Margin="0,0,10,5"/>
                    <TextBox Grid.Row="2" Grid.Column="1" Name="OmaUriResultTextBox" Height="25" IsReadOnly="True" Background="LightGray" Margin="0,0,0,10" FontFamily="Consolas" FontSize="10"/>
                    
                    <!-- Copy Buttons -->
                    <Grid Grid.Row="3" Grid.Column="1" Margin="0,0,0,5">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="5"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="5"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Button Grid.Column="0" Name="CopyPathButton" Content="Copy Path" Height="25" FontSize="10" IsEnabled="False"/>
                        <Button Grid.Column="2" Name="CopyThumbprintButton" Content="Copy Thumbprint" Height="25" FontSize="10" IsEnabled="False"/>
                        <Button Grid.Column="4" Name="CopyOmaUriButton" Content="Copy OMA-URI" Height="25" FontSize="10" IsEnabled="False"/>
                    </Grid>
                </Grid>
            </GroupBox>
            
            <!-- Base64 Encoding -->
            <GroupBox Grid.Row="2" Header="Base64 Certificate Encoding" FontWeight="Bold">
                <Grid Margin="10">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    
                    <ScrollViewer Grid.Row="0">
                        <TextBox Name="Base64TextBox" FontFamily="Consolas" FontSize="10" IsReadOnly="True" 
                                 TextWrapping="Wrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto"
                                 Background="LightGray" MinHeight="100"/>
                    </ScrollViewer>
                    
                    <Button Grid.Row="1" Name="CopyBase64Button" Content="Copy Base64 Encoding" Height="25" FontSize="10" 
                            IsEnabled="False" Margin="0,5,0,0" HorizontalAlignment="Center" Width="150"/>
                </Grid>
            </GroupBox>
        </Grid>
        
        <!-- Action Buttons -->
        <Grid Grid.Row="8" Margin="0,0,0,5">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <Button Grid.Column="1" Name="ClearButton" Content="Clear All" Height="30" FontSize="10" 
                    Width="70" Margin="5,0,0,0"/>
            <Button Grid.Column="2" Name="CopyButton" Content="Copy to Clipboard" Height="30" FontSize="10" 
                    Width="110" Margin="5,0,0,0" IsEnabled="False"/>
            <Button Grid.Column="3" Name="ExitButton" Content="Exit" Height="30" FontSize="10" 
                    Width="60" Margin="5,0,0,0"/>
        </Grid>
        
        <!-- Status Bar -->
        <StatusBar Grid.Row="9" Height="25" Background="LightGray">
            <StatusBarItem>
                <TextBlock Name="StatusLabel" Text="Select a certificate file to begin..." Padding="5,2"/>
            </StatusBarItem>
        </StatusBar>
    </Grid>
</Window>
"@

# Create the window
try {
    $reader = (New-Object System.Xml.XmlNodeReader $xaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)
} catch {
    Write-Error "Failed to create GUI: $($_.Exception.Message)"
    return
}

# Global variables for authentication and Graph connection
$global:accessToken = $null
$global:graphHeaders = $null
$global:policiesLoaded = $false

# Helper function to update status label
function Update-StatusLabel {
    param([string]$Message)
    $statusLabel = $window.FindName("StatusLabel")
    if ($statusLabel) {
        $statusLabel.Text = $Message
    }
}

# Check for existing Graph connection on startup and disconnect it
try {
    $existingContext = Get-MgContext -ErrorAction SilentlyContinue
    if ($existingContext) {
        Write-Host "Found existing Graph connection. Disconnecting..."
        Disconnect-MgGraph -ErrorAction SilentlyContinue
        Write-Host "Disconnected from previous Graph session."
    }
} catch {
    # Ignore any errors during cleanup
}

# Get GUI elements
$certificatePathTextBox = $window.FindName("CertificatePathTextBox")
$browseButton = $window.FindName("BrowseButton")
$scopeComboBox = $window.FindName("ScopeComboBox")
$certTypeComboBox = $window.FindName("CertTypeComboBox")
$clearButton = $window.FindName("ClearButton")
$copyButton = $window.FindName("CopyButton")
$statusLabel = $window.FindName("StatusLabel")
$exitButton = $window.FindName("ExitButton")

# Output mode elements
$consoleRadioButton = $window.FindName("ConsoleRadioButton")
$fileRadioButton = $window.FindName("FileRadioButton")
$intuneRadioButton = $window.FindName("IntuneRadioButton")

# File output elements
$fileOutputGrid = $window.FindName("FileOutputGrid")
$outputPathTextBox = $window.FindName("OutputPathTextBox")
$outputBrowseButton = $window.FindName("OutputBrowseButton")
$addToFileButton = $window.FindName("AddToFileButton")
$appendToFileCheckBox = $window.FindName("AppendToFileCheckBox")

# Intune output elements
$intuneOutputGrid = $window.FindName("IntuneOutputGrid")
$operationTypeGrid = $window.FindName("OperationTypeGrid")
$createNewPolicyRadioButton = $window.FindName("CreateNewPolicyRadioButton")
$addToExistingPolicyRadioButton = $window.FindName("AddToExistingPolicyRadioButton")
$connectionPhaseGrid = $window.FindName("ConnectionPhaseGrid")
$connectionStatusLabel = $window.FindName("ConnectionStatusLabel")
$connectToGraphButton = $window.FindName("ConnectToGraphButton")
$newPolicyConfigurationGrid = $window.FindName("NewPolicyConfigurationGrid")
$policyNameTextBox = $window.FindName("PolicyNameTextBox")
$configNameTextBox = $window.FindName("ConfigNameTextBox")
$configDescriptionTextBox = $window.FindName("ConfigDescriptionTextBox")
$configNameTextBoxExisting = $window.FindName("ConfigNameTextBoxExisting")
$configDescriptionTextBoxExisting = $window.FindName("ConfigDescriptionTextBoxExisting")
$createIntuneConfigButton = $window.FindName("CreateIntuneConfigButton")
$existingPolicyConfigurationGrid = $window.FindName("ExistingPolicyConfigurationGrid")
$existingPoliciesComboBox = $window.FindName("ExistingPoliciesComboBox")
$refreshPoliciesButton = $window.FindName("RefreshPoliciesButton")
$addToExistingConfigButton = $window.FindName("AddToExistingConfigButton")
$selectedPolicyInfoTextBox = $window.FindName("SelectedPolicyInfoTextBox")

# Result elements
$resultsDisplayGrid = $window.FindName("ResultsDisplayGrid")
$certPathResultTextBox = $window.FindName("CertPathResultTextBox")
$thumbprintResultTextBox = $window.FindName("ThumbprintResultTextBox")
$omaUriResultTextBox = $window.FindName("OmaUriResultTextBox")
$copyPathButton = $window.FindName("CopyPathButton")
$copyThumbprintButton = $window.FindName("CopyThumbprintButton")
$copyOmaUriButton = $window.FindName("CopyOmaUriButton")
$base64TextBox = $window.FindName("Base64TextBox")
$copyBase64Button = $window.FindName("CopyBase64Button")

# Global variables to store certificate information
$global:certificateData = @{
    Path = ""
    Thumbprint = ""
    OmaUri = ""
    Base64 = ""
    Issuer = ""
    Subject = ""
    Store = ""
    Scope = ""
}

# Helper function to update button states
function Update-ButtonStates {
    param([bool]$CertificateProcessed)
    
    $copyButton.IsEnabled = $CertificateProcessed
    $copyPathButton.IsEnabled = $CertificateProcessed
    $copyThumbprintButton.IsEnabled = $CertificateProcessed
    $copyOmaUriButton.IsEnabled = $CertificateProcessed
    $copyBase64Button.IsEnabled = $CertificateProcessed
    $createIntuneConfigButton.IsEnabled = $CertificateProcessed -and $global:accessToken
    $addToExistingConfigButton.IsEnabled = $CertificateProcessed -and $global:accessToken -and $existingPoliciesComboBox.SelectedItem
}

# Helper function to enable/disable Intune create/add buttons based on certificate and connection status
function Update-IntuneButtonStates {
    $certificateReady = ![string]::IsNullOrEmpty($global:certificateData.Thumbprint)
    $graphConnected = $global:accessToken -ne $null
    
    $createIntuneConfigButton.IsEnabled = $certificateReady -and $graphConnected
    $addToExistingConfigButton.IsEnabled = $certificateReady -and $graphConnected -and $existingPoliciesComboBox.SelectedItem
}

# Helper function to update connection button state
function Update-ConnectionButtonState {
    $context = Get-MgContext -ErrorAction SilentlyContinue
    if ($global:accessToken -and $context) {
        $connectToGraphButton.Content = "Disconnect"
        $connectionStatusLabel.Content = "Connected"
        $connectionStatusLabel.Foreground = "Green"
    } else {
        $connectToGraphButton.Content = "Connect"
        $connectionStatusLabel.Content = "Not connected"
        $connectionStatusLabel.Foreground = "Red"
        $global:accessToken = $false
    }
}

# Helper function to populate name fields based on certificate
function Update-ConfigurationNames {
    if (![string]::IsNullOrEmpty($global:certificateData.Subject)) {
        # Extract subject CN (Issued To)
        $subjectCN = "Unknown"
        if ($global:certificateData.Subject -match "CN=([^,]+)") {
            $subjectCN = $matches[1]
        }
        
        # Get current certificate type
        $certType = $certTypeComboBox.SelectedItem.Content
        
        # Generate suggested names
        # OMA-URI Name is composed by the Issued To (Subject)
        $suggestedConfigName = $subjectCN
        # OMA-URI Description is composed by the Certificate Type
        $suggestedConfigDescription = $certType
        
        # Update text boxes if they're empty - both new policy and existing policy fields
        if ([string]::IsNullOrWhiteSpace($configNameTextBox.Text)) {
            $configNameTextBox.Text = $suggestedConfigName
        }
        if ([string]::IsNullOrWhiteSpace($configDescriptionTextBox.Text)) {
            $configDescriptionTextBox.Text = $suggestedConfigDescription
        }
        if ([string]::IsNullOrWhiteSpace($configNameTextBoxExisting.Text)) {
            $configNameTextBoxExisting.Text = $suggestedConfigName
        }
        if ([string]::IsNullOrWhiteSpace($configDescriptionTextBoxExisting.Text)) {
            $configDescriptionTextBoxExisting.Text = $suggestedConfigDescription
        }
    }
}

# Output mode change event handlers
$consoleRadioButton.Add_Checked({
    $fileOutputGrid.Visibility = "Collapsed"
    $intuneOutputGrid.Visibility = "Collapsed"
    $resultsDisplayGrid.Visibility = "Visible"
    Update-StatusLabel "Display mode: Certificate details shown"
})

$fileRadioButton.Add_Checked({
    $fileOutputGrid.Visibility = "Visible"
    $intuneOutputGrid.Visibility = "Collapsed"
    $resultsDisplayGrid.Visibility = "Collapsed"
    Update-StatusLabel "File mode: Certificate details hidden"
})

$intuneRadioButton.Add_Checked({
    $fileOutputGrid.Visibility = "Collapsed"
    $intuneOutputGrid.Visibility = "Visible"
    $resultsDisplayGrid.Visibility = "Collapsed"
    Update-StatusLabel "Intune mode: Certificate details hidden - Connect to Graph API first"
})

# Intune operation type change handlers
$createNewPolicyRadioButton.Add_Checked({
    $newPolicyConfigurationGrid.Visibility = "Visible"
    $existingPolicyConfigurationGrid.Visibility = "Collapsed"
})

$addToExistingPolicyRadioButton.Add_Checked({
    $newPolicyConfigurationGrid.Visibility = "Collapsed"
    $existingPolicyConfigurationGrid.Visibility = "Visible"
    
    # Auto-load policies on first use
    if (!$global:policiesLoaded) {
        Get-ExistingPolicies
        $global:policiesLoaded = $true
    }
})

# Function to browse for certificate file
$browseButton.Add_Click({
    $fileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $fileDialog.Filter = "Certificate Files (*.cer;*.crt;*.der)|*.cer;*.crt;*.der|All Files (*.*)|*.*"
    $fileDialog.Title = "Select Certificate File"
    
    if ($fileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $certificatePathTextBox.Text = $fileDialog.FileName
        Update-StatusLabel "Certificate file selected: $(Split-Path $fileDialog.FileName -Leaf)"
        
        # Automatically process the certificate
        $certPath = $fileDialog.FileName
        $scope = $scopeComboBox.SelectedItem.Content
        $certType = $certTypeComboBox.SelectedItem.Content
        
        $result = Process-Certificate -CertPath $certPath -Scope $scope -CertType $certType
        
        if ($result) {
            Update-StatusLabel "Certificate processed successfully: $(Split-Path $certPath -Leaf)"
        }
    }
})

# Function to browse for output file
$outputBrowseButton.Add_Click({
    $fileDialog = New-Object System.Windows.Forms.SaveFileDialog
    $fileDialog.Filter = "Text Files (*.txt)|*.txt|All Files (*.*)|*.*"
    $fileDialog.Title = "Save Output File"
    
    if ($fileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $outputPathTextBox.Text = $fileDialog.FileName
    }
})

# Function to save certificate information to file
$addToFileButton.Add_Click({
    $outputPath = $outputPathTextBox.Text.Trim()
    
    # Validate output path is specified
    if ([string]::IsNullOrEmpty($outputPath)) {
        [System.Windows.MessageBox]::Show("Please select an output file first.", "No Output File", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }
    
    # Validate certificate has been processed
    if ([string]::IsNullOrEmpty($global:certificateData.Thumbprint)) {
        [System.Windows.MessageBox]::Show("Please select and process a certificate first.", "No Certificate", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }
    
    try {
        # Create the same content as "Copy to Clipboard"
        $allInfo = @"
Certificate Path: $($global:certificateData.Path)
Certificate Thumbprint: $($global:certificateData.Thumbprint)
Intune OMA-URI: $($global:certificateData.OmaUri)
Base64 Encoding:
$($global:certificateData.Base64)
"@
        
        # Check if append mode is enabled
        if ($appendToFileCheckBox.IsChecked -and (Test-Path $outputPath)) {
            # Append to existing file with a separator
            $separator = "`r`n`r`n" + ("=" * 80) + "`r`n`r`n"
            Add-Content -Path $outputPath -Value ($separator + $allInfo) -Encoding ASCII
            Update-StatusLabel "Certificate information appended to file: $outputPath"
        } else {
            # Overwrite or create new file with ASCII encoding
            $allInfo | Out-File -FilePath $outputPath -Encoding ASCII -Force
            Update-StatusLabel "Certificate information saved to file: $outputPath"
        }
        
        [System.Windows.MessageBox]::Show("Certificate information saved successfully!", "Success", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
    catch {
        Update-StatusLabel "Error saving to file: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show("Failed to save to file: $($_.Exception.Message)", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    }
})

# Function to copy text to clipboard
function Copy-ToClipboard {
    param([string]$Text)
    try {
        [System.Windows.Clipboard]::SetText($Text)
        Update-StatusLabel "Copied to clipboard!"
    } catch {
        Update-StatusLabel "Failed to copy to clipboard: $($_.Exception.Message)"
    }
}

# Copy button event handlers
$copyPathButton.Add_Click({ Copy-ToClipboard $global:certificateData.Path })
$copyThumbprintButton.Add_Click({ Copy-ToClipboard $global:certificateData.Thumbprint })
$copyOmaUriButton.Add_Click({ Copy-ToClipboard $global:certificateData.OmaUri })
$copyBase64Button.Add_Click({ Copy-ToClipboard $global:certificateData.Base64 })

$copyButton.Add_Click({
    $allInfo = @"
Certificate Path: $($global:certificateData.Path)
Certificate Thumbprint: $($global:certificateData.Thumbprint)
Intune OMA-URI: $($global:certificateData.OmaUri)
Base64 Encoding:
$($global:certificateData.Base64)
"@
    Copy-ToClipboard $allInfo
})

# Graph API Disconnect Function
function Disconnect-FromGraphAPI {
    try {
        Update-StatusLabel "Disconnecting from Graph API..."
        $connectToGraphButton.IsEnabled = $false
        
        # Disconnect from Graph
        Disconnect-MgGraph -ErrorAction SilentlyContinue
        
        # Reset global token tracking
        $global:accessToken = $false
        
        # Update UI elements
        $connectionStatusLabel.Content = "Not connected"
        $connectionStatusLabel.Foreground = "Red"
        $operationTypeGrid.Visibility = "Collapsed"
        $newPolicyConfigurationGrid.Visibility = "Collapsed"
        $existingPolicyConfigurationGrid.Visibility = "Collapsed"
        
        # Reset button states
        Update-IntuneButtonStates
        
        # Update button text and enable it
        $connectToGraphButton.Content = "Connect"
        $connectToGraphButton.IsEnabled = $true
        
        Update-StatusLabel "Successfully disconnected from Graph API"
        return $true
    }
    catch {
        Update-StatusLabel "Error disconnecting from Graph API: $($_.Exception.Message)"
        $connectToGraphButton.IsEnabled = $true
        return $false
    }
}

# Graph API Authentication Function
function Connect-ToGraphAPI {
    param([string]$TenantId = "common")
    
    try {
        Update-StatusLabel "Connecting to Graph API..."
        $connectToGraphButton.IsEnabled = $false
        
        # Check and install required modules with progress indication
        $requiredModules = @("Microsoft.Graph.Authentication", "Microsoft.Graph.DeviceManagement")
        foreach ($module in $requiredModules) {
            if (!(Get-Module -ListAvailable -Name $module)) {
                Update-StatusLabel "Installing module: $module..."
                try {
                    Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser -Repository PSGallery
                } catch {
                    Update-StatusLabel "Failed to install $module. Trying to continue..."
                }
            }
            try {
                Import-Module $module -Force -ErrorAction SilentlyContinue
            } catch {
                # Continue if import fails - might still work
            }
        }
        
        Update-StatusLabel "Authenticating with Microsoft Graph..."
        
        # Connect to Graph with Device Management permissions
        Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All" -NoWelcome -ErrorAction Stop
        
        # Check if connection was successful
        $context = Get-MgContext
        if ($context) {
            $global:accessToken = $true  # Simplified token tracking
            
            $connectionStatusLabel.Content = "Connected"
            $connectionStatusLabel.Foreground = "Green"
            $operationTypeGrid.Visibility = "Visible"
            $newPolicyConfigurationGrid.Visibility = "Visible"
            Update-StatusLabel "Successfully connected to Graph API - Select operation type"
            
            # Update button states
            Update-IntuneButtonStates
            
            # Update button text and enable it
            $connectToGraphButton.Content = "Disconnect"
            $connectToGraphButton.IsEnabled = $true
            return $true
        } else {
            throw "Failed to establish Graph context"
        }
    }
    catch {
        $connectionStatusLabel.Content = "Connection failed"
        $connectionStatusLabel.Foreground = "Red"
        Update-StatusLabel "Graph API connection failed: $($_.Exception.Message)"
        $connectToGraphButton.Content = "Connect"
        $connectToGraphButton.IsEnabled = $true
        return $false
    }
}

# Connect/Disconnect to Graph button event (toggle functionality)
$connectToGraphButton.Add_Click({
    # Check current connection status
    if ($global:accessToken -and (Get-MgContext)) {
        # Currently connected, so disconnect
        Disconnect-FromGraphAPI
    } else {
        # Not connected, so connect
        Connect-ToGraphAPI
    }
})

# Function to get existing custom configuration policies
function Get-ExistingPolicies {
    try {
        if (!$global:accessToken) {
            Update-StatusLabel "Please connect to Graph API first"
            return
        }
        
        Update-StatusLabel "Retrieving existing policies..."
        
        # Get all device configurations without filter to avoid BadRequest
        $policies = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations" -ErrorAction Stop
        
        $existingPoliciesComboBox.Items.Clear()
        if ($policies.value -and $policies.value.Count -gt 0) {
            Write-Host "Total policies found: $($policies.value.Count)"
            
            # Debug: Show first policy structure
            $firstPolicy = $policies.value[0]
            Write-Host "First policy properties:"
            $firstPolicy.PSObject.Properties | ForEach-Object { Write-Host "  $($_.Name): $($_.Value)" }
            
            # Try different ways to access the type property
            $customPolicies = $policies.value | Where-Object { 
                $odataType = $_."@odata.type"
                if (!$odataType) { $odataType = $_.AdditionalProperties."@odata.type" }
                if (!$odataType) { $odataType = $_."odata.type" }
                
                Write-Host "Policy '$($_.displayName)' has type: '$odataType'"
                
                $odataType -eq "microsoft.graph.windows10CustomConfiguration" -or
                $odataType -eq "#microsoft.graph.windows10CustomConfiguration"
            }
            
            Write-Host "Windows 10 custom configuration policies found: $($customPolicies.Count)"
            
            if ($customPolicies.Count -gt 0) {
                foreach ($policy in $customPolicies) {
                    $comboBoxItem = New-Object System.Windows.Controls.ComboBoxItem
                    $comboBoxItem.Content = $policy.displayName
                    $comboBoxItem.Tag = $policy
                    $existingPoliciesComboBox.Items.Add($comboBoxItem)
                    Write-Host "Added policy: $($policy.displayName)"
                }
                Update-StatusLabel "Found $($customPolicies.Count) existing custom configuration policies"
            } else {
                Update-StatusLabel "No Windows 10 custom configuration policies found"
            }
        } else {
            Update-StatusLabel "No device configuration policies found"
        }
    }
    catch {
        Update-StatusLabel "Failed to retrieve policies: $($_.Exception.Message)"
        Write-Host "Error details: $($_.Exception.Message)"
        Write-Host "Full error: $($_.Exception)"
    }
}

# Refresh policies button event
$refreshPoliciesButton.Add_Click({
    Get-ExistingPolicies
})

# Existing policies selection change event
$existingPoliciesComboBox.Add_SelectionChanged({
    if ($existingPoliciesComboBox.SelectedItem) {
        $selectedPolicy = $existingPoliciesComboBox.SelectedItem.Tag
        $selectedPolicyInfoTextBox.Text = "Policy: $($selectedPolicy.displayName)`nDescription: $($selectedPolicy.description)`nCreated: $($selectedPolicy.createdDateTime)"
        Update-IntuneButtonStates
    }
})

# Function to create OMA-URI configuration
function New-IntuneCustomConfiguration {
    param(
        [string]$PolicyName,
        [string]$ConfigName,
        [string]$ConfigDescription,
        [string]$OmaUri,
        [string]$Base64Value
    )
    
    try {
        Update-StatusLabel "Creating Intune configuration..."
        
        $omaSettings = @(
            @{
                "@odata.type" = "microsoft.graph.omaSettingBase64"
                displayName = $ConfigName
                description = $ConfigDescription
                omaUri = $OmaUri
                value = $Base64Value
            }
        )
        
        $deviceConfiguration = @{
            "@odata.type" = "microsoft.graph.windows10CustomConfiguration"
            displayName = $PolicyName
            description = "Custom Windows 10 configuration policy created by Certificate to CSP Tool"
            omaSettings = $omaSettings
        }
        
        $jsonBody = $deviceConfiguration | ConvertTo-Json -Depth 10
        
        $response = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations" -Body $jsonBody
        
        Update-StatusLabel "Successfully created Intune configuration policy: $PolicyName"
        return $response
    }
    catch {
        Update-StatusLabel "Failed to create Intune configuration: $($_.Exception.Message)"
        return $null
    }
}

# Function to add to existing configuration
function Add-ToExistingConfiguration {
    param(
        [object]$ExistingPolicy,
        [string]$ConfigName,
        [string]$ConfigDescription,
        [string]$OmaUri,
        [string]$Base64Value
    )
    
    try {
        Update-StatusLabel "Adding to existing configuration..."
        Write-Host "Starting to add configuration to policy: $($ExistingPolicy.displayName)"
        
        # Get current policy details
        $currentPolicy = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations/$($ExistingPolicy.id)"
        Write-Host "Retrieved current policy. Existing OMA settings count: $($currentPolicy.omaSettings.Count)"
        
        # Check for duplicate OMA URIs
        $existingOmaUris = @()
        if ($currentPolicy.omaSettings) {
            $existingOmaUris = $currentPolicy.omaSettings | ForEach-Object { $_.omaUri }
            Write-Host "Existing OMA URIs: $($existingOmaUris -join ', ')"
            
            if ($existingOmaUris -contains $OmaUri) {
                Update-StatusLabel "Error: OMA URI already exists in policy"
                Write-Host "Error: OMA URI '$OmaUri' already exists in the policy"
                return $null
            }
        }
        
        # Add new OMA setting
        $newOmaSetting = @{
            "@odata.type" = "microsoft.graph.omaSettingBase64"
            displayName = $ConfigName
            description = $ConfigDescription
            omaUri = $OmaUri
            value = $Base64Value
        }
        Write-Host "Created new OMA setting with URI: $OmaUri"
        Write-Host "New OMA setting display name: $ConfigName"
        Write-Host "Base64 value length: $($Base64Value.Length) characters"
        
        # Create updated OMA settings array - preserve ALL existing settings
        $updatedOmaSettings = @()
        $existingSettingsCount = 0
        
        if ($currentPolicy.omaSettings -and $currentPolicy.omaSettings.Count -gt 0) {
            # Preserve ALL existing settings without any filtering
            foreach ($setting in $currentPolicy.omaSettings) {
                # Use the original setting object directly - no filtering at all
                $updatedOmaSettings += $setting
                $existingSettingsCount++
                Write-Host "Preserved existing OMA setting: $($setting.displayName) - URI: $($setting.omaUri) - Value length: $($setting.value.Length)"
            }
            Write-Host "Total existing settings preserved: $existingSettingsCount"
        }
        
        $updatedOmaSettings += $newOmaSetting
        Write-Host "Total OMA settings after adding new one: $($updatedOmaSettings.Count)"
        
        # Debug: Show all settings that will be sent
        Write-Host "Settings to be sent in update:"
        for ($i = 0; $i -lt $updatedOmaSettings.Count; $i++) {
            Write-Host "  Setting $($i + 1): $($updatedOmaSettings[$i].displayName) - URI: $($updatedOmaSettings[$i].omaUri)"
        }
        
        # Create update payload with required properties for PATCH
        $updatePayload = @{
            "@odata.type" = "microsoft.graph.windows10CustomConfiguration"
            omaSettings = $updatedOmaSettings
        }
        
        $jsonBody = $updatePayload | ConvertTo-Json -Depth 10
        Write-Host "Complete JSON payload for PATCH:"
        Write-Host "=================================="
        Write-Host $jsonBody
        Write-Host "=================================="
        Write-Host "JSON length: $($jsonBody.Length) characters"
        
        # Validate JSON structure before sending
        try {
            $testParse = $jsonBody | ConvertFrom-Json
            Write-Host "JSON validation successful"
        } catch {
            Write-Host "JSON validation failed: $($_.Exception.Message)"
            return $null
        }
        
        # Use PATCH with @odata.type included
        Write-Host "Attempting PATCH with @odata.type..."
        $response = Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations/$($ExistingPolicy.id)" -Body $jsonBody
        
        Update-StatusLabel "Successfully added configuration to existing policy: $($ExistingPolicy.displayName)"
        Write-Host "Successfully updated policy using PATCH method"
        return $response
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Host "PATCH update failed: $errorMessage"
        
        # If the update failed and there were corrupted settings, try creating a new policy
        if ($corruptedSettings -gt 0) {
            Update-StatusLabel "Update failed due to corrupted data. Creating new policy..."
            Write-Host "Update failed, likely due to corrupted settings. Creating a new policy instead."
            
            # Generate a new policy name, avoiding duplicate "- Fixed" suffixes
            $newPolicyName = $ExistingPolicy.displayName
            if (-not $newPolicyName.EndsWith("- Fixed")) {
                $newPolicyName += " - Fixed"
            } else {
                # If it already ends with "- Fixed", append a number
                $counter = 2
                $baseName = $newPolicyName -replace " - Fixed$", ""
                do {
                    $newPolicyName = "$baseName - Fixed $counter"
                    $counter++
                    
                    # Check if this name already exists (simplified check)
                    $existingCheck = $existingPoliciesComboBox.Items | Where-Object { $_.Content -eq $newPolicyName }
                } while ($existingCheck)
            }
            
            # Use the New-IntuneCustomConfiguration function instead
            $result = New-IntuneCustomConfiguration -PolicyName $newPolicyName -ConfigName $ConfigName -ConfigDescription $ConfigDescription -OmaUri $OmaUri -Base64Value $Base64Value
            
            if ($result) {
                Update-StatusLabel "Created new policy '$newPolicyName' due to update failure"
                Write-Host "Successfully created new policy: $newPolicyName"
                return $result
            } else {
                Update-StatusLabel "Failed to create fallback policy"
                Write-Host "Failed to create fallback policy as well"
            }
        }
        
        # If fallback also fails or no corrupted settings, show the original error
        Update-StatusLabel "Failed to add to existing configuration: $errorMessage"
        Write-Host "Error details: $errorMessage"
        Write-Host "Full error: $($_.Exception)"
        
        # Enhanced error handling to get actual API response
        try {
            if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) {
                $response = $_.Exception.Response
                Write-Host "Response Status Code: $($response.StatusCode)"
                Write-Host "Response Status Description: $($response.StatusDescription)"
                
                # Try to read response stream
                if ($response.Content) {
                    $responseContent = $response.Content.ReadAsStringAsync().Result
                    Write-Host "API Response Content: $responseContent"
                    
                    # Try to parse as JSON for detailed error
                    try {
                        $errorDetails = $responseContent | ConvertFrom-Json
                        if ($errorDetails.error) {
                            Write-Host "Error Code: $($errorDetails.error.code)"
                            Write-Host "Error Message: $($errorDetails.error.message)"
                            if ($errorDetails.error.details) {
                                Write-Host "Error Details: $($errorDetails.error.details | ConvertTo-Json -Depth 5)"
                            }
                        }
                    } catch {
                        Write-Host "Could not parse error response as JSON: $_"
                    }
                }
            } elseif ($_.ErrorDetails) {
                Write-Host "ErrorDetails: $($_.ErrorDetails.Message)"
            }
        } catch {
            Write-Host "Could not extract detailed error information: $_"
        }
        
        return $null
    }
}

# Create Intune configuration button event
$createIntuneConfigButton.Add_Click({
    if ([string]::IsNullOrWhiteSpace($policyNameTextBox.Text)) {
        [System.Windows.MessageBox]::Show("Please enter a policy name", "Missing Information", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }
    
    if ([string]::IsNullOrWhiteSpace($configNameTextBox.Text)) {
        [System.Windows.MessageBox]::Show("Please enter a configuration name", "Missing Information", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }
    
    $result = New-IntuneCustomConfiguration -PolicyName $policyNameTextBox.Text -ConfigName $configNameTextBox.Text -ConfigDescription $configDescriptionTextBox.Text -OmaUri $global:certificateData.OmaUri -Base64Value $global:certificateData.Base64
    
    if ($result) {
        [System.Windows.MessageBox]::Show("Successfully created Intune configuration policy!", "Success", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
})

# Add to existing configuration button event
$addToExistingConfigButton.Add_Click({
    if (!$existingPoliciesComboBox.SelectedItem) {
        [System.Windows.MessageBox]::Show("Please select an existing policy", "No Policy Selected", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }
    
    if ([string]::IsNullOrWhiteSpace($configNameTextBoxExisting.Text)) {
        [System.Windows.MessageBox]::Show("Please enter a configuration name", "Missing Information", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }
    
    $selectedPolicy = $existingPoliciesComboBox.SelectedItem.Tag
    $result = Add-ToExistingConfiguration -ExistingPolicy $selectedPolicy -ConfigName $configNameTextBoxExisting.Text -ConfigDescription $configDescriptionTextBoxExisting.Text -OmaUri $global:certificateData.OmaUri -Base64Value $global:certificateData.Base64
    
    if ($result) {
        [System.Windows.MessageBox]::Show("Successfully added configuration to existing policy!", "Success", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    }
})

# Main certificate processing function
function Process-Certificate {
    param(
        [string]$CertPath,
        [string]$Scope,
        [string]$CertType
    )
    
    try {
        if (![System.IO.File]::Exists($CertPath)) {
            throw "Certificate file not found: $CertPath"
        }
        
        # Load the certificate
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertPath)
        
        # Get certificate details
        $thumbprint = $cert.Thumbprint
        $issuer = $cert.Issuer
        $subject = $cert.Subject
        
        # Read certificate as base64
        $certBytes = [System.IO.File]::ReadAllBytes($CertPath)
        $base64Cert = [System.Convert]::ToBase64String($certBytes)
        
        # Generate OMA-URI based on scope and certificate type
        $scopePath = if ($Scope -eq "User") { "User" } else { "Device" }
        $certStore = switch ($CertType) {
            "Root" { "Root" }
            "CA" { "CA" }
            "TrustedPublisher" { "TrustedPublisher" }
            "TrustedPeople" { "TrustedPeople" }
            "UntrustedCertificates" { "UntrustedCertificates" }
            default { "TrustedPublisher" }
        }
        
        $omaUri = "./$scopePath/Vendor/MSFT/RootCATrustedCertificates/$certStore/$thumbprint/EncodedCertificate"
        
        # Store in global variable
        $global:certificateData = @{
            Path = $CertPath
            Thumbprint = $thumbprint
            OmaUri = $omaUri
            Base64 = $base64Cert
            Issuer = $issuer
            Subject = $subject
            Store = $certStore
            Scope = $Scope
        }
        
        # Update UI elements
        $certPathResultTextBox.Text = $CertPath
        $thumbprintResultTextBox.Text = $thumbprint
        $omaUriResultTextBox.Text = $omaUri
        $base64TextBox.Text = $base64Cert
        
        # Update configuration names
        Update-ConfigurationNames
        
        # Enable copy buttons
        Update-ButtonStates $true
        
        Update-StatusLabel "Certificate processed successfully"
        
        return @{
            Path = $CertPath
            Thumbprint = $thumbprint
            OmaUri = $omaUri
            Base64 = $base64Cert
            Issuer = $issuer
            Subject = $subject
        }
    }
    catch {
        Update-StatusLabel "Error processing certificate: $($_.Exception.Message)"
        # Clear results on error
        $certPathResultTextBox.Text = ""
        $thumbprintResultTextBox.Text = ""
        $omaUriResultTextBox.Text = ""
        $base64TextBox.Text = ""
        Update-ButtonStates $false
        return $null
    }
}

# Certificate type change event handler
$certTypeComboBox.Add_SelectionChanged({
    # Only re-process if a certificate is already loaded
    $certPath = $certificatePathTextBox.Text.Trim()
    
    if (![string]::IsNullOrEmpty($certPath) -and (Test-Path $certPath)) {
        $scope = $scopeComboBox.SelectedItem.Content
        $certType = $certTypeComboBox.SelectedItem.Content
        
        # Re-process the certificate with the new type
        $result = Process-Certificate -CertPath $certPath -Scope $scope -CertType $certType
        
        if ($result) {
            Update-StatusLabel "Certificate re-processed with new type: $certType"
        }
    }
})

# Scope change event handler
$scopeComboBox.Add_SelectionChanged({
    # Only re-process if a certificate is already loaded
    $certPath = $certificatePathTextBox.Text.Trim()
    
    if (![string]::IsNullOrEmpty($certPath) -and (Test-Path $certPath)) {
        $scope = $scopeComboBox.SelectedItem.Content
        $certType = $certTypeComboBox.SelectedItem.Content
        
        # Re-process the certificate with the new scope
        $result = Process-Certificate -CertPath $certPath -Scope $scope -CertType $certType
        
        if ($result) {
            Update-StatusLabel "Certificate re-processed with new scope: $scope"
        }
    }
})

# Clear button event
$clearButton.Add_Click({
    # Clear input fields
    $certificatePathTextBox.Text = ""
    $outputPathTextBox.Text = ""
    $policyNameTextBox.Text = ""
    $configNameTextBox.Text = ""
    $configDescriptionTextBox.Text = ""
    
    # Clear result fields
    $certPathResultTextBox.Text = ""
    $thumbprintResultTextBox.Text = ""
    $omaUriResultTextBox.Text = ""
    $base64TextBox.Text = ""
    $selectedPolicyInfoTextBox.Text = ""
    
    # Clear selection
    $existingPoliciesComboBox.SelectedItem = $null
    
    # Reset to defaults
    $scopeComboBox.SelectedIndex = 1
    $certTypeComboBox.SelectedIndex = 2
    $consoleRadioButton.IsChecked = $true
    $createNewPolicyRadioButton.IsChecked = $true
    $appendToFileCheckBox.IsChecked = $true
    
    # Clear global data
    $global:certificateData = @{
        Path = ""
        Thumbprint = ""
        OmaUri = ""
        Base64 = ""
        Issuer = ""
        Subject = ""
        Store = ""
        Scope = ""
    }
    
    # Update button states
    Update-ButtonStates $false
    
    Update-StatusLabel "All fields cleared"
})

# Exit button event
$exitButton.Add_Click({
    # Disconnect from Graph before closing
    try {
        $context = Get-MgContext -ErrorAction SilentlyContinue
        if ($context) {
            Update-StatusLabel "Disconnecting from Graph API..."
            Disconnect-MgGraph -ErrorAction SilentlyContinue
            Update-StatusLabel "Disconnected from Graph API. Closing..."
        }
    } catch {
        # Continue with close even if disconnect fails
    }
    
    $window.Close()
})

# Window closing event
$window.Add_Closing({
    # Disconnect from Graph if connected
    try {
        $context = Get-MgContext -ErrorAction SilentlyContinue
        if ($context) {
            Write-Host "Disconnecting from Graph API..."
            Disconnect-MgGraph -ErrorAction SilentlyContinue
            Write-Host "Successfully disconnected from Graph API."
        }
    } catch {
        # Ignore disconnection errors but log them
        Write-Host "Note: Graph disconnection completed with warnings."
    }
    
    # Clear global variables
    $global:accessToken = $null
    $global:graphHeaders = $null
})

# Initialize button states
Update-ButtonStates $false

# Set initial state - show results display for console mode (default)
$resultsDisplayGrid.Visibility = "Visible"

# If command line parameters are provided, process them
if ($CertificatePath) {
    $certificatePathTextBox.Text = $CertificatePath
    
    if ($Scope) {
        $scopeIndex = if ($Scope -eq "User") { 0 } else { 1 }
        $scopeComboBox.SelectedIndex = $scopeIndex
    }
    
    if ($CertificateType) {
        $certTypeIndex = switch ($CertificateType) {
            "Root" { 0 }
            "CA" { 1 }
            "TrustedPublisher" { 2 }
            "TrustedPeople" { 3 }
            "UntrustedCertificates" { 4 }
            default { 2 }
        }
        $certTypeComboBox.SelectedIndex = $certTypeIndex
    }
    
    if ($OutputPath) {
        $outputPathTextBox.Text = $OutputPath
        $fileRadioButton.IsChecked = $true
        $appendToFileCheckBox.IsChecked = -not $AppendToFile.IsPresent
    }
    
    # Auto-process if all required parameters are provided
    if (![string]::IsNullOrEmpty($certificatePathTextBox.Text)) {
        $scope = $scopeComboBox.SelectedItem.Content
        $certType = $certTypeComboBox.SelectedItem.Content
        Process-Certificate -CertPath $certificatePathTextBox.Text -Scope $scope -CertType $certType
    }
}

# Initialize UI state
Update-ConnectionButtonState

# Show the window
$window.ShowDialog()