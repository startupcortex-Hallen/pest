# Publica a integração oficial dos Correios (cotação + etiqueta + rastreio).
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File scripts/publicar-correios.ps1
#
# Teste sem contrato (etiqueta simulada):
#   powershell -ExecutionPolicy Bypass -File scripts/publicar-correios.ps1 -Simulacao
#
# Pré-requisitos:
#   - npx supabase login
#   - projeto linkado (ou informe -ProjectRef)
#   - credenciais do CWS (usuário/código de acesso) ou -Simulacao

param(
  [string]$ProjectRef = 'rudmeztnxsxipmfytuem',
  [ValidateSet('homolog', 'production', 'simulacao')]
  [string]$CorreiosEnv = 'homolog',
  [string]$Usuario,
  [string]$CodigoAcesso,
  [string]$Cnpj,
  [string]$Contrato,
  [string]$CartaoPostagem,
  [string]$Dr,
  [string]$Servicos = '03298:PAC,03220:SEDEX',
  [string]$Layout = 'PADRAO',
  [switch]$Simulacao,
  [string]$AllowedOrigins = 'https://startupcortex-hallen.github.io,http://localhost:8080'
)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
Push-Location $raiz
try {
  $modoSimulacao = $Simulacao -or ($CorreiosEnv -eq 'simulacao')

  if (-not $modoSimulacao) {
    if (-not $Usuario) {
      $Usuario = Read-Host 'Usuário do Meu Correios (em homologação, o CNPJ)'
    }
    if (-not $CodigoAcesso) {
      $secure = Read-Host 'Código de acesso do CWS (não será exibido)' -AsSecureString
      $CodigoAcesso = [System.Net.NetworkCredential]::new('', $secure).Password
    }
    if ([string]::IsNullOrWhiteSpace($Usuario) -or [string]::IsNullOrWhiteSpace($CodigoAcesso)) {
      throw 'Informe usuário e código de acesso do CWS, ou use -Simulacao.'
    }
  }

  Write-Host '== Verificando login no Supabase...'
  npx supabase projects list | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw 'Sem login. Rode: npx supabase login'
  }

  Write-Host "== Vinculando o projeto $ProjectRef..."
  npx supabase link --project-ref $ProjectRef
  if ($LASTEXITCODE -ne 0) {
    throw 'Falha ao vincular o projeto. Confira o project ref e o acesso.'
  }

  Write-Host '== Configurando secrets dos Correios...'
  $pares = @(
    "CORREIOS_ENV=$CorreiosEnv",
    "CORREIOS_SERVICOS=$Servicos",
    "CORREIOS_LAYOUT=$Layout",
    "CORREIOS_SIMULACAO=$($modoSimulacao.ToString().ToLower())",
    "ALLOWED_ORIGINS=$AllowedOrigins"
  )
  if (-not $modoSimulacao) {
    $pares += "CORREIOS_USUARIO=$Usuario"
    $pares += "CORREIOS_CODIGO_ACESSO=$CodigoAcesso"
  }
  if ($Cnpj) { $pares += "CORREIOS_CNPJ=$Cnpj" }
  if ($Contrato) { $pares += "CORREIOS_CONTRATO=$Contrato" }
  if ($CartaoPostagem) { $pares += "CORREIOS_CARTAO_POSTAGEM=$CartaoPostagem" }
  if ($Dr) { $pares += "CORREIOS_DR=$Dr" }

  $envFile = Join-Path $env:TEMP "opest-correios-$PID.env"
  [System.IO.File]::WriteAllText(
    $envFile,
    ($pares -join "`n"),
    (New-Object System.Text.UTF8Encoding($false))
  )

  try {
    npx supabase secrets set --env-file $envFile
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao configurar os secrets.' }
  } finally {
    Remove-Item -LiteralPath $envFile -Force -ErrorAction SilentlyContinue
  }

  Write-Host '== Publicando frete-cotacao...'
  npx supabase functions deploy frete-cotacao
  if ($LASTEXITCODE -ne 0) { throw 'Falha ao publicar frete-cotacao.' }

  Write-Host '== Publicando frete-etiqueta...'
  npx supabase functions deploy frete-etiqueta
  if ($LASTEXITCODE -ne 0) { throw 'Falha ao publicar frete-etiqueta.' }

  Write-Host '== Publicando frete-rastreio (sem JWT)...'
  npx supabase functions deploy frete-rastreio --no-verify-jwt
  if ($LASTEXITCODE -ne 0) { throw 'Falha ao publicar frete-rastreio.' }

  Write-Host ''
  Write-Host 'Concluído.'
  if ($modoSimulacao) {
    Write-Host 'MODO SIMULAÇÃO ativo: as etiquetas são PDFs de teste e não chamam os Correios.'
  } else {
    Write-Host "Ambiente Correios: $CorreiosEnv"
  }
  Write-Host ''
  Write-Host 'Agende o rastreio no Supabase > Integrations > Cron (a cada 15 min):'
  Write-Host "  POST https://$ProjectRef.supabase.co/functions/v1/frete-rastreio"
  Write-Host '  Header x-conciliacao-secret: (mesmo CONCILIACAO_SECRET dos pagamentos)'
} finally {
  Pop-Location
}
