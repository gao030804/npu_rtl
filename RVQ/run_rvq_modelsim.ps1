# 编译并运行RVQ Core自检。兼容Windows PowerShell 5.1和PowerShell 7。
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$simBin = 'E:\modelsim_24\win64pe'
$workLib = Join-Path $projectRoot 'build\rvq_work'
$logDir = Join-Path $projectRoot 'logs'
$compileLog = Join-Path $logDir 'rvq_compile.log'
$simulationLog = Join-Path $logDir 'rvq_simulation.log'

New-Item -ItemType Directory -Force -Path $logDir | Out-Null

function Quote-NativeArgument {
    param([Parameter(Mandatory = $true)] [string] $Value)
    return '"' + $Value + '"'
}

function Invoke-ModelSimTool {
    param(
        [Parameter(Mandatory = $true)] [string] $Tool,
        [Parameter(Mandatory = $true)] [string[]] $Arguments,
        [Parameter(Mandatory = $true)] [string] $FailureMessage
    )

    $toolPath = Join-Path $simBin $Tool
    if (-not (Test-Path -LiteralPath $toolPath)) {
        throw "ModelSim executable not found: $toolPath"
    }

    $process = Start-Process -FilePath $toolPath `
        -ArgumentList $Arguments -NoNewWindow -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "$FailureMessage (exit code $($process.ExitCode))"
    }
}

if (-not (Test-Path -LiteralPath (Join-Path $workLib '_info'))) {
    Invoke-ModelSimTool -Tool 'vlib.exe' `
        -Arguments @((Quote-NativeArgument $workLib)) `
        -FailureMessage 'vlib failed'
}

$sources = @(
    'rvq_codebook_sram.v',
    'rvq_scale_align_8lane.v',
    'rvq_distance_8lane.v',
    'rvq_residual_update_8lane.v',
    'rvq_projection_64to32.v',
    'rvq_core.v',
    'tb_rvq_core.v'
) | ForEach-Object {
    Join-Path $PSScriptRoot $_
}

$compileArguments = @(
    '-work', (Quote-NativeArgument $workLib),
    '-vlog01compat',
    '-l', (Quote-NativeArgument $compileLog)
)
$compileArguments += $sources | ForEach-Object {
    Quote-NativeArgument $_
}

Invoke-ModelSimTool -Tool 'vlog.exe' `
    -Arguments $compileArguments `
    -FailureMessage "RVQ compile failed; see $compileLog"

$simulationArguments = @(
    '-c',
    '-lib', (Quote-NativeArgument $workLib),
    'tb_rvq_core',
    '-l', (Quote-NativeArgument $simulationLog),
    '-do', '"run -all; quit -f"'
)

Invoke-ModelSimTool -Tool 'vsim.exe' `
    -Arguments $simulationArguments `
    -FailureMessage "RVQ simulation failed; see $simulationLog"

Write-Host "RVQ simulation log: $simulationLog"
