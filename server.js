import express from "express";
import cors from "cors";
import multer from "multer";
import rateLimit from "express-rate-limit";
import dotenv from "dotenv";
import fs from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import OpenAI from "openai";
import crypto from "node:crypto";
import Database from "better-sqlite3";
import mammoth from "mammoth";
import pdf from "pdf-parse/lib/pdf-parse.js";
import XLSX from "xlsx";
import { Document, Packer, Paragraph, HeadingLevel } from "docx";
import PDFDocument from "pdfkit";

dotenv.config();
const app = express();
app.use(cors());
app.use(express.json({ limit: "2mb" }));
app.use(express.urlencoded({ extended: false }));
app.use("/api/", rateLimit({ windowMs: 60_000, limit: 30 }));
const upload = multer({ dest: os.tmpdir(), limits: { fileSize: 20 * 1024 * 1024, files: 2 } });
const client = process.env.AI_API_KEY && process.env.AI_API_KEY !== "YOUR_SERVER_SIDE_API_KEY"
  ? new OpenAI({ apiKey: process.env.AI_API_KEY }) : null;

// iyzico Checkout Form — one-time lifetime Premium (299.00 TRY)
const IYZICO_API_KEY = process.env.IYZICO_API_KEY || '';
const IYZICO_SECRET_KEY = process.env.IYZICO_SECRET_KEY || '';
const IYZICO_BASE_URL = process.env.IYZICO_BASE_URL || 'https://sandbox-api.iyzipay.com';
const PUBLIC_BASE_URL = process.env.PUBLIC_BASE_URL || '';
const db = new Database(process.env.SQLITE_PATH || './belge-asistani.sqlite');
db.pragma('journal_mode = WAL');
db.exec(`CREATE TABLE IF NOT EXISTS iyzico_payments (
  token TEXT PRIMARY KEY, installation_id TEXT NOT NULL, price TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'PENDING', created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS premium_entitlements (
  installation_id TEXT PRIMARY KEY, payment_token TEXT NOT NULL,
  payment_id TEXT NOT NULL, activated_at TEXT NOT NULL
);`);

function iyzicoAuthorization(uriPath, bodyText) {
  const randomKey = `${Date.now()}${crypto.randomInt(100000, 999999)}`;
  const signature = crypto.createHmac('sha256', IYZICO_SECRET_KEY)
    .update(randomKey + uriPath + bodyText, 'utf8').digest('hex');
  const raw = `apiKey:${IYZICO_API_KEY}&randomKey:${randomKey}&signature:${signature}`;
  return { authorization: `IYZWSv2 ${Buffer.from(raw, 'utf8').toString('base64')}`, randomKey };
}

async function iyzicoPost(uriPath, payload) {
  if (!IYZICO_API_KEY || !IYZICO_SECRET_KEY) throw new Error('iyzico API anahtarları sunucu ortamına eklenmemiş.');
  const bodyText = JSON.stringify(payload);
  const auth = iyzicoAuthorization(uriPath, bodyText);
  const response = await fetch(`${IYZICO_BASE_URL}${uriPath}`, {
    method: 'POST',
    headers: { 'Authorization': auth.authorization, 'x-iyzi-rnd': auth.randomKey, 'Content-Type': 'application/json' },
    body: bodyText
  });
  const data = await response.json();
  if (!response.ok || data.status !== 'success') {
    throw new Error(data.errorMessage || data.errorCode || 'iyzico isteği başarısız.');
  }
  return data;
}

app.post('/api/iyzico/initialize', async (req, res) => {
  try {
    if (!PUBLIC_BASE_URL.startsWith('https://')) throw new Error('PUBLIC_BASE_URL geçerli HTTPS adresi olmalı.');
    const { installationId, name, surname, email, gsmNumber, identityNumber, address, city } = req.body || {};
    if (![installationId,name,surname,email,gsmNumber,identityNumber,address,city].every(v => typeof v === 'string' && v.trim())) {
      return res.status(400).json({ error: 'Ödeme bilgileri eksik.' });
    }
    if (!/^[a-f0-9-]{36}$/i.test(installationId)) return res.status(400).json({ error: 'Geçersiz uygulama kimliği.' });
    if (!/^\d{11}$/.test(identityNumber)) return res.status(400).json({ error: 'T.C. kimlik numarası 11 rakam olmalıdır.' });
    const id = crypto.randomUUID();
    const uriPath = '/payment/iyzipos/checkoutform/initialize/auth/ecom';
    const callbackUrl = `${PUBLIC_BASE_URL.replace(/\/$/, '')}/api/iyzico/callback`;
    const payload = {
      locale: 'tr', conversationId: id, price: '299.00', paidPrice: '299.00', currency: 'TRY',
      basketId: `BELGE-${id}`, paymentGroup: 'PRODUCT', callbackUrl, enabledInstallments: [1],
      buyer: {
        id: installationId, name: name.trim(), surname: surname.trim(), identityNumber,
        email: email.trim(), gsmNumber: gsmNumber.trim(), registrationAddress: address.trim(),
        city: city.trim(), country: 'Turkey', ip: req.ip
      },
      billingAddress: { address: address.trim(), contactName: `${name.trim()} ${surname.trim()}`, city: city.trim(), country: 'Turkey' },
      shippingAddress: { address: address.trim(), contactName: `${name.trim()} ${surname.trim()}`, city: city.trim(), country: 'Turkey' },
      basketItems: [{ id: 'BELGE-ASISTANI-PREMIUM', price: '299.00', name: 'Belge Asistanı Ömür Boyu Premium', category1: 'Dijital Ürün', itemType: 'VIRTUAL' }]
    };
    const data = await iyzicoPost(uriPath, payload);
    if (!data.token || !data.paymentPageUrl) throw new Error('iyzico ödeme sayfası bağlantısı döndürmedi.');
    db.prepare('INSERT INTO iyzico_payments (token, installation_id, price, status, created_at) VALUES (?, ?, ?, ?, ?)')
      .run(data.token, installationId, '299.00', 'PENDING', new Date().toISOString());
    res.json({ paymentPageUrl: data.paymentPageUrl, token: data.token });
  } catch (e) {
    console.error('iyzico initialize error:', e.message);
    res.status(400).json({ error: e.message || 'Ödeme başlatılamadı.' });
  }
});

