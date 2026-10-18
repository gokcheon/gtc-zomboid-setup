# GTC Zomboid Setup - 1층: 위치 찾기 + 모음집 구독·다운로드 확인
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$Title   = 'GTC 서버 설치'
$WorkDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogPath = Join-Path $WorkDir 'setup_log.txt'
$UiFont  = New-Object System.Drawing.Font('Malgun Gothic', 10)

function Write-Log([string]$m) {
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

# 메시지 창이 다른 창 뒤로 숨지 않게 하는 보이지 않는 맨 앞 창
$script:Owner = New-Object System.Windows.Forms.Form
$script:Owner.TopMost = $true
$script:Owner.ShowInTaskbar = $false
$script:Owner.FormBorderStyle = 'None'
$script:Owner.StartPosition = 'Manual'
$script:Owner.Location = New-Object System.Drawing.Point(-2000, -2000)
$script:Owner.Size = New-Object System.Drawing.Size(1, 1)
$script:Owner.Opacity = 0
$script:Owner.Show()

function Show-Msg([string]$text, [string]$buttons = 'OK', [string]$icon = 'Information') {
    return [System.Windows.Forms.MessageBox]::Show($script:Owner, $text, $Title,
        [System.Windows.Forms.MessageBoxButtons]::$buttons,
        [System.Windows.Forms.MessageBoxIcon]::$icon)
}

function Read-Text([string]$p) {
    return [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
}

function Find-Steam {
    $sp = $null
    $k = Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue
    if ($k -and $k.SteamPath) { $sp = $k.SteamPath }
    if (-not $sp) {
        $k = Get-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction SilentlyContinue
        if ($k -and $k.InstallPath) { $sp = $k.InstallPath }
    }
    if ($sp) { $sp = $sp -replace '/', '\' }
    if ($sp -and (Test-Path -LiteralPath (Join-Path $sp 'steam.exe'))) { return $sp }
    return $null
}

function Find-Game([string]$steam, [string]$appId) {
    $libs = New-Object System.Collections.Generic.List[string]
    $libs.Add($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        foreach ($m in [regex]::Matches((Read-Text $vdf), '"path"\s+"([^"]+)"')) {
            $libs.Add(($m.Groups[1].Value -replace '\\\\', '\'))
        }
    }
    foreach ($lib in ($libs | Select-Object -Unique)) {
        $acf = Join-Path $lib "steamapps\appmanifest_$appId.acf"
        if (-not (Test-Path -LiteralPath $acf)) { continue }
        $m = [regex]::Match((Read-Text $acf), '"installdir"\s+"([^"]+)"')
        if (-not $m.Success) { continue }
        $game = Join-Path $lib ('steamapps\common\' + $m.Groups[1].Value)
        if (Test-Path -LiteralPath $game) {
            return [pscustomobject]@{
                Library     = $lib
                GameDir     = $game
                WorkshopDir = (Join-Path $lib "steamapps\workshop\content\$appId")
            }
        }
    }
    return $null
}

function Find-LastUser([string]$steam) {
    $p = Join-Path $steam 'config\loginusers.vdf'
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    foreach ($m in [regex]::Matches((Read-Text $p), '"(\d{17})"\s*\{([^}]*)\}')) {
        if ($m.Groups[2].Value -match '"MostRecent"\s+"1"') {
            $id64 = [UInt64]$m.Groups[1].Value
            return [pscustomobject]@{
                SteamId64 = $id64
                AccountId = ($id64 - [UInt64]76561197960265728)
            }
        }
    }
    return $null
}

function Get-Downloaded([string]$wsDir, $ids) {
    $n = 0
    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($id in $ids) {
        $d = Join-Path $wsDir $id
        $ok = $false
        if (Test-Path -LiteralPath $d) {
            $f = Get-ChildItem -LiteralPath $d -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($f) { $ok = $true }
        }
        if ($ok) { $n++ } else { $missing.Add($id) }
    }
    return [pscustomobject]@{ Count = $n; Missing = $missing }
}

try {
    Write-Log '--- 시작 ---'
    $Config = Get-Content -LiteralPath (Join-Path $WorkDir 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $Ids   = @($Config.workshopItems | ForEach-Object { [string]$_ })
    $Total = $Ids.Count

    # 창 1: 시작
    $r = Show-Msg "GTC 서버 설치를 시작합니다.`n약 10~30분 걸리며, 중간에 스팀이 한 번 꺼졌다 켜집니다." 'OKCancel' 'Information'
    if ($r -ne [System.Windows.Forms.DialogResult]::OK) { Write-Log '시작 창에서 취소'; exit 0 }

    # ① 위치 찾기
    $Steam = Find-Steam
    $Game  = $null
    if ($Steam) { $Game = Find-Game $Steam ([string]$Config.appId) }
    if (-not $Steam -or -not $Game) {
        Write-Log ("위치 찾기 실패: Steam={0} Game={1}" -f $Steam, ($Game -ne $null))
        Show-Msg "스팀 또는 좀보이드 설치 위치를 찾지 못했습니다.`n스팀에 로그인한 뒤 좀보이드를 한 번 실행하고 다시 시도하세요." 'OK' 'Error' | Out-Null
        exit 1
    }
    $User = Find-LastUser $Steam
    Write-Log ("스팀 폴더: {0}" -f $Steam)
    Write-Log ("좀보이드 폴더: {0}" -f $Game.GameDir)
    Write-Log ("창작마당 폴더: {0}" -f $Game.WorkshopDir)
    if ($User) { Write-Log ("마지막 로그인 계정 번호: {0}" -f $User.AccountId) } else { Write-Log '마지막 로그인 계정: 찾지 못함' }

    # ② 모음집 페이지 열기
    Start-Process ('steam://url/CommunityFilePage/' + $Config.collectionId)
    Start-Sleep -Seconds 2
    Show-Msg "스팀에 GTC 모음집 페이지가 열렸습니다.`n초록색 '모두 구독' 버튼을 누른 뒤 [확인]을 누르세요." 'OK' 'Information' | Out-Null

    # ② 다운로드 확인 진행 창
    $script:Cancelled = $false
    $script:Done = $false
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.Font = $UiFont
    $form.ClientSize = New-Object System.Drawing.Size(440, 160)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.TopMost = $true

    $label = New-Object System.Windows.Forms.Label
    $label.Location = New-Object System.Drawing.Point(20, 20)
    $label.Size = New-Object System.Drawing.Size(400, 30)
    $label.Font = New-Object System.Drawing.Font('Malgun Gothic', 12, [System.Drawing.FontStyle]::Bold)
    $label.Text = ("모드 받는 중: {0}개 중 0개" -f $Total)
    $form.Controls.Add($label)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Location = New-Object System.Drawing.Point(20, 58)
    $hint.Size = New-Object System.Drawing.Size(400, 44)
    $hint.Text = '진행 상황은 스팀 라이브러리 → 다운로드에서도 볼 수 있습니다.'
    $form.Controls.Add($hint)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = '취소'
    $cancel.Location = New-Object System.Drawing.Point(330, 112)
    $cancel.Size = New-Object System.Drawing.Size(90, 32)
    $cancel.Add_Click({ $script:Cancelled = $true })
    $form.Controls.Add($cancel)
    $form.Add_FormClosing({ if (-not $script:Done) { $script:Cancelled = $true } })
    $form.Show()

    $last = -1
    $lastChange = Get-Date
    $res = $null
    while ($true) {
        $res = Get-Downloaded $Game.WorkshopDir $Ids
        $label.Text = ("모드 받는 중: {0}개 중 {1}개" -f $Total, $res.Count)
        if ($res.Count -ne $last) { $last = $res.Count; $lastChange = Get-Date }
        if ($res.Count -ge $Total) { break }

        if (((Get-Date) - $lastChange).TotalMinutes -ge 30) {
            $form.TopMost = $false
            $a = Show-Msg "다운로드가 멈췄습니다.`n스팀 라이브러리 → 다운로드에서 일시 중지된 항목이 없는지 확인한 뒤 [다시 시도]를 누르세요." 'RetryCancel' 'Warning'
            $form.TopMost = $true
            if ($a -eq [System.Windows.Forms.DialogResult]::Cancel) { $script:Cancelled = $true }
            else { $lastChange = Get-Date }
        }
        if ($script:Cancelled) { break }

        for ($i = 0; $i -lt 100; $i++) {
            [System.Windows.Forms.Application]::DoEvents()
            if ($script:Cancelled) { break }
            Start-Sleep -Milliseconds 100
        }
        if ($script:Cancelled) { break }
    }
    $script:Done = $true
    $form.Close()

    if ($script:Cancelled) {
        Write-Log ("다운로드 확인 중 취소: {0}/{1}, 못 받은 번호: {2}" -f $res.Count, $Total, ($res.Missing -join ','))
        exit 0
    }
    Write-Log ("다운로드 완료: {0}/{1}" -f $res.Count, $Total)
    Show-Msg ("모드 {0}개를 모두 받았습니다." -f $Total) 'OK' 'Information' | Out-Null
    exit 0
}
catch {
    Write-Log ("오류: {0}" -f $_.Exception.Message)
    Show-Msg ("예상하지 못한 오류가 발생했습니다.`n아래 기록 파일을 곡천님께 보내주세요.`n{0}" -f $LogPath) 'OK' 'Error' | Out-Null
    exit 1
}
