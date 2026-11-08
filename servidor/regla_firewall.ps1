$log = "C:\Users\Dante burguez\AppData\Local\Temp\opencode\regla_done.txt"
try {
  netsh advfirewall firewall add rule name="Control PC" dir=in action=allow protocol=TCP localport=8566
  $salida = netsh advfirewall firewall show rule name="Control PC"
  $existe = ($salida | Select-String "Control PC") -ne $null
  Set-Content -Path $log -Value ("done ok=" + $existe)
  Write-Output ""
  Write-Output "=============================================="
  if ($existe) {
    Write-Output "  REGLA DE FIREWALL AGREGADA CON EXITO"
    Write-Output "  El telefono ya puede entrar con esta PC."
  } else {
    Write-Output "  no pudo agregarse la regla"
  }
  Write-Output "  Esta ventana se cierra sola en 10 segundos..."
  Write-Output "=============================================="
  Start-Sleep 10
} catch {
  Set-Content -Path $log -Value ("error: " + $_.Exception.Message)
}
