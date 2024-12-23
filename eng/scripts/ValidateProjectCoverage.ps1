﻿#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Validates the code coverage policy for each project.
.DESCRIPTION
    This script compares code coverage with thresholds given in "MinCodeCoverage" property in each project.
    The script writes an error for each project that does not comply with the policy.
.PARAMETER CoberturaReportXml
    Path to the XML file to read the code coverage report from in Cobertura format
.EXAMPLE
    PS> .\ValidatePerProjectCoverage.ps1 -CoberturaReportXml .\Cobertura.xml
#>

param (
    [Parameter(Mandatory = $true, HelpMessage="Path to the XML file to read the code coverage report from")]
    [string]$CoberturaReportXml
)

function Write-Header {
    param($message, [bool]$isError);
    $color = if ($isError) { 'Red' } else { 'Green' };
    Write-Host $message -ForegroundColor $color;
    Write-Host ("=" * 80)
 }
function Get-XmlValue { param($X, $Y); return $X.SelectSingleNode($Y).'#text' }

Write-Verbose "Reading cobertura report..."
[xml]$CoberturaReport = Get-Content $CoberturaReportXml
if ($null -eq $CoberturaReport.coverage -or 
    $null -eq $CoberturaReport.coverage.packages -or
    $null -eq $CoberturaReport.coverage.packages.package -or 
    0 -eq $CoberturaReport.coverage.packages.package.count)
{
    return
}

$ProjectToMinCoverageMap = @{}

Get-ChildItem -Path src -Include '*.*sproj' -Recurse | ForEach-Object {
    $XmlDoc = [xml](Get-Content $_)
    $AssemblyName = Get-XmlValue $XmlDoc "//Project/PropertyGroup/AssemblyName"
    $MinCodeCoverage = Get-XmlValue $XmlDoc "//Project/PropertyGroup/MinCodeCoverage"

    if ([string]::IsNullOrWhiteSpace($AssemblyName)) {
        $AssemblyName = $_.BaseName
    }

    if ([string]::IsNullOrWhiteSpace($MinCodeCoverage)) {
        # Test projects may not legitimely have min code coverage set.
        Write-Warning "$AssemblyName doesn't declare 'MinCodeCoverage' property"
        return
    }

    $ProjectToMinCoverageMap[$AssemblyName] = $MinCodeCoverage
}

$esc = [char]27
$Errors = New-Object System.Collections.ArrayList
$Kudos = New-Object System.Collections.ArrayList
$ErrorsMarkdown = @();
$KudosMarkdown = @();
$FatalErrors = 0;
$Warnings = 0;

Write-Verbose "Collecting projects from code coverage report..."
$CoberturaReport.coverage.packages.package | ForEach-Object {
    $Name = $_.name
    $LineCoverage = [math]::Round([double]$_.'line-rate' * 100, 2)
    $BranchCoverage = [math]::Round([double]$_.'branch-rate' * 100, 2)
    $IsFailed = $false
    $IsWarning = $false

    Write-Verbose "Project $Name with line coverage $LineCoverage and branch coverage $BranchCoverage"

    if ($ProjectToMinCoverageMap.ContainsKey($Name)) {
        if ($ProjectToMinCoverageMap[$Name] -eq 'n/a')
        {
            Write-Host "$Name ...code coverage is not applicable"
            return
        }

        [double]$MinCodeCoverage = $ProjectToMinCoverageMap[$Name]

        # Detect the under-coverage
        if ($MinCodeCoverage -gt $LineCoverage) {
            if ($MinCodeCoverage -eq 100) {
                $ansiEscapeCode = "$esc[1m$esc[0;31m";
                $IsFailed = $true
                $FatalErrors++;
            }
            else {
                $ansiEscapeCode = "$esc[1m$esc[0;33m";
                $IsWarning = $true;
                $Warnings++;
            }

            $ErrorsMarkdown += "| $Name | Line | **$MinCodeCoverage** | $LineCoverage :small_red_triangle_down: |"
            [void]$Errors.Add(
                (
                    New-Object PSObject -Property @{
                        "Project" = $Name.Replace('Microsoft.Extensions.', 'M.E.').Replace('Microsoft.AspNetCore.', 'M.AC.');
                        "Coverage Type" = "Line";
                        "Expected" = $MinCodeCoverage;
                        "Actual" = "$($ansiEscapeCode)$($LineCoverage)$esc[0m"
                    }
                )
            )
        }

        if ($MinCodeCoverage -gt $BranchCoverage) {
            if ($MinCodeCoverage -eq 100) {
                $ansiEscapeCode = "$esc[1m$esc[0;31m";
                $IsFailed = $true
                $FatalErrors++;
            }
            else {
                $ansiEscapeCode = "$esc[1m$esc[0;33m";
                $IsWarning = $true;
                $Warnings++;
            }

            $ErrorsMarkdown += "| $Name | Branch | **$MinCodeCoverage** | $BranchCoverage :small_red_triangle_down: |"
            [void]$Errors.Add(
                (
                    New-Object PSObject -Property @{
                        "Project" = $Name.Replace('Microsoft.Extensions.', 'M.E.').Replace('Microsoft.AspNetCore.', 'M.AC.');
                        "Coverage Type" = "Branch";
                        "Expected" = $MinCodeCoverage;
                        "Actual" = "$($ansiEscapeCode)$($BranchCoverage)$esc[0m"
                    }
                )
            )
        }

        # Detect the over-coverage
        [int]$lowestReported = [math]::Min([math]::Truncate($LineCoverage), [math]::Truncate($BranchCoverage));
        Write-Debug "line: $LineCoverage, branch: $BranchCoverage, min: $lowestReported, threshold: $MinCodeCoverage"
        if ([int]$MinCodeCoverage -lt $lowestReported) {
            $KudosMarkdown += "| $Name | $MinCodeCoverage | **$lowestReported** |"
            [void]$Kudos.Add(
                (
                    New-Object PSObject -Property @{
                        "Project" = $Name.Replace('Microsoft.Extensions.', 'M.E.').Replace('Microsoft.AspNetCore.', 'M.AC.');
                        "Expected" = $MinCodeCoverage;
                        "Actual" = "$esc[1m$esc[0;32m$($lowestReported)$esc[0m";
                    }
                )
            )
        }

        if    ($IsWarning) { Write-Host "$Name" -NoNewline; Write-Host " ...missed the mark" -ForegroundColor Yellow }
        elseif ($IsFailed) { Write-Host "$Name" -NoNewline; Write-Host " ...failed validation" -ForegroundColor Red }
                      else { Write-Host "$Name" -NoNewline; Write-Host " ...ok" -ForegroundColor Green }
    }
    else {
        Write-Host "$Name ...skipping"
    }
}

