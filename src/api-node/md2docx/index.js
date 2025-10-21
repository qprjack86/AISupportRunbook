
const markdownIt = require('markdown-it')({ html: true, linkify: true });
const { BlobServiceClient } = require('@azure/storage-blob');
const HtmlDocx = require('html-docx-js');

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
<style>body{font-family:Segoe UI,Arial,sans-serif}h1,h2,h3{color:#1b1b1b}pre,code{background:#f5f7f9;padding:2px 4px}table{border-collapse:collapse}table,th,td{border:1px solid #e1e4e8}th,td{padding:6px 8px}</style></head><body>${markdownIt.render(mdText)}</body></html>`;

    const docxBuffer = HtmlDocx.asBlob(html);

    const docxPath = markdownPath.replace(/\.md$/, '.docx');
    const docxBlob = cont.getBlockBlobClient(docxPath);
    await docxBlob.uploadData(Buffer.from(docxBuffer), {
      blobHTTPHeaders: { blobContentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' },
      overwrite: true
    });

    context.res = { status: 200, body: { status: 'ok', docxPath } };
  } catch (e) {
    context.log.error(e);
    context.res = { status: 500, body: e.message };
  }
}
