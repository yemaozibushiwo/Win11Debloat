function Show-ImportExportConfigWindow {
    param (
        [System.Windows.Window]$Owner,
        [bool]$UsesDarkMode,
        [string]$Title,
        [string]$Prompt,
        [string[]]$Categories = @('Applications', 'System Tweaks', 'Deployment Settings'),
        [string[]]$DisabledCategories = @(),
        [hashtable]$CategoryDetails = @(),
        [string]$ActionLabel = 'OK'
    )

    # Map internal category keys to their localized display names for the UI
    $categoryDisplayNames = @{
        'Applications'        = '应用'
        'System Tweaks'       = '系统调整'
        'Deployment Settings' = '部署设置'
    }

    # Show overlay on owner window
    $overlay = $null
    $overlayWasAlreadyVisible = $false
    try {
        $overlay = $Owner.FindName('ModalOverlay')
        if ($overlay) {
            $overlayWasAlreadyVisible = ($overlay.Visibility -eq 'Visible')
            if (-not $overlayWasAlreadyVisible) {
                $Owner.Dispatcher.Invoke([action]{ $overlay.Visibility = 'Visible' })
            }
        }
    } catch { }

    # Load XAML from schema file
    $schemaPath = $script:ImportExportConfigSchema

    if (-not $schemaPath -or -not (Test-Path $schemaPath)) {
        Show-MessageBox -Message '找不到导入/导出窗口的架构文件。' -Title '错误' -Button 'OK' -Icon 'Error' -Owner $Owner | Out-Null
        if ($overlay -and -not $overlayWasAlreadyVisible) {
            try { $Owner.Dispatcher.Invoke([action]{ $overlay.Visibility = 'Collapsed' }) } catch { }
        }
        return $null
    }

    $xaml = Get-Content -Path $schemaPath -Raw
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
    try {
        $dlg = [System.Windows.Markup.XamlReader]::Load($reader)
    }
    finally {
        $reader.Close()
    }

    $dlg.Owner = $Owner
    SetWindowThemeResources -window $dlg -usesDarkMode $UsesDarkMode

    # Copy the CheckBox default style from the main window so checkboxes get the themed template
    try {
        $mainCheckBoxStyle = $Owner.FindResource([type][System.Windows.Controls.CheckBox])
        if ($mainCheckBoxStyle) {
            $dlg.Resources.Add([type][System.Windows.Controls.CheckBox], $mainCheckBoxStyle)
        }
    } catch { }

    # Populate named elements
    $dlg.Title = $Title
    $dlg.FindName('TitleText').Text = $Title
    $dlg.FindName('PromptText').Text = $Prompt

    $titleBar = $dlg.FindName('TitleBar')
    $titleBar.Add_MouseLeftButtonDown({ $dlg.DragMove() })

    # Add a themed checkbox per category
    $checkboxPanel = $dlg.FindName('CheckboxPanel')
    $checkboxes = @{}
    foreach ($cat in $Categories) {
        # Create a container for the checkbox and details
        $container = New-Object System.Windows.Controls.StackPanel
        $container.Orientation = [System.Windows.Controls.Orientation]::Vertical
        $container.Margin = [System.Windows.Thickness]::new(0,0,0,12)

        # Create checkbox
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Content = if ($categoryDisplayNames.ContainsKey($cat)) { $categoryDisplayNames[$cat] } else { $cat }
        $cb.IsChecked = $true
        $cb.Margin = [System.Windows.Thickness]::new(0,0,0,4)
        $cb.FontSize = 14
        $cb.FontWeight = [System.Windows.FontWeights]::Medium
        $cb.Foreground = $dlg.FindResource('FgColor')
        if ($DisabledCategories -contains $cat) {
            $cb.IsChecked = $false
            $cb.IsEnabled = $false
            $cb.Opacity = 0.65
            $cb.ToolTip = '此分类下没有可用的已选设置。'
        }
        
        $container.Children.Add($cb) | Out-Null
        
        # Add details if available
        if ($CategoryDetails -and $CategoryDetails[$cat]) {
            $detailsText = New-Object System.Windows.Controls.TextBlock
            $detailsText.Text = $CategoryDetails[$cat]
            $detailsText.FontSize = 12
            $detailsText.Foreground = $dlg.FindResource('FgColor')
            $detailsText.Margin = [System.Windows.Thickness]::new(30,0,0,0)
            $detailsText.Opacity = 0.75
            $detailsText.TextWrapping = [System.Windows.TextWrapping]::Wrap
            $container.Children.Add($detailsText) | Out-Null
        }
        
        $checkboxPanel.Children.Add($container) | Out-Null
        $checkboxes[$cat] = $cb
    }

    $okBtn = $dlg.FindName('OkButton')
    $cancelBtn = $dlg.FindName('CancelButton')
    $okBtn.Content = $ActionLabel
    $okBtn.Add_Click({ $dlg.Tag = 'OK'; $dlg.Close() })
    $cancelBtn.Add_Click({ $dlg.Tag = 'Cancel'; $dlg.Close() })

    # Handle Escape key
    $dlg.Add_KeyDown({
        param($s, $e)
        if ($e.Key -eq 'Escape') { $dlg.Tag = 'Cancel'; $dlg.Close() }
    })

    try {
        $dlg.ShowDialog() | Out-Null
    }
    finally {
        # Hide overlay
        if ($overlay -and -not $overlayWasAlreadyVisible) {
            try { $Owner.Dispatcher.Invoke([action]{ $overlay.Visibility = 'Collapsed' }) } catch { }
        }
    }

    if ($dlg.Tag -ne 'OK') { return $null }

    $selected = @()
    foreach ($cat in $Categories) {
        if ($checkboxes[$cat].IsEnabled -and $checkboxes[$cat].IsChecked) { $selected += $cat }
    }
    if ($selected.Count -eq 0) { return $null }
    return $selected
}

