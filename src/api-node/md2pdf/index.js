
const markdownIt = require('markdown-it')({ html: true, linkify: true });
const { chromium } = require('playwright-chromium');
const { BlobServiceClient } = require('@azure/storage-blob');

module.exports = async function (context, req) {
  try {
    const { markdownPath } = req.body || {};
    if (!markdownPath) return (context.res = { status: 400, body: 'markdownPath required' });

    const conn = process.env.STORAGE_CONNECTION || process.env.AzureWebJobsStorage;
    const container = process.env.RUNBOOKS_CONTAINER || 'runbooks';

    const blobSvc = BlobServiceClient.fromConnectionString(conn);
    const cont = blobSvc.getContainerClient(container);
    const mdBlob = cont.getBlobClient(markdownPath);
    const dl = await mdBlob.download();
    const chunks = [];
    for await (const c of dl.readableStreamBody) chunks.push(c);
    const mdText = Buffer.concat(chunks).toString('utf8');

    const html = `<!doctype html><html><head><meta charset="utf-8"/>
<style>body{font-family:Segoe UI,Arial,sans-serif;margin:24px}h1,h2,h3{color:#1b1b1b}pre,code{background:#f5f7f9;padding:2px 4px}table{border-collapse:collapse}table,th,td{border:1px solid #e1e4e8}th,td{padding:6px 8px}</style></head><body>${markdownIt.render(mdText)}</body></html>`;

    const browser = await chromium.launch();
    const page = await browser.newPage();
    await page.setContent(html, { waitUntil: 'load' });
    const pdf = await page.pdf({ format: 'A4', printBackground: true, margin: { top: '14mm', bottom: '14mm', left: '12mm', right: '12mm' }});
    await browser.close();

    const pdfPath = markdownPath.replace(/\.md$/, '.pdf');
    const pdfBlob = cont.getBlockBlobClient(pdfPath);
    await pdfBlob.uploadData(Buffer.from(pdf), { overwrite: true });

    context.res = { status: 200, body: { status: 'ok', pdfPath } };
  } catch (e) {
    context.log.error(e);
    context.res = { status: 500, body: e.message };
  }
}