if ($Kudos.Count -ne 0) {
    Write-Header -message "`r`nGood job! The coverage increased" -isError $false
    $Kudos | `
        Sort-Object Project | `
        Format-Table "Project", `
                    @{ Name="Expected"; Expression="Expected"; Width=10; Alignment = "Right" }, `
                    @{ Name="Actual"; Expression="Actual"; Width=10; Alignment = "Right" } `
                    -AutoSize -Wrap
    Write-Host "##vso[task.logissue type=warning;]Good job! The coverage increased, please update your projects"

    $KudosMarkdown = @(':tada: **Good job! The coverage increased** :tada:', 'Update `MinCodeCoverage` in the project files.', "`r`n", '| Project | Expected | Actual |', '| --- | ---: | ---: |', $KudosMarkdown, "`r`n`r`n");
}

if ($Errors.Count -ne 0) {
    Write-Header -message "`r`n[!!] Found $($Errors.Count) issues!" -isError ($Errors.Count -ne 0)
    $Errors | `
        Sort-Object Project, 'Coverage Type' | `
        Format-Table "Project", `
                    @{ Name="Expected"; Expression="Expected"; Width=10; Alignment = "Right" }, `
                    @{ Name="Actual"; Expression="Actual"; Width=10; Alignment = "Right" }, `
                    @{ Name="Coverage Type"; Expression="Coverage Type"; Width=10; Alignment = "Center" } `
                    -AutoSize -Wrap

    $ErrorsMarkdown = @(":bangbang: **Found issues** :bangbang: ", "`r`n", '| Project | Coverage Type |Expected | Actual | ', '| --- | :---: | ---: | ---: |', $ErrorsMarkdown, "`r`n`r`n");
}

# Write out markdown for publishing back to AzDO
'' | Out-File coverage-report.md -Encoding ascii
$ErrorsMarkdown | Out-File coverage-report.md -Encoding ascii -Append
$KudosMarkdown | Out-File coverage-report.md -Encoding ascii -Append

# Set the AzDO variable used by GitHubComment@0 task
[string]$markdown = Get-Content coverage-report.md -Raw
if (![string]::IsNullOrWhiteSpace($markdown)) {
    # Add link back to the Code Coverage board
    $link = "$($env:SYSTEM_COLLECTIONURI)$env:SYSTEM_TEAMPROJECT/_build/results?buildId=$env:BUILD_BUILDID&view=codecoverage-tab"
    $markdown = "$markdown`n`nFull code coverage report: $link"

    $gitHubCommentVar = '##vso[task.setvariable variable=GITHUB_COMMENT]' + $markdown.Replace("`r`n","`n").Replace("`n","%0D%0A")
    Write-Host $gitHubCommentVar
}

if ($FatalErrors -gt 0)
{
    Write-Host "`r`nBreaking issues detected."
    exit -1;
}

if ($Warnings -gt 0)
{
    Write-Host "`r`nNon-breaking issues detected."
}

if ($FatalErrors -eq 0)
{
    Write-Host "`r`nAll good, no issues detected."
    exit 0;
}