function Get-SelectedApplications {
    param (
        [System.Windows.Controls.Panel]$AppsPanel
    )

    $selectedApps = @()
    foreach ($child in $AppsPanel.Children) {
        if ($child -is [System.Windows.Controls.CheckBox] -and $child.IsChecked) {
            $selectedApps += $child.Tag
        }
    }

    return $selectedApps
}

function Get-SelectedTweakSettings {
    param (
        [System.Windows.Window]$Owner,
        [hashtable]$UiControlMappings
    )

    $tweakSettings = @()
    if (-not $UiControlMappings) {
        return $tweakSettings
    }

    foreach ($mappingKey in $UiControlMappings.Keys) {
        $control = $Owner.FindName($mappingKey)
        if (-not $control) { continue }

        $mapping = $UiControlMappings[$mappingKey]
        if ($control -is [System.Windows.Controls.CheckBox] -and $control.IsChecked) {
            if ($mapping.Type -eq 'feature') {
                $tweakSettings += @{ Name = $mapping.FeatureId; Value = $true }
            }
        }
        elseif ($control -is [System.Windows.Controls.ComboBox] -and $control.SelectedIndex -gt 0) {
            if ($mapping.Type -eq 'group') {
                $selectedValue = $mapping.Values[$control.SelectedIndex - 1]
                foreach ($fid in $selectedValue.FeatureIds) {
                    $tweakSettings += @{ Name = $fid; Value = $true }
                }
            }
            elseif ($mapping.Type -eq 'feature') {
                $tweakSettings += @{ Name = $mapping.FeatureId; Value = $true }
            }
        }
    }

    return $tweakSettings
}

function Get-DeploymentSettings {
    param (
        [System.Windows.Window]$Owner,
        [System.Windows.Controls.ComboBox]$UserSelectionCombo,
        [System.Windows.Controls.TextBox]$OtherUsernameTextBox
    )

    $deploySettings = @(
        @{ Name = 'UserSelectionIndex'; Value = $UserSelectionCombo.SelectedIndex }
    )

    if ($UserSelectionCombo.SelectedIndex -eq 1) {
        $deploySettings += @{ Name = 'OtherUsername'; Value = $OtherUsernameTextBox.Text.Trim() }
    }

    $appRemovalScopeCombo = $Owner.FindName('AppRemovalScopeCombo')
    if ($appRemovalScopeCombo) {
        $deploySettings += @{ Name = 'AppRemovalScopeIndex'; Value = $appRemovalScopeCombo.SelectedIndex }
    }

    $restorePointCheckBox = $Owner.FindName('RestorePointCheckBox')
    if ($restorePointCheckBox) {
        $deploySettings += @{ Name = 'CreateRestorePoint'; Value = [bool]$restorePointCheckBox.IsChecked }
    }

    $restartExplorerCheckBox = $Owner.FindName('RestartExplorerCheckBox')
    if ($restartExplorerCheckBox) {
        $deploySettings += @{ Name = 'RestartExplorer'; Value = [bool]$restartExplorerCheckBox.IsChecked }
    }

    return $deploySettings
}

