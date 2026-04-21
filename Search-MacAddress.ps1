# ============================================================
#  Search-MacAddress.ps1
#  Consulta la tabla MAC en múltiples switches via Telnet
# ============================================================

param(
    [string[]] $Hosts = @(
        "10.217.200.110",
        "10.217.200.111",
        "10.217.200.112",
        "10.217.200.117",
        "10.217.200.51",
        "10.217.200.52",
        "10.217.200.53",
        "10.217.200.151",
        "10.217.200.152",
        "10.217.200.153",
        "10.217.200.201",
        "10.217.200.202",
        "10.217.200.203",
        "10.217.200.81",
        "10.217.200.82",
        "10.217.200.101",
        "10.217.200.102",
        "10.217.200.103",
        "10.217.200.104",
        "10.217.200.105",
        "10.217.200.31",
        "10.217.200.32"
    ),
    [int] $Port           = 23,
    [int] $TimeoutMs      = 3000,   # Timeout de lectura por host (ms)
    [switch] $Parallel               # Usar -Parallel para consultar todos a la vez
)

# ─────────────────────────────────────────────
#  Helpers
# ─────────────────────────────────────────────

function Format-Mac {
    param([string] $Raw)
    $clean = $Raw -replace '[^a-fA-F0-9]', ''
    return $clean.ToLower()
}

function Build-Command {
    param([string] $mac)
    switch ($mac.Length) {
        12 { return "show mac-address | include $($mac.Substring(0,4)).$($mac.Substring(4,4)).$($mac.Substring(8,4))" }
        { $_ -gt 8 } { return "show mac-address | include $($mac.Substring(0,4)).$($mac.Substring(4,4)).$($mac.Substring(8))" }
        default      { return "show mac-address | include $($mac.Substring(0,4)).$($mac.Substring(4,4))." }
    }
}

function Read-Stream {
    param($stream, [int] $timeoutMs)
    $buffer   = New-Object System.Byte[] 4096
    $encoding = New-Object System.Text.AsciiEncoding
    $output   = ""
    $stream.ReadTimeout = $timeoutMs

    do {
        $gotData = $false
        try {
            $read = $stream.Read($buffer, 0, 4096)
            if ($read -gt 0) {
                $output  += $encoding.GetString($buffer, 0, $read)
                $gotData  = $true
            }
        } catch { $gotData = $false }
    } while ($gotData)

    return $output
}

function Query-Host {
    param(
        [string] $HostIP,
        [int]    $Port,
        [string] $Command,
        [int]    $TimeoutMs
    )

    $result = [PSCustomObject]@{
        Host    = $HostIP
        Status  = ""
        Output  = ""
    }

    try {
        $socket = New-Object System.Net.Sockets.TcpClient
        $connect = $socket.BeginConnect($HostIP, $Port, $null, $null)
        $waited  = $connect.AsyncWaitHandle.WaitOne(2000, $false)

        if (-not $waited) {
            $result.Status = "TIMEOUT"
            $result.Output = "No se pudo conectar (timeout 2s)"
            return $result
        }

        $socket.EndConnect($connect)
        $stream = $socket.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $writer.AutoFlush = $true

        # Pequeña pausa para que el equipo esté listo
        Start-Sleep -Milliseconds 500

        # Limpiar buffer inicial (banner del equipo)
        $stream.ReadTimeout = 800
        try {
            $buf = New-Object System.Byte[] 4096
            $null = $stream.Read($buf, 0, 4096)
        } catch {}

        # Enviar comando
        $writer.WriteLine($Command)
        $writer.Flush()
        Start-Sleep -Milliseconds 800
        $writer.WriteLine()
        $writer.Flush()

        # Leer respuesta
        $raw = Read-Stream -stream $stream -timeoutMs $TimeoutMs

        # Filtrar solo las líneas con contenido relevante (quitar basura de Telnet)
        $lines = $raw -split "`n" |
                 Where-Object { $_ -match '[0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4}' } |
                 ForEach-Object { $_.Trim() }

        if ($lines.Count -gt 0) {
            $result.Status = "ENCONTRADO"
            $result.Output = $lines -join "`n"
        } else {
            $result.Status = "SIN RESULTADO"
            $result.Output = "MAC no encontrada en este equipo"
        }

        $writer.Close()
        $stream.Close()
        $socket.Close()

    } catch {
        $result.Status = "ERROR"
        $result.Output = $_.Exception.Message
    }

    return $result
}

