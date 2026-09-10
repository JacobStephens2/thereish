// priv/scripts/verify_mobile_viewport.js
const { spawn } = require("child_process");
const http = require("http");
const fs = require("fs");
const path = require("path");

const VIEWPORTS = [
  { width: 412, height: 915, label: "412x915 (Chrome Android / Galaxy S24)" },
  { width: 360, height: 780, label: "360x780 (Compact Android)" }
];

const FIXTURES = [
  "closed_phone",
  "waiting_phone"
];

const HTML_DIR = path.resolve(__dirname, "../../tmp/mobile_html");
const SCREENSHOT_DIR = path.resolve(__dirname, "../../.scratch/2026-09-07-playtest-feedback/audit");

fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });

function wait(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function fetchJson(url) {
  return new Promise((resolve, reject) => {
    http.get(url, res => {
      let body = "";
      res.on("data", chunk => (body += chunk));
      res.on("end", () => resolve(JSON.parse(body)));
    }).on("error", reject);
  });
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
  console.log("=== Verifying Mobile Phone Viewports ===");

  const port = 9444 + Math.floor(Math.random() * 500);
  const chrome = spawn("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", [
    "--headless=new",
    "--disable-gpu",
    `--remote-debugging-port=${port}`,
    "--no-first-run",
    "--no-default-browser-check",
    "--user-data-dir=/tmp/chrome-mobile-viewport-test",
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
      const data = await fetchJson(`http://127.0.0.1:${port}/json/version`);
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

  const targets = await fetchJson(`http://127.0.0.1:${port}/json/list`);

  const tab = targets.find(t => t.id === targetId);
  const pageWs = new WebSocket(tab.webSocketDebuggerUrl);
  await new Promise(r => pageWs.onopen = r);

  await sendCDP(pageWs, "Page.enable");
  await sendCDP(pageWs, "DOM.enable");
  await sendCDP(pageWs, "Runtime.enable");

  const results = [];
  let allPassed = true;

  for (const pageName of FIXTURES) {
    const htmlPath = path.join(HTML_DIR, `${pageName}.html`);
    const fileUrl = `file://${htmlPath}`;

    for (const vp of VIEWPORTS) {
      await sendCDP(pageWs, "Emulation.setDeviceMetricsOverride", {
        width: vp.width,
        height: vp.height,
        deviceScaleFactor: 2.625,
        mobile: true
      });

      await sendCDP(pageWs, "Page.navigate", { url: fileUrl });
      await wait(1000);

      const evalRes = await sendCDP(pageWs, "Runtime.evaluate", {
        expression: `(() => {
          const doc = document.documentElement;
          const body = document.body;
          const room = document.getElementById("room");
          const speakerBar = document.querySelector("[data-role=speaker-bar]");
          const roomCode = document.querySelector("[data-role=room-code]");
          const vw = window.innerWidth;

          const scrollWidth = Math.max(
            doc.scrollWidth,
            body.scrollWidth,
            room ? room.scrollWidth : 0
          );

          const hasHorizontalOverflow = scrollWidth > vw;

          const speakerBarRect = speakerBar ? speakerBar.getBoundingClientRect() : null;
          const roomCodeRect = roomCode ? roomCode.getBoundingClientRect() : null;

          return {
            vw,
            scrollWidth,
            hasHorizontalOverflow,
            speakerBarOverflow: speakerBarRect ? speakerBarRect.right > vw : false,
            speakerBarRight: speakerBarRect ? speakerBarRect.right : null,
            roomCodeRight: roomCodeRect ? roomCodeRect.right : null
          };
        })()`,
        returnByValue: true
      });

      const metrics = evalRes.result.value;
      const passed = !metrics.hasHorizontalOverflow && !metrics.speakerBarOverflow;

      const screenshotRes = await sendCDP(pageWs, "Page.captureScreenshot", { format: "png" });
      const screenshotFilename = `${pageName}_${vp.width}x${vp.height}.png`;
      const screenshotPath = path.join(SCREENSHOT_DIR, screenshotFilename);
      fs.writeFileSync(screenshotPath, Buffer.from(screenshotRes.data, "base64"));

      if (!passed) allPassed = false;

      results.push({
        page: pageName,
        viewport: `${vp.width}x${vp.height}`,
        passed,
        metrics,
        screenshot: screenshotFilename
      });

      console.log(
        `[${passed ? "PASS" : "FAIL"}] ${pageName.padEnd(16)} @ ${vp.width}x${vp.height}: ` +
        `scrollWidth=${metrics.scrollWidth}px / vw=${metrics.vw}px (speakerBarRight=${metrics.speakerBarRight}) -> ${screenshotFilename}`
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
    console.error("Some viewports failed horizontal overflow check!");
    process.exit(1);
  } else {
    console.log("All mobile viewports have zero horizontal overflow!");
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