function Get-AvailableImportExportCategories {
    param (
        $Config
    )

    $availableCategories = @()
    if ($Config.Apps) { $availableCategories += 'Applications' }
    if ($Config.Tweaks) { $availableCategories += 'System Tweaks' }
    if ($Config.Deployment) { $availableCategories += 'Deployment Settings' }

    return $availableCategories
}

function Get-DeploymentCategoryDetailString {
    param (
        [array]$DeploymentSettings
    )

    $lookup = @{}
    foreach ($setting in @($DeploymentSettings)) {
        if ($setting -and $setting.Name) {
            $lookup[$setting.Name] = $setting.Value
        }
    }

    $line1 = @()

    if ($lookup.ContainsKey('UserSelectionIndex')) {
        switch ([int]$lookup['UserSelectionIndex']) {
            0 { $line1 += '用户:当前用户' }
            1 { $line1 += "用户:$(if ($lookup['OtherUsername']) { $lookup['OtherUsername'] } else { '其他用户' })" }
            2 { $line1 += '用户:Sysprep' }
        }
    }

    if ($lookup.ContainsKey('AppRemovalScopeIndex')) {
        switch ([int]$lookup['AppRemovalScopeIndex']) {
            0 { $line1 += '应用卸载:所有用户' }
            1 { $line1 += '应用卸载:当前用户' }
            2 { $line1 += "应用卸载:$(if ($lookup['OtherUsername']) { $lookup['OtherUsername'] } else { '其他用户' })" }
        }
    }

    $options = @()
    if ($lookup.ContainsKey('CreateRestorePoint') -and [bool]$lookup['CreateRestorePoint']) { $options += '创建还原点' }
    if ($lookup.ContainsKey('RestartExplorer')    -and [bool]$lookup['RestartExplorer'])    { $options += '重启资源管理器' }

    $lines = @()
    if ($line1.Count -gt 0)   { $lines += $line1 -join ', ' }
    if ($options.Count -gt 0) { $lines += "选项:$($options -join ', ')" }

    if ($lines.Count -gt 0) { return $lines -join "`n" }
    return '默认部署设置'
}

function Build-CategoryDetails {
    param (
        [int]$AppCount = 0,
        [int]$TweakCount = 0,
        [array]$DeploymentSettings
    )

    $details = @{}

    if ($AppCount -gt 0) {
        $details['Applications'] = "$AppCount 个应用"
    }

    if ($TweakCount -gt 0) {
        $details['System Tweaks'] = "$TweakCount 项调整"
    }

    if ($DeploymentSettings) {
        $details['Deployment Settings'] = Get-DeploymentCategoryDetailString -DeploymentSettings $DeploymentSettings
    }

    return $details
}

function Apply-ImportedApplications {
    param (
        [System.Windows.Controls.Panel]$AppsPanel,
        [string[]]$AppIds
    )

    foreach ($child in $AppsPanel.Children) {
        if ($child -is [System.Windows.Controls.CheckBox]) {
            $child.IsChecked = ($AppIds -contains $child.Tag)
        }
    }
}

function Apply-ImportedTweakSettings {
    param (
        [System.Windows.Window]$Owner,
        [hashtable]$UiControlMappings,
        [array]$TweakSettings
    )

    $settingsJson = [PSCustomObject]@{ Settings = @($TweakSettings) }
    ApplySettingsToUiControls -window $Owner -settingsJson $settingsJson -uiControlMappings $UiControlMappings
}

