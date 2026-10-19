# Pester 5.5.0. Filesystem reports use temporary fixtures only. Every LAN
# constructor is a throwing tripwire unless replaced by a disposable fake.
BeforeAll {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
    $ReportsPath = Join-Path $ProjectRoot 'scripts\reports'
    $LanPath = Join-Path $ProjectRoot 'scripts\diagnostics\Scan-Lan.ps1'
    . (Join-Path $ProjectRoot 'src\DirectoryScan.ps1')

    # Supply throwing fallbacks so mocking is safe on hosts without Windows
    # modules/native commands. A missing command must not weaken the tripwires.
    if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
        function Get-CimInstance { throw 'Real CIM access is forbidden.' }
    }
    if (-not (Get-Command Get-Disk -ErrorAction SilentlyContinue)) {
        function Get-Disk { throw 'Real disk inventory is forbidden.' }
    }
    if (-not (Get-Command powercfg -ErrorAction SilentlyContinue)) {
        function powercfg { throw 'Real power configuration access is forbidden.' }
    }

    function New-ReportTestFile([string]$Path, [int]$Bytes) {
        [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
        [System.IO.File]::WriteAllBytes($Path, (New-Object byte[] $Bytes))
    }

    function New-FakeLanPing {
        $fake = [pscustomobject]@{
            Status = [System.Net.NetworkInformation.IPStatus]::Success
            ThrowOnSend = $false
            DisposeCount = 0
            Calls = [System.Collections.Generic.List[object]]::new()
        }
        $fake | Add-Member ScriptMethod Send {
            param($Address, $Timeout)
            $this.Calls.Add([pscustomobject]@{ Address = $Address; Timeout = $Timeout })
            if ($this.ThrowOnSend) { throw 'fixture ping failure' }
            [pscustomobject]@{ Status = $this.Status }
        }
        $fake | Add-Member ScriptMethod Dispose { $this.DisposeCount++ }
        $fake
    }

    function New-FakeLanTcpClient {
        $wait = [pscustomobject]@{
            Completed = $true
            ThrowOnWait = $false
            DisposeCount = 0
            Timeouts = [System.Collections.Generic.List[int]]::new()
        }
        $wait | Add-Member ScriptMethod WaitOne {
            param($Timeout)
            $this.Timeouts.Add($Timeout)
            if ($this.ThrowOnWait) { throw 'fixture wait failure' }
            $this.Completed
        }
        $wait | Add-Member ScriptMethod Dispose { $this.DisposeCount++ }
        $fake = [pscustomobject]@{
            Connected = $true
            ThrowOnBegin = $false
            ThrowOnEnd = $false
            DisposeCount = 0
            EndCount = 0
            WaitHandle = $wait
            Calls = [System.Collections.Generic.List[object]]::new()
        }
        $fake | Add-Member ScriptMethod BeginConnect {
            param($Address, $Port, $Callback, $State)
            $this.Calls.Add([pscustomobject]@{ Address = $Address; Port = $Port })
            if ($this.ThrowOnBegin) { throw 'fixture connect failure' }
            [pscustomobject]@{ AsyncWaitHandle = $this.WaitHandle }
        }
        $fake | Add-Member ScriptMethod EndConnect {
            param($Pending)
            $this.EndCount++
            if ($this.ThrowOnEnd) { throw 'fixture connection refused' }
        }
        $fake | Add-Member ScriptMethod Dispose { $this.DisposeCount++ }
        $fake
    }
}

