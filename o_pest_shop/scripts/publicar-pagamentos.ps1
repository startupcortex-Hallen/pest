# Publica as Edge Functions de pagamento e configura os secrets.
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File scripts/publicar-pagamentos.ps1
#
# Pré-requisitos:
#   - npx supabase login (ou SUPABASE_ACCESS_TOKEN no ambiente)
#   - projeto linkado ou informar o ProjectRef
#   - token do PagBank (sandbox ou produção)

param(
  [string]$ProjectRef = 'rudmeztnxsxipmfytuem',
  [ValidateSet('sandbox', 'production')]
  [string]$PagBankEnv = 'sandbox',
  [string]$AllowedOrigins = 'https://startupcortex-hallen.github.io,http://localhost:8080',
  [string]$PagBankToken,
  [string]$ConciliacaoSecret
)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
Push-Location $raiz
try {
  if (-not $PagBankToken) {
    $secure = Read-Host 'Cole o token do PagBank (nao sera exibido)' -AsSecureString
    $PagBankToken = [System.Net.NetworkCredential]::new('', $secure).Password
  }
  if ([string]::IsNullOrWhiteSpace($PagBankToken)) {
    throw 'Token do PagBank nao informado.'
  }
  if ([string]::IsNullOrWhiteSpace($ConciliacaoSecret)) {
    $ConciliacaoSecret = [guid]::NewGuid().ToString('N')
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

  Write-Host '== Configurando secrets...'
  $envFile = Join-Path $env:TEMP "opest-pagbank-$PID.env"
  $conteudo = @(
    "PAGBANK_TOKEN=$PagBankToken",
    "PAGBANK_ENV=$PagBankEnv",
    "ALLOWED_ORIGINS=$AllowedOrigins",
    "CONCILIACAO_SECRET=$ConciliacaoSecret"
  ) -join "`n"
  [System.IO.File]::WriteAllText($envFile, $conteudo, (New-Object System.Text.UTF8Encoding($false)))

  try {
    npx supabase secrets set --env-file $envFile
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao configurar os secrets.' }
  } finally {
    Remove-Item -LiteralPath $envFile -Force -ErrorAction SilentlyContinue
  }

  Write-Host '== Publicando pagamentos...'
  npx supabase functions deploy pagamentos
  if ($LASTEXITCODE -ne 0) { throw 'Falha ao publicar a funcao pagamentos.' }

  Write-Host '== Publicando pagamentos-webhook (sem JWT)...'
  npx supabase functions deploy pagamentos-webhook --no-verify-jwt
  if ($LASTEXITCODE -ne 0) { throw 'Falha ao publicar o webhook.' }

  Write-Host '== Publicando pagamentos-conciliacao (sem JWT)...'
  npx supabase functions deploy pagamentos-conciliacao --no-verify-jwt
  if ($LASTEXITCODE -ne 0) { throw 'Falha ao publicar a conciliacao.' }

  Write-Host '== Verificando se as funcoes sairam do 404...'
  $constantes = Get-Content -LiteralPath (Join-Path $raiz 'lib\core\constants\supabase_constants.dart') -Raw
  $url = [regex]::Match($constantes, "url\s*=\s*'([^']+)'").Groups[1].Value
  $anon = [regex]::Match($constantes, "anonKey\s*=\s*'([^']+)'").Groups[1].Value
  if ($url -and $anon) {
    foreach ($funcao in @('pagamentos', 'pagamentos-webhook', 'pagamentos-conciliacao')) {
      try {
        $resp = Invoke-WebRequest -Uri "$url/functions/v1/$funcao" `
          -Method Post -Body '{}' -ContentType 'application/json' `
          -Headers @{ apikey = $anon; Authorization = "Bearer $anon" } `
          -UseBasicParsing
        Write-Host "   $funcao -> HTTP $($resp.StatusCode)"
      } catch {
        $status = $_.Exception.Response.StatusCode.value__
        if ($status -eq 404) {
          throw "$funcao continua 404. Confira o deploy no dashboard do Supabase."
        }
        Write-Host "   $funcao -> HTTP $status (ok, saiu do 404)"
      }
    }
  }

  Write-Host ''
  Write-Host 'Concluido. Agora rode o teste de sandbox descrito em docs/GO_LIVE.md.'
  Write-Host ''
  Write-Host 'Agende a conciliacao a cada 2 minutos (Supabase > Cron) chamando:'
  Write-Host "  POST $url/functions/v1/pagamentos-conciliacao"
  Write-Host "  Header x-conciliacao-secret: $ConciliacaoSecret"
} finally {
  Pop-Location
}
