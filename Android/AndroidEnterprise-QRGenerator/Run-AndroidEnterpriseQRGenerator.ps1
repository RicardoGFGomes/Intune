# Advanced QR generator using QRCodeGenerator PowerShell module

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing

# Check if QRCodeGenerator module is installed
if (-not (Get-Module -ListAvailable -Name QRCodeGenerator)) {
    Write-Host "Installing QRCodeGenerator module..." -ForegroundColor Yellow
    try {
        Install-Module -Name QRCodeGenerator -Force -Scope CurrentUser
        Import-Module QRCodeGenerator
    } catch {
        Write-Warning "Could not install QRCodeGenerator module. Please install it manually: Install-Module QRCodeGenerator"
    }
} else {
    Import-Module QRCodeGenerator -ErrorAction SilentlyContinue
}

function New-QRCodeAdvanced {
    param([string]$Text, [string]$OutputPath)
    
    if (Get-Command -Name New-QRCodeText -ErrorAction SilentlyContinue) {
        # Use QRCodeGenerator module
        New-QRCodeText -Text $Text -OutPath $OutputPath
        return $true
    } else {
        throw "QRCodeGenerator module is required. Please install it using: Install-Module QRCodeGenerator"
    }
}

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Android Enterprise QR Code Generator" Height="780" Width="500" ResizeMode="NoResize" WindowStartupLocation="CenterScreen">
    <Grid Margin="12">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>

        <TextBlock Grid.Row="0" Grid.ColumnSpan="3" FontWeight="Bold" FontSize="14" Margin="0,0,0,10" Text="Android Enterprise Enrollment Configuration"/>
        
        <TextBlock Grid.Row="1" Grid.Column="0" Margin="0,0,8,8" VerticalAlignment="Center" Text="Enrollment Token:"/>
        <TextBox x:Name="EnrollmentTokenInput" Grid.Row="1" Grid.Column="1" Grid.ColumnSpan="2" Margin="0,0,0,8" TextWrapping="Wrap" Height="40" VerticalScrollBarVisibility="Auto"/>

        <TextBlock Grid.Row="2" Grid.Column="0" Margin="0,0,8,8" VerticalAlignment="Center" Text="WiFi SSID:"/>
        <TextBox x:Name="WifiSsidInput" Grid.Row="2" Grid.Column="1" Grid.ColumnSpan="2" Margin="0,0,0,8"/>

        <TextBlock Grid.Row="3" Grid.Column="0" Margin="0,0,8,8" VerticalAlignment="Center" Text="WiFi Password:"/>
        <PasswordBox x:Name="WifiPasswordInput" Grid.Row="3" Grid.Column="1" Grid.ColumnSpan="2" Margin="0,0,0,8"/>

        <TextBlock Grid.Row="4" Grid.Column="0" Margin="0,0,8,8" VerticalAlignment="Center" Text="Security Type:"/>
        <ComboBox x:Name="SecurityTypeCombo" Grid.Row="4" Grid.Column="1" Grid.ColumnSpan="2" Margin="0,0,0,8">
            <ComboBoxItem Content="None"/>
            <ComboBoxItem Content="WEP"/>
            <ComboBoxItem Content="WPA" IsSelected="True"/>
            <ComboBoxItem Content="EAP"/>
        </ComboBox>

        <CheckBox x:Name="HiddenWifiCheck" Grid.Row="5" Grid.Column="1" Grid.ColumnSpan="2" Margin="0,0,0,8" Content="Hidden WiFi"/>
        <CheckBox x:Name="SkipEncryptionCheck" Grid.Row="6" Grid.Column="1" Grid.ColumnSpan="2" Margin="0,0,0,8" Content="Skip Device Encryption"/>
        <CheckBox x:Name="LeaveSystemAppsCheck" Grid.Row="7" Grid.Column="1" Grid.ColumnSpan="2" Margin="0,0,0,8" Content="Leave Android System Apps Enabled"/>

        <TextBlock Grid.Row="8" Grid.Column="0" Margin="0,0,8,8" VerticalAlignment="Center" Text="Save QR to:"/>
        <TextBox x:Name="OutputPathInput" Grid.Row="8" Grid.Column="1" Margin="0,0,8,8"/>
        <Button x:Name="BrowseButton" Grid.Row="8" Grid.Column="2" Width="60" Margin="0,0,0,8" Content="Browse"/>
        
        <CheckBox x:Name="DeleteOnExitCheck" Grid.Row="9" Grid.Column="1" Grid.ColumnSpan="2" Margin="0,0,0,8" Content="Delete QR code image when closing app"/>

        <StackPanel Grid.Row="10" Grid.ColumnSpan="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,10">
            <Button x:Name="DebugButton" Width="80" Margin="0,0,12,0" Content="Debug"/>
            <Button x:Name="GenerateButton" Width="120" Margin="0,0,12,0" Content="Generate QR Code"/>
            <Button x:Name="ExitButton" Width="80" Content="Exit"/>
        </StackPanel>

        <Border Grid.Row="12" Grid.ColumnSpan="3" BorderThickness="1" BorderBrush="LightGray" CornerRadius="4" MinHeight="320">
            <Grid Margin="10">
                <Image x:Name="QrImage" Stretch="Uniform" MaxHeight="300" MaxWidth="300"/>
                <TextBlock x:Name="PlaceholderText" HorizontalAlignment="Center" VerticalAlignment="Center" 
                          Foreground="Gray" Text="QR code will be generated locally"/>
            </Grid>
        </Border>
        
        <TextBlock Grid.Row="13" Grid.ColumnSpan="3" Margin="0,5,0,0" FontSize="10" Foreground="Green" 
                   Text="✓ All QR codes are generated locally on your device"/>
    </Grid>