Describe 'Reports are metadata-only and independent of the working directory' {
    BeforeEach {
        Mock Get-CimInstance { throw 'Real CIM access is forbidden.' }
        Mock Get-Disk { throw 'Real disk inventory is forbidden.' }
        Mock powercfg { throw 'Real power configuration access is forbidden.' }
        Mock Add-Type { throw 'Native interop is forbidden.' }
        Mock Start-Process { throw 'Launching processes is forbidden.' }
        Mock Get-Content { throw 'Reading file contents is forbidden.' }
        Mock New-Object { throw 'Network access is forbidden.' } -ParameterFilter { $TypeName -like 'System.Net.*' }
        $originalErrorPreference = $ErrorActionPreference
        $originalWarningPreference = $WarningPreference
        $originalEncoding = [Console]::OutputEncoding.WebName
        $fixtureBase = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $unicodeName = ([char]0x6D4B).ToString() + [char]0x8BD5
        $profile = Join-Path $fixtureBase ("profile [literal] $unicodeName")
        $root = Join-Path $fixtureBase ("root [literal] $unicodeName")
        $extraApp = Join-Path $fixtureBase ("extra-app [literal] $unicodeName")
        New-ReportTestFile (Join-Path $root 'root-child\data.bin') 13
        New-ReportTestFile (Join-Path $profile 'profile-child\data.bin') 17
        foreach ($relative in 'AppData\Local', 'AppData\Roaming', 'AppData\LocalLow', 'Downloads', 'Documents', 'Desktop', 'Videos', 'Pictures') {
            New-ReportTestFile (Join-Path $profile "$relative\fixture-app\data.bin") 19
        }
        New-ReportTestFile (Join-Path $root 'Windows\Temp\data.bin') 23
        New-ReportTestFile (Join-Path $root 'Windows\SoftwareDistribution\Download\data.bin') 29
        New-ReportTestFile (Join-Path $root '$Recycle.Bin\data.bin') 31
        New-ReportTestFile (Join-Path $profile 'AppData\Local\Temp\data.bin') 37
        New-ReportTestFile (Join-Path $extraApp 'explicit-app-child\data.bin') 41
        New-ReportTestFile (Join-Path $profile 'fixture-image.VHDX') 43
        New-ReportTestFile (Join-Path $profile 'fixture-large.bin') 47
        $sentinel = Join-Path $fixtureBase 'outside-sentinel.txt'
        [System.IO.File]::WriteAllText($sentinel, 'fixture sentinel must survive')
    }

    AfterEach {
        [System.IO.File]::ReadAllText($sentinel) | Should -Be 'fixture sentinel must survive'
        $ErrorActionPreference | Should -Be $originalErrorPreference
        $WarningPreference | Should -Be $originalWarningPreference
        [Console]::OutputEncoding.WebName | Should -Be $originalEncoding
        Should -Invoke Get-CimInstance -Times 0 -Exactly
        Should -Invoke Get-Disk -Times 0 -Exactly
        Should -Invoke powercfg -Times 0 -Exactly
        Should -Invoke Add-Type -Times 0 -Exactly
        Should -Invoke Start-Process -Times 0 -Exactly
        Should -Invoke Get-Content -Times 0 -Exactly
        Should -Invoke New-Object -Times 0 -Exactly -ParameterFilter { $TypeName -like 'System.Net.*' }
    }

    It '<Name> supports literal Unicode/bracket paths from an unrelated working directory' -TestCases @(
        @{ Name = 'Scan-TopLevel.ps1'; Expected = 'root-child' }
        @{ Name = 'Scan-UserProfile.ps1'; Expected = 'profile-child' }
        @{ Name = 'Scan-AppData.ps1'; Expected = 'fixture-app' }
        @{ Name = 'Scan-LargeFiles.ps1'; Expected = 'fixture-image.VHDX' }
        @{ Name = 'Get-DiskUsage.ps1'; Expected = 'root-child' }
    ) {
        param($Name, $Expected)
        $arguments = @{}
        if ($Name -in 'Scan-TopLevel.ps1', 'Get-DiskUsage.ps1') { $arguments.RootPath = $root }
        if ($Name -ne 'Scan-TopLevel.ps1') { $arguments.ProfilePath = $profile }
        Push-Location -LiteralPath $fixtureBase
        try { $output = & (Join-Path $ReportsPath $Name) @arguments | Out-String }
        finally { Pop-Location }
        $output | Should -Match ([regex]::Escape($Expected))
        $output | Should -Match ([regex]::Escape($unicodeName))
    }

    It 'Scan-AppData includes explicit optional application paths without guessing an application identity' {
        $output = & (Join-Path $ReportsPath 'Scan-AppData.ps1') -ProfilePath $profile -AppPath $extraApp | Out-String
        $output | Should -Match 'explicit-app-child'
        $output | Should -Not -Match 'safe to delete|reclaimable'
    }

    It 'Scan-LargeFiles keeps image and non-image candidates in separate lists after one traversal' {
        $output = & (Join-Path $ReportsPath 'Scan-LargeFiles.ps1') -ProfilePath $profile -MinimumFileBytes 45 | Out-String
        ([regex]::Matches($output, 'fixture-image.VHDX')).Count | Should -Be 1
        ([regex]::Matches($output, 'fixture-large.bin')).Count | Should -Be 1
        $output | Should -Not -Match 'data.bin'
    }

    It '<Name> leaves partial warnings visible for missing explicit paths despite silent caller preferences' -TestCases @(
        @{ Name = 'Scan-TopLevel.ps1' }
        @{ Name = 'Scan-UserProfile.ps1' }
        @{ Name = 'Scan-AppData.ps1' }
        @{ Name = 'Scan-LargeFiles.ps1' }
        @{ Name = 'Get-DiskUsage.ps1' }
    ) {
        param($Name)
        $arguments = @{}
        $missing = Join-Path $fixtureBase 'missing [literal]'
        if ($Name -in 'Scan-TopLevel.ps1', 'Get-DiskUsage.ps1') { $arguments.RootPath = $missing }
        if ($Name -ne 'Scan-TopLevel.ps1') { $arguments.ProfilePath = $missing }
        # A nested local scope keeps the caller-state teardown check meaningful.
        $records = & {
            $ErrorActionPreference = 'SilentlyContinue'
            $WarningPreference = 'SilentlyContinue'
            & (Join-Path $ReportsPath $Name) @arguments -WarningAction SilentlyContinue 3>&1
        }
        $warnings = @($records | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        $warnings.Count | Should -BeGreaterThan 0
        ($warnings -join ' ') | Should -Match 'Directory scan incomplete.*missing'
    }

    It 'Scan-LargeFiles skips a junction <Location> without listing its target' -TestCases @(
        @{ Location = 'root'; AsRoot = $true }
        @{ Location = 'child'; AsRoot = $false }
    ) {
        param($Location, $AsRoot)
        $target = Join-Path $fixtureBase 'outside-target'
        $outsideFile = Join-Path $target 'outside-only.vhdx'
        New-ReportTestFile $outsideFile 53
        $link = Join-Path $profile 'junction-link'
        New-Item -ItemType Junction -Path $link -Target $target -ErrorAction Stop | Out-Null
        try {
            $selectedProfile = $profile
            if ($AsRoot) { $selectedProfile = $link }
            $records = @(& (Join-Path $ReportsPath 'Scan-LargeFiles.ps1') -ProfilePath $selectedProfile 3>&1)
            $warnings = @($records | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
            $warnings.Count | Should -Be 1
            ($warnings -join ' ') | Should -Match 'incomplete.*reparse point'
            ($records | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] } | Out-String) |
                Should -Not -Match 'outside-only'
            [System.IO.FileInfo]::new($outsideFile).Length | Should -Be 53
        } finally {
            # Delete the link itself, never the fixture target.
            [System.IO.Directory]::Delete($link)
        }
    }

    It 'discovers default profile/system paths without scanning them' {
        Get-DirectoryReportDefaultPath -Kind Profile | Should -Be ([Environment]::GetFolderPath('UserProfile'))
        Get-DirectoryReportDefaultPath -Kind Root | Should -Be ($env:SystemDrive + [System.IO.Path]::DirectorySeparatorChar)
    }

    It 'has no machine-specific paths, unsafe traversal, preference assignments or OS commands in any report' {
        foreach ($file in [System.IO.Directory]::GetFiles($ReportsPath, '*.ps1')) {
            $source = [System.IO.File]::ReadAllText($file)
            $source | Should -Not -Match 'C:\\Users\\|010E047|ddda128a|powercfg|Get-CimInstance|Get-Disk\b|Get-Content|\$ErrorActionPreference\s*=|OutputEncoding\s*='
            $source | Should -Not -Match 'Get-ChildItem[^\r\n]+-Recurse|EnumerateFiles|EnumerateDirectories'
        }
    }
}

