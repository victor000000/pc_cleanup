BeforeAll {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $ProjectRoot 'tools\ProjectTools.ps1')
    function New-PassingResult {
        [pscustomobject]@{ PassedCount = 1; TotalCount = 1; FailedCount = 0; FailedContainersCount = 0; SkippedCount = 0; NotRunCount = 0 }
    }
}

Describe 'Owned source discovery' {
    BeforeEach {
        $script:FixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        foreach ($directory in @('src', 'scripts\storage', 'tools', 'tests', '.tools', '.local', 'archive', 'artifacts')) {
            $null = New-Item -ItemType Directory -Path (Join-Path $script:FixtureRoot $directory) -Force
        }
        foreach ($path in @('Test.ps1', 'PSScriptAnalyzerSettings.psd1', 'src\One.ps1', 'scripts\storage\Two.ps1', 'tools\Three.ps1', 'tests\Four.Tests.ps1', '.tools\Bad.ps1', '.local\Bad.ps1', 'archive\Bad.ps1', 'artifacts\Bad.ps1', 'src\NotAScript.ps1xml')) {
            Set-Content -LiteralPath (Join-Path $script:FixtureRoot $path) -Value '# fixture'
        }
    }
    It 'selects exact PowerShell extensions and ignores dependencies and historical files' {
        $files = @(Get-ProjectOwnedFile -ProjectRoot $script:FixtureRoot)
        $files.Count | Should -Be 6
        @($files | Where-Object { $_.Name -in @('Bad.ps1', 'NotAScript.ps1xml') }).Count | Should -Be 0
    }
    It 'excludes test fixtures from production lint targets' {
        $files = @(Get-ProjectOwnedFile -ProjectRoot $script:FixtureRoot -ProductionOnly)
        $files.Count | Should -Be 5
        @($files | Where-Object { $_.Name -eq 'Four.Tests.ps1' }).Count | Should -Be 0
    }
}

Describe 'Pinned dependency selection' {
    BeforeEach {
        $script:FixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $null = New-Item -ItemType Directory -Path (Join-Path $script:FixtureRoot 'tools') -Force
        Copy-Item -LiteralPath (Join-Path $ProjectRoot 'tools\Dependencies.psd1') -Destination (Join-Path $script:FixtureRoot 'tools\Dependencies.psd1')
        $script:Lock = Import-PowerShellDataFile -LiteralPath (Join-Path $script:FixtureRoot 'tools\Dependencies.psd1')
        $script:ModuleRoot = Join-Path $script:FixtureRoot '.tools\modules\Pester\5.5.0'
        $null = New-Item -ItemType Directory -Path $script:ModuleRoot -Force
    }
    It 'fails actionably rather than installing missing dependencies' {
        { Get-DevelopmentDependencyPath -ProjectRoot $script:FixtureRoot -Name Pester } | Should -Throw '*Install-DevDependencies.ps1*'
    }
    It 'uses exactly the locked manifest, not globally installed versions' {
        Set-Content -LiteralPath (Join-Path $script:ModuleRoot 'Pester.psd1') -Value "@{ ModuleVersion = '5.5.0' }"
        Set-Content -LiteralPath (Join-Path $script:ModuleRoot '.package-sha512') -Value $script:Lock.Modules.Pester.SHA512
        Get-DevelopmentDependencyPath -ProjectRoot $script:FixtureRoot -Name Pester | Should -Be (Join-Path $script:ModuleRoot 'Pester.psd1')
    }
    It 'rejects a different package stamp or manifest version' {
        Set-Content -LiteralPath (Join-Path $script:ModuleRoot 'Pester.psd1') -Value "@{ ModuleVersion = '6.0.0' }"
        Set-Content -LiteralPath (Join-Path $script:ModuleRoot '.package-sha512') -Value 'wrong'
        { Get-DevelopmentDependencyPath -ProjectRoot $script:FixtureRoot -Name Pester } | Should -Throw '*stamp differs*'
        Set-Content -LiteralPath (Join-Path $script:ModuleRoot '.package-sha512') -Value $script:Lock.Modules.Pester.SHA512
        { Get-DevelopmentDependencyPath -ProjectRoot $script:FixtureRoot -Name Pester } | Should -Throw '*Wrong module version*'
    }
}