app.all('/api/iyzico/callback', async (req, res) => {
  try {
    const token = String(req.body?.token || req.query?.token || '');
    if (!token) return res.status(400).send('Ödeme token bilgisi bulunamadı.');
    const payment = db.prepare('SELECT * FROM iyzico_payments WHERE token = ?').get(token);
    if (!payment) return res.status(404).send('Ödeme kaydı bulunamadı.');
    const uriPath = '/payment/iyzipos/checkoutform/auth/ecom/detail';
    const result = await iyzicoPost(uriPath, { locale: 'tr', conversationId: crypto.randomUUID(), token });
    const successful = result.paymentStatus === 'SUCCESS' && Number(result.fraudStatus) === 1 &&
      Number(result.price) === 299 && Number(result.paidPrice) === 299 && result.currency === 'TRY';
    if (successful) {
      const paymentId = String(result.paymentId || '');
      if (!paymentId) throw new Error('iyzico ödeme numarası döndürmedi.');
      const tx = db.transaction(() => {
        db.prepare("UPDATE iyzico_payments SET status = 'SUCCESS' WHERE token = ?").run(token);
        db.prepare(`INSERT INTO premium_entitlements (installation_id, payment_token, payment_id, activated_at)
          VALUES (?, ?, ?, ?) ON CONFLICT(installation_id) DO UPDATE SET
          payment_token=excluded.payment_token, payment_id=excluded.payment_id, activated_at=excluded.activated_at`)
          .run(payment.installation_id, token, paymentId, new Date().toISOString());
      });
      tx();
    } else {
      db.prepare("UPDATE iyzico_payments SET status = 'NOT_APPROVED' WHERE token = ?").run(token);
    }
    res.type('html').send(`<meta charset="utf-8"><meta name="viewport" content="width=device-width"><h2>${successful ? 'Ödeme başarılı' : 'Ödeme henüz onaylanmadı'}</h2><p>${successful ? 'Belge Asistanı uygulamasına dönüp Ödemeyi kontrol et düğmesine basabilirsiniz.' : 'Ödeme doğrulanamadı. Uygulamadan tekrar kontrol edebilirsiniz.'}</p>`);
  } catch (e) {
    console.error('iyzico callback error:', e.message);
    res.status(400).type('text').send('Ödeme sonucu doğrulanamadı. Lütfen uygulamadan tekrar kontrol edin.');
  }
});

app.get('/api/iyzico/status/:installationId', (req, res) => {
  const id = String(req.params.installationId || '');
  if (!/^[a-f0-9-]{36}$/i.test(id)) return res.status(400).json({ error: 'Geçersiz uygulama kimliği.' });
  const entitlement = db.prepare('SELECT activated_at FROM premium_entitlements WHERE installation_id = ?').get(id);
  res.json({ premium: !!entitlement, activatedAt: entitlement?.activated_at || null });
});