Describe 'Shared report formatting retains exact ordering and partial results' {
    It 'sorts directory rows by bytes before rounding display sizes' {
        Mock Get-DirectoryScanChildren {
            [pscustomobject]@{ FullName = 'small'; Attributes = [System.IO.FileAttributes]::Directory }
            [pscustomobject]@{ FullName = 'large'; Attributes = [System.IO.FileAttributes]::Directory }
        }
        Mock Get-DirSize { if ($Path -eq 'small') { 1L } else { 2L } }
        $output = Show-DirectorySizeReport -Label 'fixture' -Path 'mock-only' | Out-String
        $output.IndexOf('large') | Should -BeLessThan $output.IndexOf('small')
    }

    It 'warns and skips unreadable file metadata but retains a readable sibling' {
        $bad = [pscustomobject]@{ FullName = 'unreadable.bin' }
        $bad | Add-Member ScriptProperty Length { throw 'fixture length denied' }
        $good = [pscustomobject]@{ Name = 'good.bin'; FullName = 'good.bin'; Length = 7; Extension = '.bin'; LastWriteTime = [datetime]'2026-01-01' }
        $output = @(@($bad, $good) | ConvertTo-DirectoryReportFileRow 3>&1)
        @($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count | Should -Be 1
        $rows = @($output | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })
        $rows.Count | Should -Be 1
        $rows[0].Bytes | Should -Be 7
    }
}

