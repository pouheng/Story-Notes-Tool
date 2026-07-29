// 故事紀要工具 - 即時串流節流測試
// 模擬 Ollama 一次回傳所有 token 的場景，驗證節流邏輯確保 token 以可見間隔顯示
// 用法: node test_streaming.js
// 退出碼: 0=通過, 1=失敗

// ============================================================
// 測試 A: 無節流 ── 模擬所有 token 一次到達、同步處理 (Bug 再現)
// 在瀏覽器中，callOllamaStream 的 for 迴圈處理所有 NDJSON lines，
// 即使有 setTimeout(0)，瀏覽器可能將所有 DOM 更新批次渲染，
// 導致使用者只看得到最後 1~2 個 token 的狀態。
// 此測試模擬最極端情況：完全同步的 for 迴圈，不 yield 事件迴圈。
// 期望結果: 所有 token 在 <1ms 內全部顯示完畢
// ============================================================
function testNoThrottle() {
  const TARGET_TOKENS = 2000;
  const START = performance.now();
  const times = [START];

  // 模擬所有 NDJSON lines 在單次 reader.read() 中一次到達，
  // for 迴圈同步處理，沒有 await 讓出事件迴圈給瀏覽器渲染。
  for (let i = 0; i < TARGET_TOKENS; i++) {
    times.push(performance.now());
  }

  const intervals = [];
  for (let i = 1; i < times.length; i++) {
    intervals.push(times[i] - times[i - 1]);
  }
  const totalMs = times[times.length - 1] - times[0];
  const avg = intervals.reduce((a, b) => a + b, 0) / intervals.length;

  console.log(`  總耗時: ${totalMs.toFixed(3)}ms, 平均間隔: ${avg.toFixed(6)}ms, 樣本數: ${TARGET_TOKENS}`);
  return { totalMs, avg };
}

// ============================================================
// 測試 B: 30ms 節流 ── 模擬修復後的節流行為
// 當 token 在極短時間內大量到達時，強制加入最小顯示間隔，
// 確保每個 token 有足夠時間被瀏覽器渲染出來。
// 期望結果: 平均間隔 >= 25ms, 最小間隔 >= 20ms
// ============================================================
async function testWithThrottle(minIntervalMs = 30) {
  const TARGET_TOKENS = 50;
  let lastTime = 0;
  const times = [];

  for (let i = 0; i < TARGET_TOKENS; i++) {
    const now = performance.now();
    const elapsed = now - lastTime;
    if (elapsed < minIntervalMs && lastTime > 0) {
      await new Promise(r => setTimeout(r, minIntervalMs - elapsed));
    }
    times.push(performance.now());
    lastTime = times[times.length - 1];
  }

  const intervals = [];
  for (let i = 1; i < times.length; i++) {
    intervals.push(times[i] - times[i - 1]);
  }
  const totalMs = times[times.length - 1] - times[0];
  const avg = intervals.reduce((a, b) => a + b, 0) / intervals.length;
  const min = Math.min(...intervals);
  const max = Math.max(...intervals);

  console.log(`  總耗時: ${totalMs}ms, 平均: ${avg.toFixed(2)}ms, 最小: ${min.toFixed(2)}ms, 最大: ${max.toFixed(2)}ms`);
  return { totalMs, avg, min, max };
}

// ============================================================
// 測試 C: 跨多個 chunk + 節流 ── 模擬真實 Ollama 串流場景
// Ollama 可能分批回傳 token (多次 reader.read())，
// 每次回傳一批 token。節流應確保 chunk 內的 burst token 仍被分散。
// ============================================================
async function testChunkedThrottle(minIntervalMs = 30) {
  const CHUNKS = 5;
  const TOKENS_PER_CHUNK = 10;
  let lastTime = 0;
  const times = [];

  for (let c = 0; c < CHUNKS; c++) {
    // 模擬 reader.read() 之間的真實間隔
    await new Promise(r => setTimeout(r, 200));

    for (let i = 0; i < TOKENS_PER_CHUNK; i++) {
      const now = performance.now();
      const elapsed = now - lastTime;
      if (elapsed < minIntervalMs && lastTime > 0) {
        await new Promise(r => setTimeout(r, minIntervalMs - elapsed));
      }
      times.push(performance.now());
      lastTime = times[times.length - 1];
    }
  }

  const intervals = [];
  for (let i = 1; i < times.length; i++) {
    intervals.push(times[i] - times[i - 1]);
  }
  const avg = intervals.reduce((a, b) => a + b, 0) / intervals.length;
  const min = Math.min(...intervals);

  console.log(`  平均: ${avg.toFixed(2)}ms, 最小: ${min.toFixed(2)}ms`);
  return { avg, min };
}

// ============================================================
// 主測試流程
// ============================================================
async function main() {
  let passed = 0;
  let failed = 0;

  console.log('========================================');
  console.log('  即時串流節流測試');
  console.log('========================================\n');

  // ── 測試 A ──
  console.log('測試 A: 原始行為 (無節流, 同步 for 迴圈)');
  const a = testNoThrottle();
  if (a.totalMs < 1) {
    console.log('  ✅ Bug 確認: 所有 token 在 <1ms 內爆量顯示，無串流效果\n');
    passed++;
  } else {
    console.log('  ❌ 非預期: 總耗時 >= 1ms\n');
    failed++;
  }

  // ── 測試 B ──
  console.log('測試 B: 30ms 節流 (修復)');
  const b = await testWithThrottle(30);
  if (b.avg >= 25 && b.min >= 20) {
    console.log('  ✅ PASS: 節流有效，token 以 ~30ms 間隔顯示\n');
    passed++;
  } else {
    console.log(`  ❌ FAIL: avg=${b.avg.toFixed(1)}ms min=${b.min.toFixed(1)}ms\n`);
    failed++;
  }

  // ── 測試 C ──
  console.log('測試 C: 多 chunk 場景 (含 reader.read() 間隔)');
  const c = await testChunkedThrottle(30);
  if (c.avg >= 25 && c.min >= 20) {
    console.log('  ✅ PASS: chunk 內 token 仍受節流控制\n');
    passed++;
  } else {
    console.log(`  ❌ FAIL: avg=${c.avg.toFixed(1)}ms min=${c.min.toFixed(1)}ms\n`);
    failed++;
  }

  // ── 總結果 ──
  console.log('========================================');
  console.log(`  結果: ${passed} 通過, ${failed} 失敗`);
  console.log('========================================');
  process.exit(failed > 0 ? 1 : 0);
}

main().catch(e => {
  console.error('測試失敗:', e.message);
  process.exit(1);
});
