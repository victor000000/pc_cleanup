BeforeAll {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $ProjectRoot 'src\DirectoryScan.ps1')

    function New-ScanTestFile([string]$Path, [int]$Bytes) {
        [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
        [System.IO.File]::WriteAllBytes($Path, (New-Object byte[] $Bytes))
    }

    function Get-TestDirSize([string]$Path, [ref]$Warnings) {
        # Capture the actual warning stream; PS5.1 does not reliably propagate
        # WarningVariable through the nested pipeline functions.
        $output = @(Get-DirSize -Path $Path 3>&1)
        $Warnings.Value = @($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        $output | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] }
    }
}

Describe 'Safe directory-local scans (temporary fixtures only)' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        [void][System.IO.Directory]::CreateDirectory($root)
        $junctions = New-Object 'System.Collections.Generic.List[string]'
        $warnings = @()
        $sentinel = Join-Path $TestDrive ('outside-sentinel-' + [guid]::NewGuid().ToString())
        [System.IO.File]::WriteAllText($sentinel, 'fixture sentinel must survive')
    }

    AfterEach {
        # Remove the junction itself, not its target, before Pester cleans TestDrive.
        foreach ($junction in $junctions) {
            [System.IO.Directory]::Delete($junction)
        }
        # Teardown tripwire: traversal must never alter even a sibling fixture.
        [System.IO.File]::ReadAllText($sentinel) | Should -Be 'fixture sentinel must survive'
    }

    It 'sums multiple files, nested directories and readable siblings exactly once' {
        New-ScanTestFile (Join-Path $root 'a.bin') 3
        New-ScanTestFile (Join-Path $root 'b.bin') 5
        New-ScanTestFile (Join-Path $root 'nested\c.bin') 7
        New-ScanTestFile (Join-Path $root 'nested\d.bin') 11
        New-ScanTestFile (Join-Path $root 'nested\deep\e.bin') 13
        New-ScanTestFile (Join-Path $root 'sibling\f.bin') 17

        Get-TestDirSize $root -Warnings ([ref]$warnings) | Should -Be 56
        @($warnings).Count | Should -Be 0
        $files = @(Get-DirectoryScanFiles $root)
        $files.Count | Should -Be 6
        @($files.FullName | Select-Object -Unique).Count | Should -Be 6
    }

    It 'returns one Int64 zero for an empty directory without warning' {
        $result = @(Get-TestDirSize $root -Warnings ([ref]$warnings))
        $result.Count | Should -Be 1
        $result[0] | Should -BeOfType ([long])
        $result[0] | Should -Be 0
        @($warnings).Count | Should -Be 0
    }

    It 'includes zero-byte and hidden files without reading their contents' {
        New-ScanTestFile (Join-Path $root 'zero.bin') 0
        $hidden = Join-Path $root 'hidden.bin'
        New-ScanTestFile $hidden 9
        [System.IO.File]::SetAttributes($hidden, [System.IO.FileAttributes]::Hidden)

        Get-DirSize $root | Should -Be 9
        @(Get-DirectoryScanFiles $root).Count | Should -Be 2
    }

    It 'warns for a missing root even with silent error and warning preferences' {
        $ErrorActionPreference = 'SilentlyContinue'
        $WarningPreference = 'SilentlyContinue'
        $missing = Join-Path $root 'not-here'
        $output = @(Get-DirSize $missing -ErrorAction SilentlyContinue -WarningAction SilentlyContinue 3>&1)
        @($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count | Should -Be 1
        ($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Message |
            Should -Match 'Directory scan incomplete.*not-here'
        @($output | Where-Object { $_ -is [long] })[0] | Should -Be 0
    }

    It 'does not treat a file root as an empty complete directory' {
        $file = Join-Path $root 'a.bin'
        New-ScanTestFile $file 12
        Get-TestDirSize $file -Warnings ([ref]$warnings) | Should -Be 0
        ($warnings -join ' ') | Should -Match 'incomplete.*not a directory'
    }

    It 'warns and returns zero when root enumeration is denied' {
        Mock Get-DirectoryScanFileSystemInfos { throw [System.UnauthorizedAccessException]::new('fixture denied') }
        $ErrorActionPreference = 'SilentlyContinue'
        Get-TestDirSize $root -Warnings ([ref]$warnings) | Should -Be 0
        ($warnings -join ' ') | Should -Match 'incomplete.*fixture denied'
        Should -Invoke Get-DirectoryScanFileSystemInfos -Times 1 -Exactly
    }

    It 'continues readable sibling directories when one directory is denied' {
        New-ScanTestFile (Join-Path $root 'a.bin') 3
        $denied = Join-Path $root 'denied'
        New-ScanTestFile (Join-Path $denied 'unreadable.bin') 100
        New-ScanTestFile (Join-Path $root 'readable\good.bin') 7
        New-ScanTestFile (Join-Path $root 'other\good.bin') 11
        Mock Get-DirectoryScanFileSystemInfos {
            param($Directory)
            if ($Directory.FullName -eq $denied) {
                throw [System.UnauthorizedAccessException]::new('fixture denied')
            }
            foreach ($entry in $Directory.EnumerateFileSystemInfos()) { $entry }
        }
        $ErrorActionPreference = 'SilentlyContinue'
        Get-TestDirSize $root -Warnings ([ref]$warnings) | Should -Be 21
        ($warnings -join ' ') | Should -Match 'incomplete.*denied'
        Should -Invoke Get-DirectoryScanFileSystemInfos -Times 4 -Exactly
    }

    It 'continues queued siblings when a directory vanishes before it is opened' {
        New-ScanTestFile (Join-Path $root 'readable\good.bin') 13
        $vanished = Join-Path $root 'vanished'
        [void][System.IO.Directory]::CreateDirectory($vanished)
        Mock Get-DirectoryScanFileSystemInfos {
            param($Directory)
            foreach ($entry in $Directory.EnumerateFileSystemInfos()) { $entry }
            if ($Directory.FullName -eq $root) {
                [System.IO.Directory]::Delete($vanished)
            }
        }
        Get-TestDirSize $root -Warnings ([ref]$warnings) | Should -Be 13
        ($warnings -join ' ') | Should -Match 'incomplete.*vanished'
        Should -Invoke Get-DirectoryScanFileSystemInfos -Times 2 -Exactly
    }

    It 'keeps already emitted files and queued directories after a late enumeration failure without fallback double counting' {
        New-ScanTestFile (Join-Path $root 'a.bin') 3
        New-ScanTestFile (Join-Path $root 'b.bin') 5
        New-ScanTestFile (Join-Path $root 'sibling\good.bin') 7
        Mock Get-DirectoryScanFileSystemInfos {
            param($Directory)
            foreach ($entry in $Directory.EnumerateFileSystemInfos()) { $entry }
            if ($Directory.FullName -eq $root) {
                throw [System.IO.IOException]::new('fixture late failure')
            }
        }
        Get-TestDirSize $root -Warnings ([ref]$warnings) | Should -Be 15
        ($warnings -join ' ') | Should -Match 'incomplete.*fixture late failure'
        Should -Invoke Get-DirectoryScanFileSystemInfos -Times 2 -Exactly
        Should -Invoke Get-DirectoryScanFileSystemInfos -Times 1 -Exactly -ParameterFilter { $Directory.FullName -eq $root }
    }

    It 'continues same-directory entries when entry metadata cannot be read' {
        New-ScanTestFile (Join-Path $root 'good.bin') 17
        Mock Get-DirectoryScanFileSystemInfos {
            param($Directory)
            $bad = [pscustomobject]@{ FullName = (Join-Path $root 'bad.bin') }
            $bad | Add-Member -MemberType ScriptProperty -Name Attributes -Value { throw 'fixture metadata denied' }
            $bad
            foreach ($entry in $Directory.EnumerateFileSystemInfos()) { $entry }
        }
        Get-TestDirSize $root -Warnings ([ref]$warnings) | Should -Be 17
        ($warnings -join ' ') | Should -Match 'incomplete.*cannot inspect'
    }

    It 'continues other files when a file length becomes unavailable' {
        New-ScanTestFile (Join-Path $root 'good.bin') 19
        Mock Get-DirectoryScanFileSystemInfos {
            param($Directory)
            $bad = [pscustomobject]@{
                FullName = (Join-Path $root 'bad.bin')
                Attributes = [System.IO.FileAttributes]::Normal
            }
            $bad | Add-Member -MemberType ScriptProperty -Name Length -Value { throw 'fixture length denied' }
            $bad
            foreach ($entry in $Directory.EnumerateFileSystemInfos()) { $entry }
        }
        Get-TestDirSize $root -Warnings ([ref]$warnings) | Should -Be 19
        ($warnings -join ' ') | Should -Match 'incomplete.*cannot read length.*bad.bin'
    }

    It 'skips both files and directories with unsafe <Name> attributes before reading length or enumerating them' -TestCases @(
        @{ Name = 'ReparsePoint'; Flags = 0x400 }
        @{ Name = 'Offline'; Flags = 0x1000 }
        @{ Name = 'RecallOnOpen'; Flags = 0x40000 }
        @{ Name = 'RecallOnDataAccess'; Flags = 0x400000 }
    ) {
        param($Name, $Flags)
        New-ScanTestFile (Join-Path $root 'good.bin') 23
        Mock Get-DirectoryScanFileSystemInfos {
            param($Directory)
            $unsafeFile = [pscustomobject]@{
                FullName = (Join-Path $root 'unsafe-file')
                Attributes = [long]$Flags
            }
            $unsafeFile | Add-Member -MemberType ScriptProperty -Name Length -Value { throw 'must not hydrate fixture' }
            $unsafeFile
            [pscustomobject]@{
                FullName = (Join-Path $root 'unsafe-directory')
                Attributes = [long]($Flags -bor 0x10)
            }
            foreach ($entry in $Directory.EnumerateFileSystemInfos()) { $entry }
        }
        Get-TestDirSize $root -Warnings ([ref]$warnings) | Should -Be 23
        @($warnings).Count | Should -Be 2
        ($warnings -join ' ') | Should -Not -Match 'must not hydrate'
        Should -Invoke Get-DirectoryScanFileSystemInfos -Times 1 -Exactly
    }

    It 'skips a junction root including <Suffix> without enumerating its target' -TestCases @(
        @{ Suffix = '' }
        @{ Suffix = '\' }
    ) {
        param($Suffix)
        $target = Join-Path $root 'target'
        New-ScanTestFile (Join-Path $target 'outside.bin') 101
        $link = Join-Path $root 'root-link'
        New-Item -ItemType Junction -Path $link -Target $target -ErrorAction Stop | Out-Null
        $junctions.Add($link)
        Mock Get-DirectoryScanFileSystemInfos { throw 'must not enumerate a junction root' }

        Get-TestDirSize ($link + $Suffix) -Warnings ([ref]$warnings) | Should -Be 0
        @($warnings).Count | Should -Be 1
        ($warnings -join ' ') | Should -Match 'incomplete.*reparse point'
        Should -Invoke Get-DirectoryScanFileSystemInfos -Times 0 -Exactly
    }

    It 'skips child junction targets and junction cycles but still scans regular children' {
        $target = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-ScanTestFile (Join-Path $target 'outside.bin') 101
        New-ScanTestFile (Join-Path $root 'a.bin') 3
        New-ScanTestFile (Join-Path $root 'nested\b.bin') 7
        $externalLink = Join-Path $root 'external-link'
        $cycleLink = Join-Path $root 'nested\cycle-link'
        New-Item -ItemType Junction -Path $externalLink -Target $target -ErrorAction Stop | Out-Null
        $junctions.Add($externalLink)
        New-Item -ItemType Junction -Path $cycleLink -Target $root -ErrorAction Stop | Out-Null
        $junctions.Add($cycleLink)

        Get-TestDirSize $root -Warnings ([ref]$warnings) | Should -Be 10
        @($warnings).Count | Should -Be 2
        @(Get-DirectoryScanFiles $root).Count | Should -Be 2
    }
}

Describe 'Report scanner integration (parse only; never execute the reports)' {
    It '<Name> loads the shared library and has no unsafe recursive traversal or private size variant' -TestCases @(
        @{ Name = 'Scan-TopLevel.ps1' }
        @{ Name = 'Scan-UserProfile.ps1' }
        @{ Name = 'Scan-LargeFiles.ps1' }
        @{ Name = 'Scan-AppData.ps1' }
        @{ Name = 'Get-DiskUsage.ps1' }
    ) {
        param($Name)
        $path = Join-Path (Join-Path $ProjectRoot 'scripts\reports') $Name
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
        @($parseErrors).Count | Should -Be 0
        $source = $ast.Extent.Text
        $source | Should -Match 'Split-Path -Parent \(Split-Path -Parent \$PSScriptRoot\)'
        $source | Should -Match 'Join-Path \$projectRoot ''src\\DirectoryScan.ps1'''
        $source | Should -Not -Match 'function Get-DirSize|EnumerateFiles|EnumerateDirectories|Get-ChildItem[^\r\n]+-Recurse'
    }

    It 'Scan-LargeFiles delegates both categories to one bounded report scan' {
        $path = Join-Path $ProjectRoot 'scripts\reports\Scan-LargeFiles.ps1'
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
        $calls = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'Get-DirectoryLargeFileReport'
        }, $true))
        $calls.Count | Should -Be 1
        $calls[0].Extent.Text | Should -Match ([regex]::Escape('-Path $ProfilePath -MinimumFileBytes $MinimumFileBytes -Top $Top'))
    }
}
