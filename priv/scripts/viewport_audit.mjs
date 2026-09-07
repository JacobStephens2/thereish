import { spawn } from "child_process";
import fs from "fs";

const [,, url, widthStr, heightStr, screenshotPath, expectedSelectorsJson] = process.argv;
const width = parseInt(widthStr, 10);
const height = parseInt(heightStr, 10);
const expectedSelectors = JSON.parse(expectedSelectorsJson || "[]");

async function main() {
  const chromePath = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
  const port = 9333 + Math.floor(Math.random() * 500);
  const chrome = spawn(chromePath, [
    "--headless=new",
    `--remote-debugging-port=${port}`,
    "--disable-gpu",
    "--no-sandbox",
    `--window-size=${width},${height}`
  ]);

  try {
    let versionData = null;
    for (let i = 0; i < 30; i++) {
      try {
        const res = await fetch(`http://127.0.0.1:${port}/json/version`);
        if (res.ok) {
          versionData = await res.json();
          break;
        }
      } catch {}
      await new Promise(r => setTimeout(r, 100));
    }
    if (!versionData) throw new Error("Could not connect to Chrome CDP");

    const newPageRes = await fetch(`http://127.0.0.1:${port}/json/new?${encodeURIComponent(url)}`, { method: "PUT" });
    const target = await newPageRes.json();
    const ws = new WebSocket(target.webSocketDebuggerUrl);

    let id = 1;
    const callbacks = new Map();
    ws.onmessage = (msg) => {
      const data = JSON.parse(msg.data);
      if (data.id && callbacks.has(data.id)) {
        callbacks.get(data.id)(data);
        callbacks.delete(data.id);
      }
    };

    const send = (method, params = {}) => new Promise((resolve) => {
      const msgId = id++;
      callbacks.set(msgId, resolve);
      ws.send(JSON.stringify({ id: msgId, method, params }));
    });

    await new Promise(r => ws.onopen = r);

    await send("Emulation.setDeviceMetricsOverride", {
      width,
      height,
      deviceScaleFactor: 1,
      mobile: false
    });

    let pageReady = false;
    for (let i = 0; i < 50; i++) {
      const evalRes = await send("Runtime.evaluate", {
        expression: `(() => {
          const main = document.getElementById("stage");
          if (!main) return { ready: false };
          return { ready: true };
        })()`,
        returnByValue: true
      });
      if (evalRes.result?.value?.ready) {
        pageReady = true;
        break;
      }
      await new Promise(r => setTimeout(r, 100));
    }

    // Wait a bit for LiveView connection and layout
    await new Promise(r => setTimeout(r, 600));

    const auditRes = await send("Runtime.evaluate", {
      expression: `(() => {
        const doc = document.documentElement;
        const body = document.body;
        const main = document.getElementById("stage");
        const vh = window.innerHeight;
        const vw = window.innerWidth;

        const scrollHeight = Math.max(doc.scrollHeight, body.scrollHeight, main ? main.scrollHeight : 0);
        const scrollWidth = Math.max(doc.scrollWidth, body.scrollWidth, main ? main.scrollWidth : 0);
        const hasVerticalScroll = scrollHeight > vh;
        const hasHorizontalScroll = scrollWidth > vw;

        const results = {
          viewport: { width: vw, height: vh },
          doc: { scrollHeight, scrollWidth },
          hasVerticalScroll,
          hasHorizontalScroll,
          elements: {}
        };

        const selectors = ${JSON.stringify(expectedSelectors)};
        for (const sel of selectors) {
          const el = document.querySelector(sel);
          if (!el) {
            results.elements[sel] = { found: false };
          } else {
            const r = el.getBoundingClientRect();
            results.elements[sel] = {
              found: true,
              top: Math.round(r.top),
              bottom: Math.round(r.bottom),
              left: Math.round(r.left),
              right: Math.round(r.right),
              height: Math.round(r.height),
              width: Math.round(r.width),
              fullyVisible: r.top >= -1 && r.bottom <= vh + 1
            };
          }
        }
        return results;
      })()`,
      returnByValue: true
    });

    const metrics = auditRes.result?.result?.value;
    if (!metrics) {
      console.error("Evaluation failed:", JSON.stringify(auditRes, null, 2));
      process.exit(1);
    }

    if (screenshotPath) {
      const shotRes = await send("Page.captureScreenshot", { format: "png" });
      if (shotRes.result?.data) {
        fs.writeFileSync(screenshotPath, Buffer.from(shotRes.result.data, "base64"));
      }
    }

    ws.close();
    console.log(JSON.stringify(metrics, null, 2));

    if (metrics.hasVerticalScroll) {
      console.error(`FAIL: Viewport overflow! scrollHeight ${metrics.doc.scrollHeight} > viewport height ${metrics.viewport.height}`);
      process.exit(1);
    }
    for (const [sel, info] of Object.entries(metrics.elements)) {
      if (!info.found) {
        console.error(`FAIL: Selector not found: ${sel}`);
        process.exit(1);
      }
      if (!info.fullyVisible) {
        console.error(`FAIL: Element ${sel} not fully visible: top=${info.top}, bottom=${info.bottom}, vh=${metrics.viewport.height}`);
        process.exit(1);
      }
    }
  } finally {
    chrome.kill("SIGKILL");
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
