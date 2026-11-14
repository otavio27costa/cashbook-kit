# Mantem o cashbook-mcp no ar no Windows (WSL2). Rodado pelo instalar.sh, de dentro do Ubuntu.
#  1. .wslconfig: desliga o desligamento por ociosidade do WSL (sem isso o Ubuntu para ~15 s depois
#     que o ultimo terminal fecha, e o servidor cai junto).
#  2. Tarefa agendada que liga o Ubuntu quando o Windows inicia, mesmo sem ninguem entrar (precisa de
#     admin: o Windows pede a permissao), e o segura ligado com um "sleep infinity" aberto. Se voce recusar,
#     a tarefa faz o mesmo quando voce entrar no Windows. O systemd sobe o Docker e o firewall, e o Docker
#     sobe os containers (restart: unless-stopped). O instalar.sh dispara a tarefa na hora, sem reiniciar.
# Desfazer: Stop-ScheduledTask e Unregister-ScheduledTask -TaskName 'cashbook-mcp (WSL)', wsl --shutdown, e tire
# as duas linhas do .wslconfig (a copia de antes esta em .wslconfig.antes-do-cashbook).
param([Parameter(Mandatory = $true)][string]$Distro, [switch]$SoTarefaDeInicio, [string]$Usuario = '')
$ErrorActionPreference = 'Stop'
$name = 'cashbook-mcp (WSL)'
$me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name   # MAQUINA\usuario (USERDOMAIN pode vir "WORKGROUP")
$acaoArg = "-d $Distro --exec /bin/sh -c `"exec sleep infinity`""   # o processo aberto segura o WSL ligado
$action = New-ScheduledTaskAction -Execute 'wsl.exe' -Argument $acaoArg
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew   # sem limite de tempo

# sua conta (sem admin) pode disparar a tarefa: o instalar.sh liga o servidor na hora, sem reiniciar
function Grant-Run {
    $sid = (New-Object System.Security.Principal.NTAccount($me)).Translate([System.Security.Principal.SecurityIdentifier]).Value
    $svc = New-Object -ComObject Schedule.Service; $svc.Connect()
    $svc.GetFolder('\').GetTask($name).SetSecurityDescriptor("D:(A;;FA;;;BA)(A;;FA;;;SY)(A;;GRGX;;;$sid)", 0)
}

function Register-AtStartup {
    $p = New-ScheduledTaskPrincipal -UserId $me -LogonType S4U   # roda sem login e sem guardar senha
    Register-ScheduledTask -TaskName $name -Action $action -Trigger (New-ScheduledTaskTrigger -AtStartup) `
        -Principal $p -Settings $settings -Force | Out-Null
    Grant-Run
}

if ($SoTarefaDeInicio) {   # chamada elevada (janela do UAC)
    if ($Usuario -and $me -ne $Usuario) { exit 3 }   # admin de outra conta: a tarefa ficaria na conta errada
    Register-AtStartup; exit 0
}

function Set-IniValue([System.Collections.Generic.List[string]]$Lines, [string]$Section, [string]$Key, [string]$Value) {
    $header = -1; $end = $Lines.Count
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $t = $Lines[$i].Trim()
        if ($t -match '^\[(.+)\]$') {
            if ($header -ge 0) { $end = $i; break }
            if ($Matches[1].Trim() -ieq $Section) { $header = $i }
        }
    }
    if ($header -lt 0) {
        if ($Lines.Count -gt 0 -and $Lines[$Lines.Count - 1].Trim() -ne '') { $Lines.Add('') }
        $Lines.Add("[$Section]"); $Lines.Add("$Key=$Value"); return
    }
    for ($i = $header + 1; $i -lt $end; $i++) {
        if ($Lines[$i] -match "^\s*$([regex]::Escape($Key))\s*=") { $Lines[$i] = "$Key=$Value"; return }
    }
    $Lines.Insert($header + 1, "$Key=$Value")
}

$cfg = Join-Path $env:USERPROFILE '.wslconfig'
$lines = New-Object 'System.Collections.Generic.List[string]'
$antes = ''
if (Test-Path $cfg) {
    $antes = [System.IO.File]::ReadAllText($cfg)
    foreach ($l in (Get-Content -LiteralPath $cfg)) { $lines.Add($l) }
    if (-not (Test-Path "$cfg.antes-do-cashbook")) { Copy-Item -LiteralPath $cfg -Destination "$cfg.antes-do-cashbook" }
}
Set-IniValue $lines 'general' 'instanceIdleTimeout' '-1'
Set-IniValue $lines 'wsl2' 'vmIdleTimeout' '-1'
[System.IO.File]::WriteAllLines($cfg, $lines)
Write-Output "ok .wslconfig: o WSL nao desliga mais sozinho ($cfg)"

$admin = ([Security.Principal.WindowsPrincipal]$([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
function Test-BootTask {
    $t = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    return [bool]($t -and $t.Principal.UserId -and ($me -like "*\$($t.Principal.UserId)" -or $me -eq $t.Principal.UserId) -and
        ($t.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskBootTrigger' }) -and
        ($t.Actions | Where-Object { $_.Arguments -eq $acaoArg }))
}
if (-not (Test-BootTask)) {
    try {
        if ($admin) { Register-AtStartup }
        else {
            Write-Output "aviso o Windows vai pedir permissao de administrador para a tarefa de inicio: clique em Sim."
            $arg = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Distro $Distro -SoTarefaDeInicio -Usuario `"$me`""
            $pr = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -WindowStyle Hidden -ArgumentList $arg
            if ($pr.ExitCode -eq 3) { Write-Output "aviso a permissao veio de outra conta de admin; a tarefa precisa ser da sua conta." }
        }
    } catch { Write-Output "aviso tarefa de inicio nao criada: $($_.Exception.Message)" }
}
if (Test-BootTask) {
    Write-Output "ok tarefa '$name': liga o Ubuntu ($Distro) quando o Windows inicia, mesmo sem ninguem entrar"
} else {
    Register-ScheduledTask -TaskName $name -Action $action -Trigger (New-ScheduledTaskTrigger -AtLogOn -User $me) `
        -Settings $settings -Force | Out-Null
    Write-Output "ok tarefa '$name': liga o Ubuntu ($Distro) quando voce entra no Windows"
    Write-Output "aviso sem a permissao de admin, o servidor so sobe depois que alguem entra no Windows."
    Write-Output "aviso para subir sem login, rode ./instalar.sh subir de novo e aceite a janela do Windows."
}
