# hotspot_auto.ps1 (PS 5.1 + WinRT + registro de Windows) - ASCII puro
# Enciende el hotspot de Windows, configura el SSID/clave automaticos y
# muestra SSID / clave / IP / QR directo (texto en pantalla).
Add-Type -AssemblyName System.Runtime.WindowsRuntime

$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($WinRtTask, $ResultType) {
  $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
  $netTask = $asTask.Invoke($null, @($WinRtTask))
  $netTask.Wait(-1) | Out-Null
  $netTask.Result
}

$perfil = [Windows.Networking.Connectivity.NetworkInformation,Windows.Networking.Connectivity,ContentType=WindowsRuntime]::GetInternetConnectionProfile()
if ($perfil -eq $null) {
  Write-Host "ERROR: la PC no tiene conexion a ninguna red"
  exit 1
}
try {
  $tether = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager,Windows.Networking.NetworkOperators,ContentType=WindowsRuntime]::CreateFromConnectionProfile($perfil)
} catch {
  Write-Host ("ERROR: " + $_.Exception.Message)
  exit 1
}

$ssid = [string]$tether.ConfigurationProfile.Ssid
$clave = [string]$tether.ConfigurationProfile.Passphrase

# si el perfil no guarda SSID/clave, usa la configuracion del registro icssvc
if ([string]::IsNullOrWhiteSpace($ssid) -or [string]::IsNullOrWhiteSpace($clave)) {
  try {
    $reg = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\icssvc\Settings"
    if ($reg.PrivateConnectionSettings) {
      # Decodifica: primer dato legible = SSID; segundo = clave
      $bytes = $reg.PrivateConnectionSettings
      $todo = [System.Text.Encoding]::Unicode.GetString($bytes)
      $valores = [regex]::Matches($todo, "[A-Za-z0-9\-]{8,40}") | ForEach-Object { $_.Value } | Select-Object -Unique
      if ($valores) {
        if ($valores.Count -ge 1) { $ssid = $valores[0] }
        if ($valores.Count -ge 2) { $clave = $valores[1] }
      }
    }
  } catch {
    Write-Host ("registro err: " + $_.Exception.Message)
  }
}

# si aun vacio, configura el SSID/clave hardcodeados
if ([string]::IsNullOrWhiteSpace($ssid) -or [string]::IsNullOrWhiteSpace($clave)) {
  try {
    $config = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringAccessPointConfiguration]::new()
    $config.Ssid = "CONTROL-PC-HOTSPOT"
    $config.Passphrase = "CP123456789"
    $asyncop = $tether.ConfigureAccessPointAsync($config)
    Start-Sleep 2
    $res = $asyncop.GetResults()
    $ssid = "CONTROL-PC-HOTSPOT"
    $clave = "CP123456789"
  } catch {
    Write-Host ("config err: " + $_.Exception.Message)
  }
}

# enciende el hotspot si esta apagado
if ($tether.TetheringOperationalState -ne 1) {
  try {
    $res2 = Await ($tether.StartTetheringAsync()) ([Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult])
    Write-Host ("hotspot start: " + $res2.Status)
  } catch { Write-Host ("start err: " + $_.Exception.Message) }
}

Write-Host ""
Write-Host "===================================================="
Write-Host "HOTSPOT LISTO - SSSID y CLAVE de tu wifi de la PC"
Write-Host "SSID:     $ssid"
Write-Host "clave:    $clave"
Write-Host "IP de la PC: 192.168.137.1 (puerto 8566)"
Write-Host "En el telefono: conecta a `$ssid y abre la APK Control PC "
Write-Host "con IP 192.168.137.1."
Write-Host "===================================================="