Describe 'Test result gate' {
    It 'accepts successful complete results' {
        { Assert-ProjectTestResult -Result (New-PassingResult) } | Should -Not -Throw
    }
    It 'rejects failures, discovery failures, skipped and unrun cases' -ForEach @(
        @{ Property = 'FailedCount' }, @{ Property = 'FailedContainersCount' },
        @{ Property = 'SkippedCount' }, @{ Property = 'NotRunCount' }
    ) {
        $result = New-PassingResult
        $result.$Property = 1
        { Assert-ProjectTestResult -Result $result } | Should -Throw '*Test gate failed*'
    }
    It 'rejects an empty test run or malformed result' {
        $result = New-PassingResult
        $result.TotalCount = 0
        { Assert-ProjectTestResult -Result $result } | Should -Throw '*Test gate failed*'
        { Assert-ProjectTestResult -Result ([pscustomobject]@{ TotalCount = 1 }) } | Should -Throw '*missing*'
    }
    It 'rejects a result with no passing tests' {
        $result = New-PassingResult
        $result.PassedCount = 0
        { Assert-ProjectTestResult -Result $result } | Should -Throw '*Test gate failed*'
    }
}

Describe 'Pester configuration safety' {
    It 'disables real registry fixtures and emits NUnit results' {
        $config = Get-ProjectPesterConfiguration -ProjectRoot $ProjectRoot -OutputPath $TestDrive
        $config.TestRegistry.Enabled.Value | Should -BeFalse
        $config.Run.Exit.Value | Should -BeFalse
        $config.TestResult.Enabled.Value | Should -BeTrue
        $config.TestResult.OutputFormat.Value | Should -Be 'NUnitXml'
        $config.Run.Path.Value | Should -Be (Join-Path $ProjectRoot 'tests')
    }
    It 'limits optional coverage to reusable source, not entrypoints or vendor code' {
        $config = Get-ProjectPesterConfiguration -ProjectRoot $ProjectRoot -OutputPath $TestDrive -Coverage
        $config.CodeCoverage.Enabled.Value | Should -BeTrue
        $config.CodeCoverage.CoveragePercentTarget.Value | Should -Be 90
        $config.CodeCoverage.Path.Value.Count | Should -BeGreaterThan 0
        foreach ($path in $config.CodeCoverage.Path.Value) {
            $path | Should -Match '[\\/]src[\\/]'
            $path | Should -Not -Match '[\\/](scripts|archive|\.tools|\.local)[\\/]'
        }
    }
}

Describe 'Coverage result gate' {
    It 'accepts measured coverage at the required minimum' {
        { Assert-ProjectCoverageResult -Result ([pscustomobject]@{ CommandsAnalyzedCount = 100; CoveragePercent = 90 }) -MinimumPercent 90 } | Should -Not -Throw
    }
    It 'rejects missing, empty, and below-target coverage' {
        { Assert-ProjectCoverageResult -Result $null -MinimumPercent 90 } | Should -Throw '*missing or empty*'
        { Assert-ProjectCoverageResult -Result ([pscustomobject]@{ CommandsAnalyzedCount = 0; CoveragePercent = 100 }) -MinimumPercent 90 } | Should -Throw '*missing or empty*'
        { Assert-ProjectCoverageResult -Result ([pscustomobject]@{ CommandsAnalyzedCount = 100; CoveragePercent = 89.99 }) -MinimumPercent 90 } | Should -Throw '*required 90*'
    }
    It 'rejects invalid numeric coverage values' {
        foreach ($percent in @([double]::NaN, [double]::PositiveInfinity, 101)) {
            { Assert-ProjectCoverageResult -Result ([pscustomobject]@{ CommandsAnalyzedCount = 100; CoveragePercent = $percent }) -MinimumPercent 90 } | Should -Throw '*Coverage gate failed*'
        }
    }
}

Describe 'Validation orchestration' {
    BeforeEach {
        Mock Import-ProjectDependency {}
        Mock Invoke-ProjectLint {}
        Mock Get-ProjectPesterConfiguration { New-PesterConfiguration }
        Mock Invoke-Pester { New-PassingResult }
        $script:Output = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    }
    It 'still runs tests and retains results if lint fails' {
        Mock Invoke-ProjectLint { throw 'synthetic lint failure' }
        { Invoke-ProjectValidation -ProjectRoot $ProjectRoot -OutputPath $script:Output } | Should -Throw '*synthetic lint failure*'
        Should -Invoke Invoke-Pester -Times 1 -Exactly
        Test-Path -LiteralPath (Join-Path $script:Output 'environment.json') | Should -BeTrue
    }
    It 'propagates test discovery failures' {
        Mock Invoke-Pester { $r = New-PassingResult; $r.FailedContainersCount = 1; $r }
        { Invoke-ProjectValidation -ProjectRoot $ProjectRoot -OutputPath $script:Output } | Should -Throw '*Test gate failed*'
    }
    It 'supports a diagnostic tests-only run without weakening the default gate' {
        Invoke-ProjectValidation -ProjectRoot $ProjectRoot -OutputPath $script:Output -SkipLint
        Should -Invoke Invoke-ProjectLint -Times 0
        Should -Invoke Invoke-Pester -Times 1 -Exactly
    }
}