# ─────────────────────────────────────────────
#  Validación de entrada
# ─────────────────────────────────────────────

function Main {

    Write-Host ""
    Write-Host "══════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "   MAC Address Lookup — $($Hosts.Count) host(s) en cola" -ForegroundColor Cyan
    Write-Host "══════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    $rawMac = Read-Host "Ingrese la dirección MAC (8–12 dígitos hex)"
    $mac    = Format-Mac -Raw $rawMac

    if ($mac.Length -lt 8 -or $mac.Length -gt 12) {
        Write-Error "La dirección MAC debe tener entre 8 y 12 dígitos hexadecimales válidos."
        exit 1
    }

    $command = Build-Command -mac $mac
    Write-Host ""
    Write-Host "  Buscando: " -NoNewline
    Write-Host $mac -ForegroundColor Yellow
    Write-Host "  Comando : " -NoNewline
    Write-Host $command -ForegroundColor DarkGray
    Write-Host ""

    # ─────────────────────────────────────────
    #  Consulta (paralela o secuencial)
    # ─────────────────────────────────────────

    $results = @()

    if ($Parallel) {
        # Requiere PowerShell 7+
        $results = $Hosts | ForEach-Object -Parallel {
            $r = Query-Host -HostIP $_ -Port $using:Port -Command $using:command -TimeoutMs $using:TimeoutMs
            $r
        } -ThrottleLimit 10
    } else {
        foreach ($h in $Hosts) {
            Write-Host "  → Consultando $h ..." -ForegroundColor DarkCyan -NoNewline
            $r = Query-Host -HostIP $h -Port $Port -Command $command -TimeoutMs $TimeoutMs
            $results += $r

            $color = switch ($r.Status) {
                "ENCONTRADO"   { "Green"  }
                "SIN RESULTADO"{ "Gray"   }
                default         { "Red"    }
            }
            Write-Host " [$($r.Status)]" -ForegroundColor $color
        }
    }

    # ─────────────────────────────────────────
    #  Resumen de resultados
    # ─────────────────────────────────────────

    Write-Host ""
    Write-Host "══════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "   RESULTADOS" -ForegroundColor Cyan
    Write-Host "══════════════════════════════════════════════" -ForegroundColor Cyan

    $found = $results | Where-Object { $_.Status -eq "ENCONTRADO" }

    if ($found.Count -eq 0) {
        Write-Host ""
        Write-Host "  ✗ MAC no encontrada en ningún host." -ForegroundColor Red
    } else {
        foreach ($r in $found) {
            Write-Host ""
            Write-Host "  ✔ $($r.Host)" -ForegroundColor Green
            $r.Output -split "`n" | ForEach-Object {
                Write-Host "      $_" -ForegroundColor White
            }
        }
    }

    Write-Host ""
    Write-Host "──────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  Resumen: $($found.Count) / $($results.Count) hosts reportaron la MAC" -ForegroundColor DarkGray
    Write-Host ""

    # Mostrar errores al final, sin contaminar el output principal
    $errors = $results | Where-Object { $_.Status -eq "ERROR" -or $_.Status -eq "TIMEOUT" }
    if ($errors.Count -gt 0) {
        Write-Host "  Hosts con problemas de conexión:" -ForegroundColor DarkYellow
        foreach ($e in $errors) {
            Write-Host "    ✗ $($e.Host) — $($e.Output)" -ForegroundColor DarkYellow
        }
        Write-Host ""
    }
}

Main
