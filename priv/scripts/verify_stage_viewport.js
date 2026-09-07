// priv/scripts/verify_stage_viewport.js
const { spawn } = require("child_process");
const http = require("http");
const fs = require("fs");
const path = require("path");

const VIEWPORTS = [
  { width: 1512, height: 908, label: "1512x908 (14\" MacBook Pro)" },
  { width: 1366, height: 768, label: "1366x768 (Standard Laptop)" }
];

const PHASE_FIXTURES = [
  "giving",
  "writing",
  "bridging",
  "assaying",
  "reveal_3bridges",
  "reveal_6bridges",
  "closed_arc"
];

const HTML_DIR = path.resolve(__dirname, "../../tmp/stage_html");
const SCREENSHOT_DIR = path.resolve(__dirname, "../../.scratch/at-the-table/screenshots");

fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });

function wait(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function sendCDP(ws, method, params = {}) {
  return new Promise((resolve, reject) => {
    const id = Math.floor(Math.random() * 1000000);
    const handler = (event) => {
      const msg = JSON.parse(event.data);
      if (msg.id === id) {
        ws.removeEventListener("message", handler);
        if (msg.error) reject(msg.error);
        else resolve(msg.result);
      }
    };
    ws.addEventListener("message", handler);
    ws.send(JSON.stringify({ id, method, params }));
  });
}

async function main() {
  console.log("=== Verifying Stage Laptop Viewports ===");

  const chrome = spawn("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", [
    "--headless=new",
    "--disable-gpu",
    "--remote-debugging-port=9222",
    "--no-first-run",
    "--no-default-browser-check",
    "--user-data-dir=/tmp/chrome-viewport-test",
    "--disable-background-networking",
    "--disable-sync",
    "--disable-default-apps",
    "--mute-audio",
    "about:blank"
  ]);

  let wsUrl = null;
  for (let i = 0; i < 30; i++) {
    await wait(200);
    try {
      const data = await new Promise((resolve, reject) => {
        http.get("http://127.0.0.1:9222/json/version", res => {
          let body = "";
          res.on("data", chunk => body += chunk);
          res.on("end", () => resolve(JSON.parse(body)));
        }).on("error", reject);
      });
      if (data.webSocketDebuggerUrl) {
        wsUrl = data.webSocketDebuggerUrl;
        break;
      }
    } catch (e) {}
  }

  if (!wsUrl) {
    chrome.kill("SIGKILL");
    throw new Error("Could not connect to Chrome debugging port");
  }

  const browserWs = new WebSocket(wsUrl);
  await new Promise(r => browserWs.onopen = r);

  // Create a target tab
  const { targetId } = await sendCDP(browserWs, "Target.createTarget", { url: "about:blank" });
  
  // Connect to target tab
  const targets = await new Promise((resolve, reject) => {
    http.get("http://127.0.0.1:9222/json/list", res => {
      let body = "";
      res.on("data", chunk => body += chunk);
      res.on("end", () => resolve(JSON.parse(body)));
    }).on("error", reject);
  });

  const tab = targets.find(t => t.id === targetId);
  const pageWs = new WebSocket(tab.webSocketDebuggerUrl);
  await new Promise(r => pageWs.onopen = r);

  await sendCDP(pageWs, "Page.enable");
  await sendCDP(pageWs, "DOM.enable");
  await sendCDP(pageWs, "Runtime.enable");

  const results = [];
  let allPassed = true;

  for (const pageName of PHASE_FIXTURES) {
    const htmlPath = path.join(HTML_DIR, `${pageName}.html`);
    const fileUrl = `file://${htmlPath}`;

    for (const vp of VIEWPORTS) {
      // Set viewport dimensions
      await sendCDP(pageWs, "Emulation.setDeviceMetricsOverride", {
        width: vp.width,
        height: vp.height,
        deviceScaleFactor: 1,
        mobile: false
      });

      // Navigate to file
      await sendCDP(pageWs, "Page.navigate", { url: fileUrl });
      await wait(1200);

      // Measure scrollHeight vs innerHeight
      const evalRes = await sendCDP(pageWs, "Runtime.evaluate", {
        expression: `({
          scrollHeight: document.documentElement.scrollHeight,
          bodyScrollHeight: document.body.scrollHeight,
          clientHeight: document.documentElement.clientHeight,
          innerHeight: window.innerHeight,
          mainScrollHeight: document.getElementById("stage") ? document.getElementById("stage").scrollHeight : null,
          mainClientHeight: document.getElementById("stage") ? document.getElementById("stage").clientHeight : null,
          closenessFontSize: document.querySelector("[data-role=closeness]") ? window.getComputedStyle(document.querySelector("[data-role=closeness]")).fontSize : null,
          bridgeFontSize: document.querySelector("[data-bridge] .font-bold") ? window.getComputedStyle(document.querySelector("[data-bridge] .font-bold")).fontSize : null,
          bookendFontSize: document.querySelector("[data-role=bookends] span") ? window.getComputedStyle(document.querySelector("[data-role=bookends] span")).fontSize : null,
          headingFontSize: document.querySelector("h1") ? window.getComputedStyle(document.querySelector("h1")).fontSize : null
        })`,
        returnByValue: true
      });

      const metrics = evalRes.result.value;
      const overflows = metrics.scrollHeight > vp.height || metrics.bodyScrollHeight > vp.height || (metrics.mainScrollHeight && metrics.mainScrollHeight > vp.height);

      // Capture screenshot
      const screenshotRes = await sendCDP(pageWs, "Page.captureScreenshot", { format: "png" });
      const screenshotFilename = `${pageName}_${vp.width}x${vp.height}.png`;
      const screenshotPath = path.join(SCREENSHOT_DIR, screenshotFilename);
      fs.writeFileSync(screenshotPath, Buffer.from(screenshotRes.data, "base64"));

      const passed = !overflows;
      if (!passed) allPassed = false;

      results.push({
        page: pageName,
        viewport: `${vp.width}x${vp.height}`,
        passed,
        metrics,
        screenshot: screenshotFilename
      });

      console.log(
        `[${passed ? "PASS" : "FAIL"}] ${pageName.padEnd(16)} @ ${vp.viewport || `${vp.width}x${vp.height}`}: ` +
        `scrollHeight=${metrics.scrollHeight}px / viewportHeight=${vp.height}px ` +
        `(Closeness: ${metrics.closenessFontSize || "N/A"}, Bridge: ${metrics.bridgeFontSize || "N/A"}) -> ${screenshotFilename}`
      );
    }
  }

  pageWs.close();
  browserWs.close();
  chrome.kill("SIGKILL");

  console.log("\n=== Summary ===");
  console.log(`Total tests: ${results.length}`);
  console.log(`Passed: ${results.filter(r => r.passed).length}`);
  console.log(`Failed: ${results.filter(r => !r.passed).length}`);

  if (!allPassed) {
    console.error("Some viewports failed (overflow detected)!");
    process.exit(1);
  } else {
    console.log("All viewports fit above the fold without scrolling!");
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
