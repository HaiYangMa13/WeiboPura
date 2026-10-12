param(
  [string]$Edge = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Edge)) { throw 'Microsoft Edge not found; pass its path with -Edge.' }
$output = Join-Path $PSScriptRoot '..\images'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$output = (Resolve-Path $output).Path
$page = ([uri](Join-Path $PSScriptRoot 'index.html')).AbsoluteUri
$jobs = @(
  @{ Scene='overview'; Theme='light'; Height=1120; Name='fluo-overview-light.png' },
  @{ Scene='overview'; Theme='dark'; Height=1120; Name='fluo-overview-dark.png' },
  @{ Scene='home'; Theme='light'; Height=1040; Name='fluo-home.png' },
  @{ Scene='search'; Theme='light'; Height=1040; Name='fluo-search.png' },
  @{ Scene='detail'; Theme='dark'; Height=1040; Name='fluo-detail-dark.png' }
)
foreach ($job in $jobs) {
  $profile = Join-Path ([IO.Path]::GetTempPath()) ('fluo-showcase-' + [guid]::NewGuid().ToString('N'))
  $target = Join-Path $output $job.Name
  $url = $page + '?export=1&scene=' + $job.Scene + '&theme=' + $job.Theme
  $args = @('--headless=new', '--disable-gpu', '--disable-background-networking', '--hide-scrollbars', '--no-first-run', '--force-device-scale-factor=1', '--virtual-time-budget=2500', ('--window-size=1600,' + $job.Height), ('--user-data-dir="' + $profile + '"'), ('--screenshot="' + $target + '"'), ('"' + $url + '"'))
  $process = Start-Process -FilePath $Edge -ArgumentList $args -PassThru -RedirectStandardError ($profile + '.log')
  if (-not $process.WaitForExit(30000)) { $process.Kill(); throw ('Screenshot timed out: ' + $job.Name) }
  if (-not (Test-Path -LiteralPath $target)) { throw ('Screenshot missing: ' + $job.Name) }
  Get-Item -LiteralPath $target | Select-Object Name, Length
}