async function extract(file) {
  const ext = path.extname(file.originalname).toLowerCase();
  const buf = await fs.readFile(file.path);
  if (ext === ".pdf") return (await pdf(buf)).text;
  if (ext === ".docx") return (await mammoth.extractRawText({ buffer: buf })).value;
  if (ext === ".txt" || ext === ".md") return buf.toString("utf8");
  if (ext === ".xlsx" || ext === ".xls" || ext === ".csv") {
    const wb = XLSX.read(buf, { type: "buffer" });
    return wb.SheetNames.map(n => `SAYFA: ${n}\n${XLSX.utils.sheet_to_csv(wb.Sheets[n])}`).join("\n\n");
  }
  throw new Error("Desteklenmeyen dosya türü. PDF, DOCX, XLSX, XLS veya TXT yükleyin.");
}
async function ai(system, user) {
  if (!client) throw new Error("Backend AI_API_KEY ayarlanmamış. backend/.env dosyasını düzenleyin.");
  const out = await client.chat.completions.create({
    model: process.env.AI_MODEL || "gpt-4o-mini",
    messages: [{ role: "system", content: system }, { role: "user", content: user }],
    temperature: 0.3
  });
  return out.choices?.[0]?.message?.content?.trim() || "Yanıt üretilemedi.";
}
const system = "Sen dikkatli bir belge asistanısın. Yalnızca verilen belge içeriğine dayan; belgede olmayan bilgileri uydurma. Belge yetersizse bunu açıkça söyle. Türkçe yanıt ver.";
app.get("/health", (_req,res)=>res.json({ok:true, service:"Belge Asistanı"}));

function requirePremium(req, res, next) {
  const id = String(req.header('x-installation-id') || '');
  if (!/^[a-f0-9-]{36}$/i.test(id)) return res.status(401).json({ error: 'Premium oturumu bulunamadı.' });
  const entitlement = db.prepare('SELECT 1 FROM premium_entitlements WHERE installation_id = ?').get(id);
  if (!entitlement) return res.status(403).json({ error: 'Bu işlem için aktif Premium satın alımı gerekir.' });
  next();
}

app.post("/api/analyze", requirePremium, upload.single("file"), async (req,res) => {
  try {
    if (!req.file) return res.status(400).json({error:"Dosya gerekli."});
    const content = (await extract(req.file)).slice(0, 90000);
    const action = String(req.body.action || "summary");
    const promptMap = {
      summary: "Belgeyi ana fikirleri, önemli ayrıntıları ve sonuçlarıyla anlaşılır biçimde özetle.",
      report: "Belgeye dayanarak başlıklar, bulgular, önemli noktalar ve sonuç içeren düzenli bir rapor hazırla.",
      translate: `Belgeyi şu dile çevir: ${String(req.body.language || "İngilizce")}. Yapıyı mümkün olduğunca koru.`,
      ask: `Kullanıcının sorusu: ${String(req.body.question || "")}\nSoruyu yalnızca belgeye dayanarak yanıtla.`,
    };
    const result = await ai(system, `${promptMap[action] || promptMap.summary}\n\nBELGE:\n${content}`);
    res.json({text:result, filename:req.file.originalname});
  } catch(e) { res.status(400).json({error:e.message || "İşlem başarısız."}); }
  finally { if(req.file) await fs.unlink(req.file.path).catch(()=>{}); }
});

app.post("/api/compare", requirePremium, upload.array("files", 2), async (req,res) => {
  try {
    if (!req.files || req.files.length !== 2) return res.status(400).json({error:"Karşılaştırmak için iki dosya yükleyin."});
    const [a,b] = await Promise.all(req.files.map(extract));
    const result = await ai(system, `İki belgeyi karşılaştır. Önce ortak noktaları, sonra farklılıkları, çelişkileri ve eksik bilgileri maddeler halinde yaz. Belge 1:\n${a.slice(0,40000)}\n\nBelge 2:\n${b.slice(0,40000)}`);
    res.json({text:result});
  } catch(e) { res.status(400).json({error:e.message || "Karşılaştırma başarısız."}); }
  finally { for(const f of req.files || []) await fs.unlink(f.path).catch(()=>{}); }
});

app.post("/api/export", requirePremium, async (req,res) => {
  try {
    const text = String(req.body.text || "").slice(0,100000);
    const format = String(req.body.format || "docx").toLowerCase();
    if (!text.trim()) return res.status(400).json({error:"Dışa aktarılacak metin boş."});
    if (format === "pdf") {
      res.setHeader("Content-Type","application/pdf");
      res.setHeader("Content-Disposition",'attachment; filename="belge-asistani.pdf"');
      const doc = new PDFDocument({margin:50}); doc.pipe(res);
      doc.font("Helvetica").fontSize(11).text(text, { lineGap:4 }); doc.end();
    } else {
      const paragraphs = text.split(/\n/).map(line => new Paragraph({text:line || " "}));
      const doc = new Document({sections:[{children:[new Paragraph({text:"Belge Asistanı Çıktısı",heading:HeadingLevel.HEADING_1}),...paragraphs]}]});
      const buffer = await Packer.toBuffer(doc);
      res.setHeader("Content-Type","application/vnd.openxmlformats-officedocument.wordprocessingml.document");
      res.setHeader("Content-Disposition",'attachment; filename="belge-asistani.docx"');
      res.send(buffer);
    }
  } catch(e) { res.status(500).json({error:e.message || "Dışa aktarma başarısız."}); }
});
app.listen(process.env.PORT || 3000, ()=>console.log(`Belge Asistanı backend :${process.env.PORT || 3000}`));