Describe 'Optional LAN diagnostic (all network constructors mocked)' {
    BeforeEach {
        Mock New-Object { throw 'Real network access is forbidden.' } -ParameterFilter { $TypeName -like 'System.Net.*' }
    }

    It 'requires an explicitly authorized prefix before any network object is created' {
        { & $LanPath } | Should -Throw '*authorized*'
        Should -Invoke New-Object -Times 0 -Exactly -ParameterFilter { $TypeName -like 'System.Net.*' }
    }

    It 'rejects malformed or non-private prefix <Prefix> without network access' -TestCases @(
        @{ Prefix = '' }
        @{ Prefix = '192.168' }
        @{ Prefix = '192.168.256' }
        @{ Prefix = '192.168.1.2' }
        @{ Prefix = '192.168.1/24' }
        @{ Prefix = '192.169.1' }
        @{ Prefix = '172.15.1' }
        @{ Prefix = '172.32.1' }
        @{ Prefix = '11.1.1' }
        @{ Prefix = '10.001.1' }
        @{ Prefix = '10.256.1' }
        @{ Prefix = '192.168.*' }
    ) {
        param($Prefix)
        { & $LanPath -SubnetPrefix $Prefix } | Should -Throw
        Should -Invoke New-Object -Times 0 -Exactly -ParameterFilter { $TypeName -like 'System.Net.*' }
    }

    It 'rejects out-of-bound <Name> before network access' -TestCases @(
        @{ Name = 'FirstHost'; Value = 0 }
        @{ Name = 'LastHost'; Value = 255 }
        @{ Name = 'TimeoutMs'; Value = 0 }
        @{ Name = 'TimeoutMs'; Value = 5001 }
        @{ Name = 'Ports'; Value = @(0) }
        @{ Name = 'Ports'; Value = @(65536) }
        @{ Name = 'Ports'; Value = @(1..17) }
    ) {
        param($Name, $Value)
        $arguments = @{ SubnetPrefix = '192.168.1'; $Name = $Value }
        { & $LanPath @arguments } | Should -Throw
        Should -Invoke New-Object -Times 0 -Exactly -ParameterFilter { $TypeName -like 'System.Net.*' }
    }

    It 'rejects reversed host bounds before network access' {
        { & $LanPath -SubnetPrefix '192.168.1' -FirstHost 10 -LastHost 1 } | Should -Throw '*LastHost*'
        Should -Invoke New-Object -Times 0 -Exactly -ParameterFilter { $TypeName -like 'System.Net.*' }
    }

    Context 'Disposable network fakes' {
        BeforeEach {
            $fakePing = New-FakeLanPing
            $fakeTcp = New-FakeLanTcpClient
            Mock New-Object { $fakePing } -ParameterFilter { $TypeName -eq 'System.Net.NetworkInformation.Ping' }
            Mock New-Object { $fakeTcp } -ParameterFilter { $TypeName -eq 'System.Net.Sockets.TcpClient' }
        }

        It 'accepts authorized private prefix <Prefix> with an explicitly bounded single host' -TestCases @(
            @{ Prefix = '10.255.255' }
            @{ Prefix = '172.16.0' }
            @{ Prefix = '172.31.255' }
            @{ Prefix = '192.168.0' }
        ) {
            param($Prefix)
            $result = @(& $LanPath -SubnetPrefix $Prefix -FirstHost 254 -LastHost 254 -Ports 445 -TimeoutMs 5)
            $result.Count | Should -Be 1
            $result[0].Address | Should -Be "$Prefix.254"
            $result[0].OpenPorts | Should -Be @(445)
            $fakePing.DisposeCount | Should -Be 1
            $fakeTcp.DisposeCount | Should -Be 1
            $fakeTcp.WaitHandle.DisposeCount | Should -Be 1
        }

        It 'probes only the selected hosts and unique ports, honoring timeouts and disposing all resources' {
            $result = @(& $LanPath -SubnetPrefix '192.168.12' -FirstHost 2 -LastHost 3 -Ports 445,3389,445 -TimeoutMs 7)
            $result.Count | Should -Be 2
            $fakePing.Calls.Address | Should -Be @('192.168.12.2', '192.168.12.3')
            @($fakePing.Calls | Where-Object { $_.Timeout -ne 7 }).Count | Should -Be 0
            $fakeTcp.Calls.Count | Should -Be 4
            @($fakeTcp.WaitHandle.Timeouts | Where-Object { $_ -ne 7 }).Count | Should -Be 0
            $fakePing.DisposeCount | Should -Be 2
            $fakeTcp.DisposeCount | Should -Be 4
            $fakeTcp.WaitHandle.DisposeCount | Should -Be 4
            $fakeTcp.EndCount | Should -Be 4
        }

        It 'does not connect ports when ping times out, and disposes ping' {
            $fakePing.Status = [System.Net.NetworkInformation.IPStatus]::TimedOut
            @(& $LanPath -SubnetPrefix '192.168.12' -LastHost 1).Count | Should -Be 0
            $fakePing.DisposeCount | Should -Be 1
            $fakeTcp.Calls.Count | Should -Be 0
        }

        It 'disposes ping after a send failure without connecting ports' {
            $fakePing.ThrowOnSend = $true
            @(& $LanPath -SubnetPrefix '192.168.12' -LastHost 1).Count | Should -Be 0
            $fakePing.DisposeCount | Should -Be 1
            $fakeTcp.Calls.Count | Should -Be 0
        }

        It 'disposes the socket and wait handle after a connect timeout without EndConnect' {
            $fakeTcp.WaitHandle.Completed = $false
            $result = @(& $LanPath -SubnetPrefix '192.168.12' -LastHost 1 -Ports 445)
            $result[0].OpenPorts.Count | Should -Be 0
            $fakeTcp.DisposeCount | Should -Be 1
            $fakeTcp.WaitHandle.DisposeCount | Should -Be 1
            $fakeTcp.EndCount | Should -Be 0
        }

        It 'disposes the socket after BeginConnect fails before producing a wait handle' {
            $fakeTcp.ThrowOnBegin = $true
            $result = @(& $LanPath -SubnetPrefix '192.168.12' -LastHost 1 -Ports 445)
            $result[0].OpenPorts.Count | Should -Be 0
            $fakeTcp.DisposeCount | Should -Be 1
            $fakeTcp.WaitHandle.DisposeCount | Should -Be 0
        }

        It 'disposes socket and wait handle after <Failure> fails' -TestCases @(
            @{ Failure = 'WaitOne' }
            @{ Failure = 'EndConnect' }
        ) {
            param($Failure)
            if ($Failure -eq 'WaitOne') { $fakeTcp.WaitHandle.ThrowOnWait = $true }
            else { $fakeTcp.ThrowOnEnd = $true }
            $result = @(& $LanPath -SubnetPrefix '192.168.12' -LastHost 1 -Ports 445)
            $result[0].OpenPorts.Count | Should -Be 0
            $fakeTcp.DisposeCount | Should -Be 1
            $fakeTcp.WaitHandle.DisposeCount | Should -Be 1
        }
    }
}