function Apply-ImportedDeploymentSettings {
    param (
        [System.Windows.Window]$Owner,
        [System.Windows.Controls.ComboBox]$UserSelectionCombo,
        [System.Windows.Controls.TextBox]$OtherUsernameTextBox,
        [array]$DeploymentSettings
    )

    $lookup = @{}
    foreach ($setting in $DeploymentSettings) {
        $lookup[$setting.Name] = $setting.Value
    }

    if ($lookup.ContainsKey('UserSelectionIndex')) {
        $UserSelectionCombo.SelectedIndex = [int]$lookup['UserSelectionIndex']
    }
    if ($lookup.ContainsKey('OtherUsername') -and $UserSelectionCombo.SelectedIndex -eq 1) {
        $OtherUsernameTextBox.Text = $lookup['OtherUsername']
    }

    $appRemovalScopeCombo = $Owner.FindName('AppRemovalScopeCombo')
    if ($lookup.ContainsKey('AppRemovalScopeIndex') -and $appRemovalScopeCombo) {
        $appRemovalScopeCombo.SelectedIndex = [int]$lookup['AppRemovalScopeIndex']
    }

    $restorePointCheckBox = $Owner.FindName('RestorePointCheckBox')
    if ($lookup.ContainsKey('CreateRestorePoint') -and $restorePointCheckBox) {
        $restorePointCheckBox.IsChecked = [bool]$lookup['CreateRestorePoint']
    }

    $restartExplorerCheckBox = $Owner.FindName('RestartExplorerCheckBox')
    if ($lookup.ContainsKey('RestartExplorer') -and $restartExplorerCheckBox) {
        $restartExplorerCheckBox.IsChecked = [bool]$lookup['RestartExplorer']
    }
}

function Export-Configuration {
    param (
        [System.Windows.Window]$Owner,
        [bool]$UsesDarkMode,
        [System.Windows.Controls.Panel]$AppsPanel,
        [hashtable]$UiControlMappings,
        [System.Windows.Controls.ComboBox]$UserSelectionCombo,
        [System.Windows.Controls.TextBox]$OtherUsernameTextBox
    )

    # Precompute exportable data so empty categories can be disabled in the picker.
    $selectedApps = Get-SelectedApplications -AppsPanel $AppsPanel
    $tweakSettings = Get-SelectedTweakSettings -Owner $Owner -UiControlMappings $UiControlMappings

    $disabledCategories = @()
    if ($selectedApps.Count -eq 0) { $disabledCategories += 'Applications' }
    if ($tweakSettings.Count -eq 0) { $disabledCategories += 'System Tweaks' }

    $deploymentSettings = Get-DeploymentSettings -Owner $Owner -UserSelectionCombo $UserSelectionCombo -OtherUsernameTextBox $OtherUsernameTextBox
    $categoryDetails = Build-CategoryDetails -AppCount $selectedApps.Count -TweakCount $tweakSettings.Count -DeploymentSettings $deploymentSettings

    $categories = Show-ImportExportConfigWindow -Owner $Owner -UsesDarkMode $UsesDarkMode -Title '导出配置' -Prompt '选择要包含在导出中的设置。' -DisabledCategories $disabledCategories -CategoryDetails $categoryDetails -ActionLabel '导出设置'
    if (-not $categories) {
        Write-Host '已取消导出。'
        return
    }

    $config = @{ Version = '1.0' }

    if ($categories -contains 'Applications') {
        $config['Apps'] = @($selectedApps)
    }
    if ($categories -contains 'System Tweaks') {
        $config['Tweaks'] = @($tweakSettings)
    }
    if ($categories -contains 'Deployment Settings') {
        $config['Deployment'] = @($deploymentSettings)
    }

    # Show native save-file dialog
    $saveDialog = New-Object Microsoft.Win32.SaveFileDialog
    $saveDialog.Title = '导出配置'
    $saveDialog.Filter = 'JSON files (*.json)|*.json|All files (*.*)|*.*'
    $saveDialog.DefaultExt = '.json'
    $saveDialog.FileName = "Win11Debloat-Config-$(Get-Date -Format 'yyyyMMdd').json"

    if ($saveDialog.ShowDialog($Owner) -ne $true) {
        Write-Host '已取消保存。'
        return
    }

    Write-Host "Exporting configuration to '$($saveDialog.FileName)'... (Categories: $($categories -join ', '))"

    if (SaveToFile -Config $config -FilePath $saveDialog.FileName) {
        Write-Host "Configuration exported successfully: $($saveDialog.FileName)"
        Show-MessageBox -Message "配置导出成功。" -Title '导出配置' -Button 'OK' -Icon 'Information' | Out-Null
    }
    else {
        Write-Error "Failed to export configuration to '$($saveDialog.FileName)'"
        Show-MessageBox -Message '导出配置失败' -Title '错误' -Button 'OK' -Icon 'Error' | Out-Null
    }
}

