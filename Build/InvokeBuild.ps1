<#
.Synopsis
	Build script invoked by Invoke-Build.

.Description
	TODO: Declare build parameters as standard script parameters. Parameters
	are specified directly for Invoke-Build if their names do not conflict.
	Otherwise or alternatively they are passed in as "-Parameters @{...}".
#>

# TODO: [CmdletBinding()] is optional but recommended for strict name checks.
[CmdletBinding()]
param(
)
# PSake makes variables declared here available in other scriptblocks
# Init some things
# TODO: Move some properties to script param() in order to use as parameters.

    # Find the build folder based on build system
    $ProjectRoot = $ENV:BHProjectPath
    if(-not $ProjectRoot)
    {
        $ProjectRoot = (Resolve-Path -Path "$PSScriptRoot\.." -ErrorAction Stop).Path
    }

    $Timestamp = Get-date -uformat "%Y%m%d-%H%M%S"
    $PSVersion = $PSVersionTable.PSVersion.Major
    $TestFileFormat = "TestResults_PS$PSVersion`_$TimeStamp.xml"
    $lines = '----------------------------------------------------------------------'

    $Verbose = @{}
    if($ENV:BHCommitMessage -match "!verbose")
    {
        $Verbose = @{Verbose = $True}
    }

# TODO: Default task. If it is the first then any name can be used instead.
task . Deploy

task Init {
    $lines
    Set-Location $ProjectRoot
    "Build System Details:"
    Get-Item ENV:BH*
    "`n"
}

task Test Init, {
    $lines

    foreach ($TestType in @('Unit','Integration'))
    {
        "`n`tSTATUS: $TestType testing with PowerShell $PSVersion"
        $TestFile = "{0}_{1}" -f $TestType, $TestFileFormat

        if (Test-Path -Path "$ProjectRoot\Tests\$TestType")
        {
            # Gather test results. Store them in a variable and file
            $TestResults = Invoke-Pester -Path "$ProjectRoot\Tests\$TestType" -PassThru -OutputFormat NUnitXml -OutputFile "$ProjectRoot\$TestFile"

            # In Appveyor?  Upload our tests! #Abstract this into a function?
            If($ENV:BHBuildSystem -eq 'AppVeyor')
            {
                (New-Object 'System.Net.WebClient').UploadFile(
                    "https://ci.appveyor.com/api/testresults/nunit/$($env:APPVEYOR_JOB_ID)",
                    "$ProjectRoot\$TestFile" )
            }

            Remove-Item "$ProjectRoot\$TestFile" -Force -ErrorAction SilentlyContinue

            # Failed tests?
            # Need to tell psake or it will proceed to the deployment. Danger!
            if($TestResults.FailedCount -gt 0)
            {
                throw "Failed '$($TestResults.FailedCount)' $TestType tests, build failed"
                break # break out if any of the test fails
            }
            "`n"
        }
    }
}

task Build Test, {
    $lines

    Set-Location $ProjectRoot
    # Load the module, read the exported functions, update the psd1 FunctionsToExport
    Set-ModuleFunctions

    # Bump the module version
    Try
    {
        # $Version = Get-NextPSGalleryVersion -Name $env:BHProjectName -ErrorAction Stop
        [Version]$Version  = Get-Metadata -Path $env:BHPSModuleManifest -PropertyName ModuleVersion
        $Build    = if($Version.Build    -le 0) { 0 } else { $Version.Build }
        $Revision = if($Version.Revision -le 0) { 1 } else { $Version.Revision + 1 }
        $Version  = New-Object System.Version ($Version.Major, $Version.Minor, $Build, $Revision)
        # write-Verbose "BHProjectName      - $env:BHProjectName" -Verbose
        write-Verbose "Version            - $Version" -Verbose
        # write-Verbose "BHPSModuleManifest - $env:BHPSModuleManifest" -Verbose

        Update-Metadata -Path $env:BHPSModuleManifest -PropertyName ModuleVersion -Value $Version -ErrorAction stop
    }
    Catch
    {
        "Failed to update version for '$env:BHProjectName': $_.`nContinuing with existing version"
    }
}

task Deploy Build, {
    $lines

    # $Params = @{
    #     Path = $ProjectRoot
    #     Force = $true
    #     Recurse = $false # We keep psdeploy artifacts, avoid deploying those : )
    # }
    # "Invoke-PSDeploy"
    # $Verbose
    # $Params
    # Invoke-PSDeploy @Verbose @Params

    Write-Host "Creating Nuget package" -ForegroundColor Cyan
    $ModulePackage = New-PMModulePackage -Verbose -PassThru -Path "$ProjectRoot\$(split-path $ProjectRoot -Leaf)"
    # $ModulePackage = Move-Item -path $ModulePackage -Destination "$ProjectRoot\Builds" -PassThru
    Write-Host "Signing Nuget package" -ForegroundColor Cyan
    Set-PMPackageCert `
        -path $ModulePackage.fullname `
        -CertificateFingerprint 'a6fb07f7732c7c4c1decb637e85e43902dd533ef' `
        -Timestamper 'http://sha256timestamp.ws.symantec.com/sha256/timestamp' `
        -Verbose
    Write-Host "Publishing Nuget package" -ForegroundColor Cyan
    Publish-PMPackage `
        -Path $ModulePackage.fullname `
        -FeedUrl 'https://NuGET.dev.iconic-it.com/Nuget' `
        -ApiKey '9DqH$EE3PLRT6DsW5!#3qcpq3VcJY!ZGk9Pr6ch7^XhH4mn5HKgT8pT3kpWv!7K' `
        -Verbose
    # Get-ChildItem "$ProjectRoot\Builds" | Sort-Object Name
    Remove-Item -Path $ModulePackage -Force
    Try
    {
        # $Version = Get-NextPSGalleryVersion -Name $env:BHProjectName -ErrorAction Stop
        Update-Metadata -Path $env:BHPSModuleManifest -PropertyName FunctionsToExport -Value '*' -ErrorAction stop
    }
    Catch
    {
        "Failed to set FunctionsToExport for '$env:BHProjectName': $_.`nContinuing with existing version"
    }

}
