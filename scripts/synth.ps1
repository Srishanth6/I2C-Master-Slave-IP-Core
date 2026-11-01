# Runs Yosys synthesis on Windows (OSS CAD Suite in C:\oss-cad-suite by default).
param([string]$Oss = "C:\oss-cad-suite")
$ErrorActionPreference = "Stop"
$env:PATH = "$Oss\bin;$Oss\lib;$env:PATH"
Set-Location (Split-Path $PSScriptRoot -Parent)
New-Item -ItemType Directory synth -Force | Out-Null
yosys -V | Tee-Object synth/yosys_version.txt
yosys -q -l synth/synth_full.log -s scripts/synth.ys
if ($LASTEXITCODE -ne 0) { throw "yosys failed" }
Write-Host "synthesis OK, logs in synth/"