function Import-Configuration {
    param (
        [System.Windows.Window]$Owner,
        [bool]$UsesDarkMode,
        [System.Windows.Controls.Panel]$AppsPanel,
        [hashtable]$UiControlMappings,
        [System.Windows.Controls.ComboBox]$UserSelectionCombo,
        [System.Windows.Controls.TextBox]$OtherUsernameTextBox,
        [scriptblock]$OnAppsImported,
        [scriptblock]$OnImportCompleted
    )

    # Show native open-file dialog
    $openDialog = New-Object Microsoft.Win32.OpenFileDialog
    $openDialog.Title = '选择配置文件'
    $openDialog.Filter = 'JSON files (*.json)|*.json|All files (*.*)|*.*'
    $openDialog.DefaultExt = '.json'

    if ($openDialog.ShowDialog($Owner) -ne $true) {
        Write-Host '已取消导入。'
        return
    }

    Write-Host "Importing configuration from '$($openDialog.FileName)'..."

    $config = LoadJsonFile -filePath $openDialog.FileName -expectedVersion '1.0'
    if (-not $config) {
        Write-Error "Failed to read configuration file '$($openDialog.FileName)'"
        Show-MessageBox -Message '读取配置文件失败' -Title '无效的配置' -Button 'OK' -Icon 'Error' | Out-Null
        return
    }

    if (-not $config.Version) {
        Write-Error "Invalid configuration file format: '$($openDialog.FileName)'"
        Show-MessageBox -Message '配置文件格式无效。' -Title '无效的配置' -Button 'OK' -Icon 'Error' | Out-Null
        return
    }

    $availableCategories = Get-AvailableImportExportCategories -Config $config

    if ($availableCategories.Count -eq 0) {
        Write-Warning "Configuration file '$($openDialog.FileName)' contains no importable data."
        Show-MessageBox -Message '所选文件不包含可导入的数据。' -Title '无效的配置' -Button 'OK' -Icon 'Error' | Out-Null
        return
    }

    Write-Host "Available categories in config: $($availableCategories -join ', ')"

    $appCount = @($config.Apps | Where-Object { $_ -is [string] -and -not [string]::IsNullOrWhiteSpace($_) }).Count
    $tweakCount = @($config.Tweaks | Where-Object { $_ -and $_.Name -and $_.Value -eq $true }).Count
    $categoryDetails = Build-CategoryDetails -AppCount $appCount -TweakCount $tweakCount -DeploymentSettings @($config.Deployment)

    $categories = Show-ImportExportConfigWindow -Owner $Owner -UsesDarkMode $UsesDarkMode -Title '导入配置' -Prompt '选择要导入的设置。导入后可以再次检查和修改。' -Categories $availableCategories -CategoryDetails $categoryDetails -ActionLabel '导入设置'
    if (-not $categories) {
        Write-Host '已取消导入。'
        return
    }

    if ($categories -contains 'Applications' -and $config.Apps) {
        $appIds = @(
            $config.Apps |
            Where-Object { $_ -is [string] } |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )

        Write-Host "Importing $($appIds.Count) app selection(s)."
        Apply-ImportedApplications -AppsPanel $AppsPanel -AppIds $appIds

        if ($OnAppsImported) {
            & $OnAppsImported
        }
    }
    if ($categories -contains 'System Tweaks' -and $config.Tweaks) {
        $tweakCount = @($config.Tweaks).Count
        Write-Host "Importing $tweakCount tweak(s)."
        Apply-ImportedTweakSettings -Owner $Owner -UiControlMappings $UiControlMappings -TweakSettings @($config.Tweaks)
    }
    if ($categories -contains 'Deployment Settings' -and $config.Deployment) {
        Write-Host 'Importing deployment settings.'
        Apply-ImportedDeploymentSettings -Owner $Owner -UserSelectionCombo $UserSelectionCombo -OtherUsernameTextBox $OtherUsernameTextBox -DeploymentSettings @($config.Deployment)
    }

    Write-Host 'Configuration imported successfully.'
    Show-MessageBox -Message '配置导入成功。' -Title '导入配置' -Button 'OK' -Icon 'Information' | Out-Null

    if ($OnImportCompleted) {
        & $OnImportCompleted $categories
    }
}
