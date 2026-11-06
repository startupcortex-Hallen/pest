import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const dadosDir = resolve(raiz, 'web/data');
const imgDir = resolve(raiz, 'web/img');
const basePublica = (process.env.PUBLIC_BASE_URL ??
  'https://opest.com.br').replace(/\/+$/, '');
const larguras = [300, 800, 1600];
const qualidade = Number(process.env.WEBP_QUALITY ?? 78);

let sharp;
try {
  sharp = (await import('sharp')).default;
} catch {
  console.error('Instale a dependência: npm install --save-dev sharp');
  process.exit(1);
}

function urlsDe(produto) {
  const raw = produto?.url_imagem;
  if (Array.isArray(raw)) {
    return raw.filter((url) => typeof url === 'string' && url.length > 0);
  }
  if (typeof raw === 'string' && raw.length > 0) {
    return raw.replaceAll(/[{}]/g, '').split(',').filter(Boolean);
  }
  return [];
}

async function lerJson(nome) {
  try {
    return JSON.parse(await readFile(join(dadosDir, nome), 'utf8'));
  } catch {
    return null;
  }
}

async function converter(url, produtoId) {
  const resposta = await fetch(url);
  if (!resposta.ok) {
    throw new Error(`HTTP ${resposta.status}`);
  }
  const buffer = Buffer.from(await resposta.arrayBuffer());
  const hash = createHash('sha1').update(url).digest('hex').slice(0, 12);
  const pasta = join(imgDir, 'produtos', String(produtoId));
  await mkdir(pasta, { recursive: true });

  const variantes = {};
  for (const largura of larguras) {
    const nome = `${hash}-${largura}.webp`;
    await sharp(buffer)
      .resize({ width: largura, withoutEnlargement: true })
      .webp({ quality: qualidade })
      .toFile(join(pasta, nome));
    variantes[largura] = `${basePublica}/img/produtos/${produtoId}/${nome}`;
  }
  return variantes;
}

function aplicarMapa(doc, mapa) {
  if (!doc || !Array.isArray(doc.produtos)) return;
  for (const produto of doc.produtos) {
    const novas = [];
    for (const url of urlsDe(produto)) {
      const variantes = mapa[url];
      if (!variantes) {
        novas.push(url);
        continue;
      }
      novas.push(variantes[800] ?? variantes[300] ?? variantes[1600]);
    }
    if (novas.length > 0) produto.url_imagem = novas;
  }
}

async function main() {
  const catalogo = await lerJson('catalogo.json');
  const produtosDoc = await lerJson('produtos.json');
  if (!produtosDoc) {
    throw new Error('Gere o catálogo antes: npm run catalogo');
  }

  const produtos = [
    ...(Array.isArray(produtosDoc.produtos) ? produtosDoc.produtos : []),
    ...(Array.isArray(catalogo?.produtos) ? catalogo.produtos : []),
  ];
  const porUrl = new Map();
  for (const produto of produtos) {
    for (const url of urlsDe(produto)) {
      if (!porUrl.has(url)) porUrl.set(url, produto.id);
    }
  }

  const mapa = {};
  let convertidas = 0;
  let falhas = 0;
  for (const [url, produtoId] of porUrl) {
    try {
      mapa[url] = await converter(url, produtoId);
      convertidas++;
    } catch (erro) {
      falhas++;
      console.warn(`Imagem ignorada (${url}): ${erro.message}`);
    }
  }

  aplicarMapa(produtosDoc, mapa);
  aplicarMapa(catalogo, mapa);

  await writeFile(
    join(dadosDir, 'produtos.json'),
    JSON.stringify(produtosDoc),
    'utf8',
  );
  if (catalogo) {
    await writeFile(
      join(dadosDir, 'catalogo.json'),
      JSON.stringify(catalogo),
      'utf8',
    );
  }
  await writeFile(
    join(dadosDir, 'imagens.json'),
    JSON.stringify({ base: basePublica, larguras, mapa }),
    'utf8',
  );

  console.log(
    `Imagens: ${convertidas} convertidas, ${falhas} falhas, ` +
      `${Object.keys(mapa).length} URLs mapeadas.`,
  );
}

main().catch((erro) => {
  console.error(`Falha ao otimizar imagens: ${erro.message}`);
  process.exitCode = 1;
});
