# SCRIPT'i KULLANMADAN ÖNCE OKUYUN: 
# Bu script, yetki kontrolü yapmak için 'icacls' komutunu kullanır. 
# Bu komut, standart PowerShell izin kontrolünden daha detaylıdır. 
# Lütfen script'i çalıştırmadan önce PowerShell'i yönetici olarak çalıştırdığınızdan emin olun. 
# Bazı yetkiler, özellikle sistem klasörlerinde, 'icacls' komutunun çalışmasını engelleyebilir. 

# Gerekli assembly'leri yükle
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$OutputEncoding = [System.Text.Encoding]::UTF8

try {

    # Ana form ve kontrolleri oluşturma
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Dosya ve Dizin Yetki Kontrol Aracı"
    $form.Size = New-Object System.Drawing.Size(800, 600)
    $form.StartPosition = 'CenterScreen'
    $form.BackColor = [System.Drawing.Color]::LightGray

    # Yetkili kullanıcı adını al
    $currentUserName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    # Kontrol düğmeleri
    $selectButton = New-Object System.Windows.Forms.Button
    $selectButton.Text = "Dizin Seç"
    $selectButton.Location = New-Object System.Drawing.Point(10, 10)
    $selectButton.Size = New-Object System.Drawing.Size(120, 30)

    $scanButton = New-Object System.Windows.Forms.Button
    $scanButton.Text = "Taramayı Başlat"
    $scanButton.Location = New-Object System.Drawing.Point(140, 10)
    $scanButton.Size = New-Object System.Drawing.Size(120, 30)
    $scanButton.Enabled = $false

    $stopButton = New-Object System.Windows.Forms.Button
    $stopButton.Text = "Durdur"
    $stopButton.Location = New-Object System.Drawing.Point(270, 10)
    $stopButton.Size = New-Object System.Drawing.Size(80, 30)
    $stopButton.Enabled = $false

    # Kullanıcı adı etiketi
    $userNameLabel = New-Object System.Windows.Forms.Label
    $userNameLabel.Text = "Kullanıcı: $currentUserName"
    $userNameLabel.Location = New-Object System.Drawing.Point(600, 15)
    $userNameLabel.AutoSize = $true
    $userNameLabel.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
    $userNameLabel.ForeColor = [System.Drawing.Color]::DarkBlue

    $pathLabel = New-Object System.Windows.Forms.Label
    $pathLabel.Text = "Seçili Dizin: Henüz Dizin Seçilmedi."
    $pathLabel.Location = New-Object System.Drawing.Point(10, 50)
    $pathLabel.AutoSize = $true

    # İlerleme çubuğu
    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Location = New-Object System.Drawing.Point(10, 75)
    $progressBar.Size = New-Object System.Drawing.Size(760, 20)
    $progressBar.Style = 'Continuous'
    $progressBar.Visible = $false

    # Ağaç yapısı (TreeView)
    $treeView = New-Object System.Windows.Forms.TreeView
    $treeView.Location = New-Object System.Drawing.Point(10, 105)
    $treeView.Size = New-Object System.Drawing.Size(760, 445)
    $treeView.BackColor = [System.Drawing.Color]::White
    $treeView.ImageIndex = 0
    $treeView.SelectedImageIndex = 0

    # Ağaç yapısı ikonları için ImageList
    $imageList = New-Object System.Windows.Forms.ImageList
    $imageList.ColorDepth = 'Depth32Bit'
    $imageList.ImageSize = New-Object System.Drawing.Size(16, 16)
    $imageList.Images.Add("GreenTick", [System.Drawing.SystemIcons]::Shield) # Kalkan ikonu
    $imageList.Images.Add("BlueInfo", [System.Drawing.SystemIcons]::Information) # Bilgi ikonu
    $imageList.Images.Add("RedCross", [System.Drawing.SystemIcons]::Error) # Hata ikonu
    $treeView.ImageList = $imageList

    # Form'a kontrolleri ekleme
    $form.Controls.Add($selectButton)
    $form.Controls.Add($scanButton)
    $form.Controls.Add($stopButton)
    $form.Controls.Add($userNameLabel)
    $form.Controls.Add($pathLabel)
    $form.Controls.Add($progressBar)
    $form.Controls.Add($treeView)

    # Dizin seçme butonu için olay
    $selectButton.Add_Click({
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = "Lütfen taramak istediğiniz dizini seçin:"
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:rootPath = $dialog.SelectedPath
            $pathLabel.Text = "Seçili Dizin: $script:rootPath"
            $scanButton.Enabled = $true
        }
    })

    # Taramayı durdurmak için global bir değişken tanımla
    $script:isStopped = $false

    # Durdur butonu için olay
    $stopButton.Add_Click({
        $script:isStopped = $true
        $stopButton.Enabled = $false
        Write-Host "Tarama durdurma isteği gönderildi..." -ForegroundColor Yellow
    })

    # Tarama başlatma butonu için olay
    $scanButton.Add_Click({
        $scanButton.Enabled = $false
        $selectButton.Enabled = $false
        $stopButton.Enabled = $true
        $treeView.Nodes.Clear()
        $progressBar.Visible = $true
        $progressBar.Value = 0
        $script:isStopped = $false # Yeni tarama için sıfırla

        $items = Get-ChildItem -Path $script:rootPath -Recurse -Force -ErrorAction SilentlyContinue
        $totalItems = $items.Count
        $processedItems = 0

        $rootNode = $treeView.Nodes.Add($script:rootPath)
        $rootNode.Expand()

        foreach ($item in $items) {
            # Eğer durdurma isteği geldiyse döngüden çık
            if ($script:isStopped) {
                Write-Host "Tarama durduruldu." -ForegroundColor Red
                break
            }

            $processedItems++
            $progress = [math]::Floor(($processedItems / $totalItems) * 100)

            $progressBar.Value = $progress
            $form.Text = "Tarama ($progress%) - $item.FullName"
            [System.Windows.Forms.Application]::DoEvents()

            $node = New-Object System.Windows.Forms.TreeNode
            $node.Text = $item.Name

            try {
                $acl = icacls $item.FullName 2>&1
                $hasPermission = $acl -notmatch "Erişim engellendi." -and $acl -notmatch "Access is denied" -and $acl -notmatch "Yetkisiz erişim"

                if ($hasPermission) {
                    $hasWritePermission = $acl -match "\((F|M|W)\)"
                    if ($hasWritePermission) {
                        $node.ImageKey = "GreenTick"
                        $node.SelectedImageKey = "GreenTick"
                        $node.Text += " - Tam/Yazma Yetkisi"
                    } else {
                        $node.ImageKey = "BlueInfo"
                        $node.SelectedImageKey = "BlueInfo"
                        $node.Text += " - Sadece Okuma/Göz Atma Yetkisi"
                    }
                } else {
                    $node.ImageKey = "RedCross"
                    $node.SelectedImageKey = "RedCross"
                    $node.Text += " - Erişim Engellendi"
                }
            } catch {
                $node.ImageKey = "RedCross"
                $node.SelectedImageKey = "RedCross"
                $node.Text += " - Hata (Erişim Engellendi)"
            }

            $parentPath = Split-Path -Path $item.FullName -Parent
            $parentNodes = $treeView.Nodes.Find($parentPath, $true)
            if ($parentNodes.Length -gt 0) {
                $parentNodes[0].Nodes.Add($node)
            } else {
                $treeView.Nodes.Add($node)
            }
        }

        $progressBar.Visible = $false
        $form.Text = "Tarama Tamamlandı"
        $scanButton.Enabled = $true
        $selectButton.Enabled = $true
        $stopButton.Enabled = $false
    })


    # Formu gösterme
    $form.ShowDialog()

}
# Hata olursa bu blok çalışır
catch {
    # Hata mesajını bir pop-up penceresinde göster
    [System.Windows.Forms.MessageBox]::Show(
        "Bilinmeyen bir hata oluştu!`n`n$($_.Exception.Message)`n`nScript sonlandırılıyor.",
        "Hata",
        "OK",
        "Error"
    )
}