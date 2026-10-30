<#
.SYNOPSIS
Build the keyboard-state utility with the Windows .NET Framework compiler.
.DESCRIPTION
Creates KeyboardState.exe beside this script. Does not install dependencies,
change execution policy, launch the app, or inject keyboard events.
.EXAMPLE
powershell -NoProfile -File .\KeyboardState\Build.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) {
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
}
if (-not (Test-Path -LiteralPath $compiler)) {
    throw 'The Windows .NET Framework C# compiler was not found.'
}

$destination = Join-Path $PSScriptRoot 'KeyboardState.exe'
$sources = @('KeyboardCore.cs', 'KeyboardWindow.cs') | ForEach-Object { Join-Path $PSScriptRoot $_ }
& $compiler /nologo /target:winexe /platform:anycpu /codepage:65001 /optimize+ /warnaserror+ "/out:$destination" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll $sources
if ($LASTEXITCODE -ne 0) { throw "Compiler failed: $LASTEXITCODE" }
Write-Output "Built: $destination"