</Window>
"@

$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]$xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

$enrollmentTokenInput = $window.FindName("EnrollmentTokenInput")
$wifiSsidInput = $window.FindName("WifiSsidInput")
$wifiPasswordInput = $window.FindName("WifiPasswordInput")
$securityTypeCombo = $window.FindName("SecurityTypeCombo")
$hiddenWifiCheck = $window.FindName("HiddenWifiCheck")
$skipEncryptionCheck = $window.FindName("SkipEncryptionCheck")
$leaveSystemAppsCheck = $window.FindName("LeaveSystemAppsCheck")
$outputInput = $window.FindName("OutputPathInput")
$browseButton = $window.FindName("BrowseButton")
$deleteOnExitCheck = $window.FindName("DeleteOnExitCheck")
$generateButton = $window.FindName("GenerateButton")
$debugButton = $window.FindName("DebugButton")
$exitButton = $window.FindName("ExitButton")
$qrImage = $window.FindName("QrImage")
$placeholderText = $window.FindName("PlaceholderText")

# Set defaults
$wifiSsidInput.Text = ""
$defaultPath = Join-Path ($env:temp) "android-enrollment-qr.png"
$outputInput.Text = $defaultPath
$deleteOnExitCheck.IsChecked = $true

# Add Browse button functionality
$browseButton.Add_Click({
    [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
    $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
    $saveDialog.Filter = "PNG Image|*.png|All Files|*.*"
    $saveDialog.FileName = "android-enrollment-qr.png"
    $saveDialog.InitialDirectory = $defaultPath
    
    if ($saveDialog.ShowDialog() -eq "OK") {
        $outputInput.Text = $saveDialog.FileName
    }
})

function Get-PayloadJson {
    $payload = [ordered]@{
        "android.app.extra.PROVISIONING_DEVICE_ADMIN_COMPONENT_NAME" = "com.google.android.apps.work.clouddpc/.receivers.CloudDeviceAdminReceiver"
        "android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_DOWNLOAD_LOCATION" = "https://play.google.com/managed/downloadManagingApp?identifier=setup"
        "android.app.extra.PROVISIONING_DEVICE_ADMIN_SIGNATURE_CHECKSUM" = "I5YvS0O5hXY46mb01BlRjq4oJJGs2kuUcHvVkAPEXlg"
    }

    # Add WiFi configuration if provided
    if (-not [string]::IsNullOrWhiteSpace($wifiSsidInput.Text)) {
        $payload["android.app.extra.PROVISIONING_WIFI_SSID"] = $wifiSsidInput.Text
        
        if ($wifiPasswordInput.Password) {
            $payload["android.app.extra.PROVISIONING_WIFI_PASSWORD"] = $wifiPasswordInput.Password
        }
        
        $securityType = $securityTypeCombo.SelectedItem.Content
        if ($securityType -ne "None") {
            $payload["android.app.extra.PROVISIONING_WIFI_SECURITY_TYPE"] = $securityType.ToUpper()
        }
        
        # Convert boolean to lowercase string for JSON
        $payload["android.app.extra.PROVISIONING_WIFI_HIDDEN"] = if ($hiddenWifiCheck.IsChecked) { $true } else { $false }
    }

    # Convert booleans to proper JSON format
    $payload["android.app.extra.PROVISIONING_SKIP_ENCRYPTION"] = if ($skipEncryptionCheck.IsChecked) { $true } else { $false }
    $payload["android.app.extra.PROVISIONING_LEAVE_ALL_SYSTEM_APPS_ENABLED"] = if ($leaveSystemAppsCheck.IsChecked) { $true } else { $false }

    # Add enrollment token if provided
    if (-not [string]::IsNullOrWhiteSpace($enrollmentTokenInput.Text)) {
        $payload["android.app.extra.PROVISIONING_ADMIN_EXTRAS_BUNDLE"] = @{
            "com.google.android.apps.work.clouddpc.EXTRA_ENROLLMENT_TOKEN" = $enrollmentTokenInput.Text.Trim()
        }
    }

    return $payload
}

$debugButton.Add_Click({
    try {
        $payload = Get-PayloadJson
        $jsonFormatted = $payload | ConvertTo-Json -Depth 3
        $jsonCompressed = $payload | ConvertTo-Json -Depth 3 -Compress

        $debugXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Debug - QR Code Payload" Height="600" Width="800" WindowStartupLocation="CenterScreen">
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="100"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <TextBlock Grid.Row="0" FontWeight="Bold" Margin="0,0,0,5" Text="Formatted JSON (for readability):"/>
        <TextBox Grid.Row="1" x:Name="FormattedJson" IsReadOnly="True" TextWrapping="Wrap" 
                 VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" 
                 FontFamily="Consolas" FontSize="12"/>
        
        <TextBlock Grid.Row="2" FontWeight="Bold" Margin="0,10,0,5" Text="Compressed JSON (actual QR content):"/>
        <TextBox Grid.Row="3" x:Name="CompressedJson" IsReadOnly="True" TextWrapping="Wrap" 
                 VerticalScrollBarVisibility="Auto" FontFamily="Consolas" FontSize="11"/>
        
        <StackPanel Grid.Row="4" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
            <TextBlock x:Name="CharCount" VerticalAlignment="Center" Margin="0,0,20,0" Foreground="Gray"/>
            <Button x:Name="CopyButton" Width="100" Margin="0,0,10,0" Content="Copy to Clipboard"/>
            <Button x:Name="CloseButton" Width="80" Content="Close"/>
        </StackPanel>
    </Grid>
</Window>
"@

        $debugReader = [System.Xml.XmlReader]::Create([System.IO.StringReader]$debugXaml)
        $debugWindow = [System.Windows.Markup.XamlReader]::Load($debugReader)
        
        $formattedTextBox = $debugWindow.FindName("FormattedJson")
        $compressedTextBox = $debugWindow.FindName("CompressedJson")
        $charCountText = $debugWindow.FindName("CharCount")
        $copyButton = $debugWindow.FindName("CopyButton")
        $closeButton = $debugWindow.FindName("CloseButton")
        
        $formattedTextBox.Text = $jsonFormatted
        $compressedTextBox.Text = $jsonCompressed
        $charCountText.Text = "Character count: $($jsonCompressed.Length)"
        
        $copyButton.Add_Click({
            [System.Windows.Clipboard]::SetText($jsonCompressed)
            [System.Windows.MessageBox]::Show("JSON copied to clipboard!", "Debug") | Out-Null
        })
        
        $closeButton.Add_Click({ $debugWindow.Close() })
        
        [void]$debugWindow.ShowDialog()
    }
    catch {
        [System.Windows.MessageBox]::Show("Error showing debug info: $($_.Exception.Message)") | Out-Null
    }
})

$generateButton.Add_Click({
    try {
        # Check if QRCodeGenerator module is available
        if (-not (Get-Command -Name New-QRCodeText -ErrorAction SilentlyContinue)) {
            $result = [System.Windows.MessageBox]::Show(
                "QRCodeGenerator module is not loaded. Android Enterprise enrollment requires valid QR codes.`n`nWould you like to try installing it now?",
                "QRCodeGenerator Required",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Warning
            )
            
            if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
                try {
                    Install-Module -Name QRCodeGenerator -Force -Scope CurrentUser
                    Import-Module QRCodeGenerator
                    [System.Windows.MessageBox]::Show("QRCodeGenerator installed successfully. Please click Generate again.") | Out-Null
                } catch {
                    [System.Windows.MessageBox]::Show("Failed to install QRCodeGenerator: $_") | Out-Null
                }
            }
            return
        }

        $payload = Get-PayloadJson
        
        # Use ConvertTo-Json with specific depth and ensure proper formatting
        $jsonContent = $payload | ConvertTo-Json -Depth 3 -Compress
        
        # Ensure booleans are lowercase in JSON
        $jsonContent = $jsonContent -replace ':\s*"?True"?', ':true' -replace ':\s*"?False"?', ':false'

        $output = $outputInput.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($output)) {
            [System.Windows.MessageBox]::Show("Specify where to save the QR code.") | Out-Null
            return
        }

        $folder = [System.IO.Path]::GetDirectoryName($output)
        if ($folder -and -not (Test-Path -LiteralPath $folder)) {
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
        }

        # Generate QR code using the PowerShell module
        New-QRCodeText -Text $jsonContent -OutPath $output

        # Load the generated image into the preview
        $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
        $bitmap.BeginInit()
        $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bitmap.UriSource = New-Object System.Uri($output)
        $bitmap.EndInit()
        $qrImage.Source = $bitmap
        $placeholderText.Visibility = "Collapsed"
        
        #[System.Windows.MessageBox]::Show("Android Enterprise enrollment QR code generated successfully!`nSaved to: $output") | Out-Null
    }
    catch {
        [System.Windows.MessageBox]::Show("Failed to generate QR code.`n$($_.Exception.Message)") | Out-Null
    }
})

$exitButton.Add_Click({ 
    # Check if we need to delete the QR code file
    if ($deleteOnExitCheck.IsChecked -and (Test-Path $outputInput.Text)) {
        try {
            Remove-Item -Path $outputInput.Text -Force
            Write-Host "QR code image deleted: $($outputInput.Text)" -ForegroundColor Green
        } catch {
            Write-Warning "Could not delete QR code image: $_"
        }
    }
    $window.Close() 
})

# Add window closing event handler for cleanup
$window.Add_Closing({
    param($sender, $e)
    
    if ($deleteOnExitCheck.IsChecked -and (Test-Path $outputInput.Text)) {
        try {
            Remove-Item -Path $outputInput.Text -Force
            Write-Host "QR code image deleted on exit: $($outputInput.Text)" -ForegroundColor Green
        } catch {
            Write-Warning "Could not delete QR code image on exit: $_"
        }
    }
})

[void]$window.ShowDialog()
