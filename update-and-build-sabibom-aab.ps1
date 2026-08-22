param(
  [string]$ProjectPath = "C:\Users\Emmanuel okom Conteh\Sabibom\sabibom"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$TargetCommit = "9db2896"
$ExpectedRemote = "MOSESALEXCONTEH/Sabibom-App"
$ExpectedVersion = "1.0.0+5"

function Assert-LastExitCode([string]$Step) {
  if ($LASTEXITCODE -ne 0) {
    throw "$Step failed with exit code $LASTEXITCODE."
  }
}

function Invoke-Native([string]$Step, [scriptblock]$Command) {
  Write-Host "`n=== $Step ===" -ForegroundColor Cyan
  & $Command
  Assert-LastExitCode $Step
}

if (-not (Test-Path -LiteralPath $ProjectPath -PathType Container)) {
  throw "Project folder was not found: $ProjectPath"
}

Push-Location $ProjectPath
try {
  if (-not (Test-Path "pubspec.yaml") -or -not (Test-Path "android" -PathType Container)) {
    throw "This is not the SabiBom Flutter Android project: $ProjectPath"
  }

  New-Item -ItemType Directory -Force "build-logs" | Out-Null
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $buildLog = Join-Path $ProjectPath "build-logs\appbundle-release-v1.0.0+5-$timestamp.log"
  $verificationFile = Join-Path $ProjectPath "build-logs\appbundle-release-v1.0.0+5-$timestamp-verification.txt"

  Invoke-Native "Confirm Git repository" { git rev-parse --is-inside-work-tree }
  $remote = (git remote get-url origin).Trim()
  Assert-LastExitCode "Read Git origin"
  if ($remote -notmatch [regex]::Escape($ExpectedRemote)) {
    throw "Wrong Git repository. Expected origin containing '$ExpectedRemote' but found '$remote'."
  }

  Write-Host "`n=== Current project status ===" -ForegroundColor Cyan
  git status --short --branch
  Assert-LastExitCode "Read Git status"

  $trackedChanges = @(git status --porcelain --untracked-files=no)
  Assert-LastExitCode "Check tracked changes"
  if ($trackedChanges.Count -eq 1 -and $trackedChanges[0] -match '^\s*M\s+pubspec\.lock$') {
    Write-Host "Discarding the previously reviewed local pubspec.lock SDK drift before updating." -ForegroundColor Yellow
    Invoke-Native "Restore tracked dependency lockfile" { git restore -- pubspec.lock }
    $trackedChanges = @()
  }
  if ($trackedChanges.Count -gt 0) {
    Write-Host ($trackedChanges -join "`n") -ForegroundColor Yellow
    throw "Tracked local changes were found. Nothing was overwritten. Commit or stash them before running this script again."
  }

  Invoke-Native "Fetch latest mobile source" { git fetch origin main }
  $head = (git rev-parse HEAD).Trim()
  Assert-LastExitCode "Read local commit"
  $originHead = (git rev-parse origin/main).Trim()
  Assert-LastExitCode "Read origin/main commit"
  $mergeBase = (git merge-base HEAD origin/main).Trim()
  Assert-LastExitCode "Compare branches"

  if ($head -eq $originHead) {
    Write-Host "Already up to date at $($head.Substring(0, 7))." -ForegroundColor Green
  } elseif ($mergeBase -eq $head) {
    Invoke-Native "Apply GitHub changes with fast-forward only" { git pull --ff-only origin main }
  } else {
    throw "The local branch has commits that are not a clean fast-forward from origin/main. Nothing was merged. Resolve the branch safely before building."
  }

  & git merge-base --is-ancestor $TargetCommit HEAD
  if ($LASTEXITCODE -ne 0) {
    throw "Required mobile release commit $TargetCommit is not present after the update."
  }

  $versionLine = (Select-String -Path "pubspec.yaml" -Pattern '^version:\s*(.+)\s*$').Matches.Groups[1].Value.Trim()
  if ($versionLine -ne $ExpectedVersion) {
    throw "Expected Flutter version $ExpectedVersion but found '$versionLine'. Do not upload an unexpected version."
  }

  $keyProperties = "android\key.properties"
  if (-not (Test-Path $keyProperties -PathType Leaf)) {
    throw "android\key.properties is missing; release signing is not configured."
  }
  $requiredSigningKeys = @("storePassword", "keyPassword", "keyAlias", "storeFile")
  $presentSigningKeys = @(
    Get-Content $keyProperties |
      Where-Object { $_ -match '=' -and $_ -notmatch '^\s*#' } |
      ForEach-Object { ($_ -split '=', 2)[0].Trim() }
  )
  foreach ($requiredKey in $requiredSigningKeys) {
    if ($presentSigningKeys -notcontains $requiredKey) {
      throw "android\key.properties is missing required key '$requiredKey'."
    }
  }
  & git check-ignore -q $keyProperties
  if ($LASTEXITCODE -ne 0) {
    throw "android\key.properties is not ignored by Git. Refusing to continue."
  }

  if (Select-String -Quiet -Path "pubspec.yaml" -Pattern '^\s*google_mobile_ads\s*:') {
    throw "The Google Mobile Ads dependency is still present in pubspec.yaml. Refusing to build."
  }
  if (Select-String -Quiet -Path "android\app\src\main\AndroidManifest.xml" -Pattern 'com\.google\.android\.gms\.ads|AD_ID') {
    throw "Google Mobile Ads metadata or the advertising ID permission is still present in the Android manifest."
  }
  if (Select-String -Quiet -Path "android\app\build.gradle.kts" -Pattern 'SABIBOM_ADMOB|sabibomAdmob') {
    throw "Obsolete AdMob release configuration is still present in Gradle."
  }

  Invoke-Native "Flutter version" { flutter --version }
  Invoke-Native "Resolve Flutter dependencies" { flutter pub get }
  Invoke-Native "Analyze Flutter source" { flutter analyze }
  Invoke-Native "Run Flutter tests" { flutter test }

  Write-Host "`n=== Build signed Android App Bundle ===" -ForegroundColor Cyan
  Write-Host "This can take a long time. Quiet periods during native compilation are normal; do not close the terminal." -ForegroundColor Yellow
  flutter build appbundle --release --build-name=1.0.0 --build-number=5 2>&1 |
    Tee-Object -FilePath $buildLog
  Assert-LastExitCode "Build signed Android App Bundle"

  $aab = Join-Path $ProjectPath "build\app\outputs\bundle\release\app-release.aab"
  if (-not (Test-Path $aab -PathType Leaf)) {
    throw "Flutter reported success but the expected AAB was not found: $aab"
  }
  $aabFile = Get-Item $aab
  if ($aabFile.Length -le 0) {
    throw "The generated AAB is empty."
  }
  if (-not (Select-String -Quiet -Path $buildLog -SimpleMatch "Built build\app\outputs\bundle\release\app-release.aab")) {
    throw "The build log does not contain Flutter's successful AAB completion line."
  }

  $signatureOutput = & jarsigner -verify $aab 2>&1
  if ($LASTEXITCODE -ne 0 -or ($signatureOutput -join "`n") -notmatch 'jar verified') {
    throw "jarsigner could not verify the generated AAB signature."
  }

  $hash = Get-FileHash $aab -Algorithm SHA256
  @(
    "SabiBom Android App Bundle verification"
    "Generated: $(Get-Date -Format o)"
    "Git commit: $((git rev-parse HEAD).Trim())"
    "Version: $ExpectedVersion"
    "Bundle: $aab"
    "Size bytes: $($aabFile.Length)"
    "SHA-256: $($hash.Hash)"
    "Signature: jar verified"
    "Build log: $buildLog"
  ) | Set-Content -Path $verificationFile -Encoding UTF8

  Write-Host "`nBUILD AND VERIFICATION SUCCEEDED" -ForegroundColor Green
  Write-Host "AAB: $aab"
  Write-Host "SHA-256: $($hash.Hash)"
  Write-Host "Build log: $buildLog"
  Write-Host "Verification: $verificationFile"
} finally {
  Pop-Location
}
