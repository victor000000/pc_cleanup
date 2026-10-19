@{
    IncludeRules = @(
        'PSAvoidUsingInvokeExpression'
        'PSAvoidUsingPlainTextForPassword'
        'PSAvoidUsingConvertToSecureStringWithPlainText'
        'PSAvoidUsingUsernameAndPasswordParams'
        'PSUsePSCredentialType'
        'PSAvoidUsingComputerNameHardcoded'
        'PSAvoidUsingBrokenHashAlgorithms'
        'PSAvoidUsingEmptyCatchBlock'
        'PSAvoidOverwritingBuiltInCmdlets'
        'PSUseBOMForUnicodeEncodedFile'
        'PSUseCompatibleSyntax'
    )
    Rules = @{
        PSUseCompatibleSyntax = @{
            Enable = $true
            TargetVersions = @('5.1', '7.0')
        }
    }
}
