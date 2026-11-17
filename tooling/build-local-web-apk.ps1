param(
    [ValidateSet('debug','release')][string]$Mode = 'debug',
    [string]$BuildName = '',
    [int]$BuildNumber = 0,
    [string]$BuildRoot = '',
    [string]$PythonPath = ''
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not $BuildName) {
    $manifest = Get-Content -Raw -LiteralPath (Join-Path $root 'runtime/out/arm64-v8a/assets/runtime/manifest.json') | ConvertFrom-Json
    $BuildName = $manifest.dshVersion
    if ($BuildName -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') { throw 'The runtime manifest has no valid DSH version.' }
}
if ($BuildNumber -eq 0) {
    $now = [datetime]::UtcNow.AddHours(8)
    $BuildNumber = ($now.Year - 2026) * 100000000 + $now.Month * 1000000 + $now.Day * 10000 + $now.Hour * 100 + $now.Minute
}
if ($BuildNumber -le 1) { throw 'Provide a valid, monotonically increasing build number.' }
if ($Mode -eq 'release') {
    $signingPath = Join-Path $root 'app/android/key.properties'
    if (-not (Test-Path -LiteralPath $signingPath)) {
        throw 'Release signing is required: configure app/android/key.properties with a private release keystore.'
    }
    $signing = @{}
    foreach ($line in Get-Content -LiteralPath $signingPath) {
        if ($line -match '^\s*(storeFile|storePassword|keyAlias|keyPassword)\s*=(.*)$') { $signing[$Matches[1]] = $Matches[2] }
    }
    foreach ($field in @('storeFile','storePassword','keyAlias','keyPassword')) {
        if (-not $signing.ContainsKey($field) -or [string]::IsNullOrEmpty($signing[$field])) {
            throw "Release signing configuration is missing $field."
        }
    }
    $keyPath = Join-Path (Join-Path $root 'app/android/app') $signing['storeFile']
    if (-not (Test-Path -LiteralPath $keyPath)) { throw 'The configured private release keystore is missing.' }
}
$pythonCommand = if ($PythonPath) { Get-Command $PythonPath -ErrorAction SilentlyContinue } else { Get-Command python -ErrorAction SilentlyContinue }
if (-not $pythonCommand -and -not $PythonPath) { $pythonCommand = Get-Command python3 -ErrorAction SilentlyContinue }
if (-not $pythonCommand) { throw 'Python 3 with Pillow is required. Set it on PATH for this build process.' }
$python = $pythonCommand.Source
function Invoke-Checked([string]$program, [string[]]$arguments) {
    & $program @arguments
    if ($LASTEXITCODE -ne 0) { throw "Build command failed ($LASTEXITCODE): $program" }
}
Invoke-Checked -program $python -arguments @((Join-Path $root 'tooling/make_local_web_brand.py'))
Invoke-Checked -program $python -arguments @((Join-Path $root 'tooling/check_local_web_runtime.py'), '--flavor', 'arm64', '--official')
if (-not $BuildRoot) {
    $BuildRoot = $root
    if ($root -match '[^\x00-\x7F]') {
        # AGP's Windows path guard rejects non-ASCII paths; keep a stable junction
        # for incremental output without duplicating or relocating the source.
        $BuildRoot = Join-Path $env:TEMP 'dsh-local-web-build'
        if (Test-Path -LiteralPath $BuildRoot) {
            $entry = Get-Item -LiteralPath $BuildRoot
            if ($entry.LinkType -ne 'Junction' -or $entry.Target -notcontains $root) {
                throw 'The temporary build alias already points to a different project. Supply -BuildRoot explicitly.'
            }
        } else {
            New-Item -ItemType Junction -Path $BuildRoot -Target $root | Out-Null
        }
    }
}
Push-Location (Join-Path $BuildRoot 'app')
try {
    Invoke-Checked -program 'flutter' -arguments @('pub', 'get', '--enforce-lockfile')
    Invoke-Checked -program 'flutter' -arguments @('build', 'apk', '--no-pub', "--$Mode", '--flavor', 'arm64',
        '--target-platform', 'android-arm64',
        "--dart-define=DSH_APP_VERSION=$BuildName+$BuildNumber", '--build-name', $BuildName,
        '--build-number', "$BuildNumber", '--no-android-gradle-daemon',
        '--android-project-arg=kotlin.incremental=false',
        '--android-project-arg=kotlin.compiler.execution.strategy=in-process')
} finally { Pop-Location }
$apk = Join-Path $root "app/build/app/outputs/flutter-apk/app-arm64-$Mode.apk"
if (-not (Test-Path -LiteralPath $apk)) { throw 'The expected APK was not produced.' }
$outDir = Join-Path $root 'dist'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$deliverable = Join-Path $outDir "deepseek-harness-local-$BuildName-$Mode.apk"
Copy-Item -LiteralPath $apk -Destination $deliverable -Force
Get-Item $deliverable | Select-Object FullName, Length
Get-FileHash $deliverable -Algorithm SHA256
