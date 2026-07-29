$ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$out = "$env:TEMP\architecture-review-$ts.html"
$html = @'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <title>Architecture review — 故事紀要工具</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <script type="module">
    import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs";
    mermaid.initialize({ startOnLoad: true, theme: "neutral", securityLevel: "loose" });
  </script>
  <style>
    .seam { stroke-dasharray: 4 4; }
    .leak { stroke: #dc2626; }
    .deep-box { background: linear-gradient(135deg, #0f172a, #1e293b); }
  </style>
</head>
<body class="bg-stone-50 text-slate-900 font-sans">
<main class="max-w-5xl mx-auto px-6 py-12 space-y-12">

  <header class="flex items-baseline justify-between border-b border-slate-200 pb-4">
    <div>
      <h1 class="text-3xl font-bold tracking-tight">&#25925;&#20107;&#32000;&#35201;&#24037;&#20855;</h1>
      <p class="text-slate-500 text-sm mt-1">single-file HTML - 1,905 lines - 75 global functions - 0 tests</p>
    </div>
    <div class="text-xs text-slate-400">2026-07-29</div>
  </header>

  <div class="flex gap-6 text-xs text-slate-500">
    <span><span class="inline-block w-4 h-4 align-middle border-2 border-slate-500 bg-white mr-1"></span> module</span>
    <span><span class="inline-block w-4 h-4 align-middle border border-dashed border-slate-400 mr-1"></span> seam</span>
    <span><span class="inline-block w-4 h-4 align-middle bg-red-500 mr-1"></span> leakage</span>
    <span><span class="inline-block w-4 h-4 align-middle bg-gradient-to-br from-slate-800 to-slate-700 mr-1"></span> deep module</span>
    <span><span class="inline-block w-4 h-4 align-middle border-2 border-slate-300 bg-slate-100 mr-1" style="width:28px;height:14px"></span> interface</span>
  </div>

  <section id="candidates" class="space-y-10">

    <!-- Card 1 -->
    <article class="bg-white rounded-xl shadow-sm border border-slate-200 overflow-hidden">
      <div class="p-6 space-y-4">
        <div class="flex items-start justify-between">
          <div>
            <h2 class="text-xl font-bold">1. Collapse global state behind a StoryStore module</h2>
            <div class="flex gap-2 mt-2">
              <span class="inline-block px-2 py-0.5 text-xs font-semibold rounded-full bg-emerald-100 text-emerald-800">Strong</span>
              <span class="inline-block px-2 py-0.5 text-xs font-semibold rounded-full bg-slate-100 text-slate-600">in-process</span>
            </div>
          </div>
        </div>
        <div class="text-sm font-mono text-slate-500">story_timeline_tool.html (entire file)</div>
        <div class="grid grid-cols-2 gap-6">
          <div>
            <div class="text-xs uppercase tracking-wider text-slate-400 mb-2">Before</div>
            <div class="rounded-lg border border-slate-200 bg-white p-4">
              <pre class="mermaid">
graph LR
  subgraph GlobalScope[global scope]
    A[app mutable object]:::shallow
    B[_batchQueue]:::shallow
    C[_batchCancelled]:::shallow
    D[_streamPanel]:::shallow
    E[_tmplEdit]:::shallow
  end
  F[renderAll] --> G{reads/writes}
  G --> A
  H[processBatch] --> A
  H --> B
  H --> C
  I[showStreamPanel] --> D
  J[openTemplateEditor] --> E
  K[80+ sites] --> A
  classDef shallow stroke:#dc2626,stroke-width:2px;
  class A,B,C,D,E shallow
              </pre>
            </div>
          </div>
          <div>
            <div class="text-xs uppercase tracking-wider text-slate-400 mb-2">After</div>
            <div class="rounded-lg border border-slate-200 bg-white p-4">
              <pre class="mermaid">
graph LR
  subgraph Store[StoryStore module]
    S[getStory / currentStory / updateBatch / save / on / emit]:::deep
  end
  subgraph Runner[BatchRunner module]
    R[enqueue / cancel / on progress]:::deep
  end
  F[renderAll] --> S
  G[processBatch] --> R
  R --> S
  R --> V[Events]
  V --> UI[UISubscriber]
  classDef deep stroke:#334155,stroke-width:3px,fill:#1e293b,color:#fff
  class S,R deep
              </pre>
            </div>
          </div>
        </div>
        <div class="grid grid-cols-3 gap-4 text-sm">
          <div><div class="font-semibold text-xs uppercase text-slate-400 mb-1">Problem</div><p>80+ sites read/write <code>app</code> directly; 4 more globals strewn across the file. No locality -- a bug in any function corrupts the entire app state.</p></div>
          <div><div class="font-semibold text-xs uppercase text-slate-400 mb-1">Solution</div><p>Extract a <code>StoryStore</code> module -- one interface, one place to enforce invariants. Side-effect globals move into their own modules that communicate via events.</p></div>
          <div><div class="font-semibold text-xs uppercase text-slate-400 mb-1">Wins</div><ul class="list-disc list-inside space-y-0.5 text-slate-600"><li><strong>locality</strong>: all mutations pass through one seam</li><li><strong>leverage</strong>: change schema - change one module</li><li><strong>depth</strong>: 6 globals collapse into 1 interface</li><li>Tests inject a mock store instead of 80-site mocking</li></ul></div>
        </div>
      </div>
    </article>

    <!-- Card 2 -->
    <article class="bg-white rounded-xl shadow-sm border border-slate-200 overflow-hidden">
      <div class="p-6 space-y-4">
        <div class="flex items-start justify-between">
          <div>
            <h2 class="text-xl font-bold">2. Separate batch queue from DOM rendering</h2>
            <div class="flex gap-2 mt-2">
              <span class="inline-block px-2 py-0.5 text-xs font-semibold rounded-full bg-emerald-100 text-emerald-800">Strong</span>
              <span class="inline-block px-2 py-0.5 text-xs font-semibold rounded-full bg-slate-100 text-slate-600">in-process</span>
            </div>
          </div>
        </div>
        <div class="text-sm font-mono text-slate-500">_runBatchWithQueue, processNextInQueue, stopBatchProcessing, showStreamPanel, batch-card buttons in renderDocsPanel</div>
        <div class="grid grid-cols-2 gap-6">
          <div>
            <div class="text-xs uppercase tracking-wider text-slate-400 mb-2">Before</div>
            <div class="rounded-lg border border-slate-200 bg-white p-4 h-64 flex items-center justify-center"><pre class="mermaid">
flowchart TD
  subgraph Q[Queue logic]
    A[_batchQueue] --> B[processNextInQueue]
    B --> C[_runBatchWithQueue]
  end
  C -.-> D[showStreamPanel]
  C -.-> E[updateStreamPanel]
  C -.-> F[finalizeStreamPanel]
  C -.-> G[renderAll]
  D -.-> H[DOM]
  classDef leak stroke:#dc2626,stroke-width:2px;
  class C,D,E,F,G leak
              </pre></div>
          </div>
          <div>
            <div class="text-xs uppercase tracking-wider text-slate-400 mb-2">After</div>
            <div class="rounded-lg border border-slate-200 bg-white p-4 h-64 flex items-center justify-center"><pre class="mermaid">
flowchart TD
  subgraph BR[BatchRunner module]
    B[enqueue / cancel / on batch-start / on batch-done / on batch-error]:::deep
  end
  B --> EV[Events]
  EV --> UI[UISubscriber]
  UI --> DOM[DOM]
  classDef deep stroke:#334155,stroke-width:3px,fill:#1e293b,color:#fff
  class B deep
              </pre></div>
          </div>
        </div>
        <div class="grid grid-cols-3 gap-4 text-sm">
          <div><div class="font-semibold text-xs uppercase text-slate-400 mb-1">Problem</div><p><code>_runBatchWithQueue</code> directly creates, updates, and destroys DOM elements -- the queue logic is inseparable from the streaming panel.</p></div>
          <div><div class="font-semibold text-xs uppercase text-slate-400 mb-1">Solution</div><p>BatchRunner exposes <code>enqueue / cancel / on</code>. It knows nothing about DOM. A separate subscriber creates the floating panel and calls <code>renderAll</code> when events fire.</p></div>
          <div><div class="font-semibold text-xs uppercase text-slate-400 mb-1">Wins</div><ul class="list-disc list-inside space-y-0.5 text-slate-600"><li><strong>seam</strong>: batch logic testable without DOM</li><li><strong>depth</strong>: queue + retry + cancel behind small interface</li><li><strong>locality</strong>: batch lifecycle bugs concentrate in one module</li><li>Non-streaming fallback lives inside the module, not in caller</li></ul></div>
        </div>
      </div>
    </article>

    <!-- Card 3 -->
    <article class="bg-white rounded-xl shadow-sm border border-slate-200 overflow-hidden">
      <div class="p-6 space-y-4">
        <div class="flex items-start justify-between">
          <div>
            <h2 class="text-xl font-bold">3. Encapsulate template editor state</h2>
            <div class="flex gap-2 mt-2">
              <span class="inline-block px-2 py-0.5 text-xs font-semibold rounded-full bg-emerald-100 text-emerald-800">Strong</span>
              <span class="inline-block px-2 py-0.5 text-xs font-semibold rounded-full bg-slate-100 text-slate-600">local-substitutable</span>
            </div>
          </div>
        </div>
        <div class="text-sm font-mono text-slate-500">openTemplateEditor, buildEditorHtml, teAddSheet, teRemoveSheet, teAddCol, teRemoveCol, teColKey, teColName, teColType, teColOpts, teRenameSheet, teSave, teDeleteTemplate, teApplyToStory, window._tmplEdit</div>
        <div class="grid grid-cols-2 gap-6">
          <div>
            <div class="text-xs uppercase tracking-wider text-slate-400 mb-2">Before</div>
            <div class="rounded-lg border border-slate-200 bg-white p-4 flex items-center justify-center" style="min-height:200px">
              <div style="display:flex;gap:40px;align-items:flex-end;height:160px">
                <div style="text-align:center"><div style="width:60px;height:150px;background:#fecaca;border:2px solid #dc2626;position:relative"><span style="position:absolute;bottom:-22px;left:0;right:0;font-size:10px;color:#dc2626;text-align:center">Interface<br/><span class="text-xs">14 global fns</span></span></div></div>
                <div style="text-align:center"><div style="width:60px;height:160px;background:#e2e8f0;border:2px solid #334155;position:relative"><span style="position:absolute;bottom:-22px;left:0;right:0;font-size:10px;color:#334155;text-align:center">Implementation<br/><span class="text-xs">~160 lines</span></span></div></div>
              </div>
              <div class="text-xs text-slate-400 mt-8 text-center">Interface ~ Implementation - <strong>shallow</strong></div>
            </div>
          </div>
          <div>
            <div class="text-xs uppercase tracking-wider text-slate-400 mb-2">After</div>
            <div class="rounded-lg border border-slate-200 bg-white p-4 flex items-center justify-center" style="min-height:200px">
              <div style="display:flex;gap:40px;align-items:flex-end;height:160px">
                <div style="text-align:center"><div style="width:60px;height:40px;background:#bbf7d0;border:2px solid #166534;position:relative"><span style="position:absolute;bottom:-22px;left:0;right:0;font-size:10px;color:#166534;text-align:center">Interface<br/><span class="text-xs">TemplateEditor.open(id)</span></span></div></div>
                <div style="text-align:center"><div style="width:60px;height:160px;background:#1e293b;border:2px solid #334155;position:relative"><span style="position:absolute;bottom:-22px;left:0;right:0;font-size:10px;color:#94a3b8;text-align:center">Implementation<br/><span class="text-xs">internal methods</span></span></div></div>
              </div>
              <div class="text-xs text-slate-400 mt-8 text-center">Interface &lt;&lt; Implementation - <strong>deep</strong></div>
            </div>
          </div>
        </div>
        <div class="grid grid-cols-3 gap-4 text-sm">
          <div><div class="font-semibold text-xs uppercase text-slate-400 mb-1">Problem</div><p>14 global functions + <code>window._tmplEdit</code> + 48 inline <code>onclick</code> handlers. The public surface is as complex as the implementation.</p></div>
          <div><div class="font-semibold text-xs uppercase text-slate-400 mb-1">Solution</div><p>One constructor <code>TemplateEditor(container, template, onSave)</code>. All <code>te*</code> functions become private methods. External interface is a single <code>.open(id)</code> call.</p></div>
          <div><div class="font-semibold text-xs uppercase text-slate-400 mb-1">Wins</div><ul class="list-disc list-inside space-y-0.5 text-slate-600"><li><strong>depth</strong>: 14 globals - 1 constructor</li><li><strong>locality</strong>: template logic lives inside one closure</li><li><strong>leverage</strong>: swap template rendering style in one place</li><li>Eliminates <code>window._tmplEdit</code> global</li></ul></div>
        </div>
      </div>
    </article>

    <!-- Card 4 -->
    <article class="bg-white rounded-xl shadow-sm border border-slate-200 overflow-hidden">
      <div class="p-6 space-y-4">
        <div class="flex items-start justify-between">
          <div>
            <h2 class="text-xl font-bold">4. Surface an AI transport adapter</h2>
            <div class="flex gap-2 mt-2">
              <span class="inline-block px-2 py-0.5 text-xs font-semibold rounded-full bg-amber-100 text-amber-800">Worth exploring</span>
              <span class="inline-block px-2 py-0.5 text-xs font-semibold rounded-full bg-slate-100 text-slate-600">ports and adapters</span>
            </div>
          </div>
        </div>
        <div class="text-sm font-mono text-slate-500">callOllama, callOllamaStream, deployOllama, settings.ollamaUrl/ollamaModel/aiProvider</div>
        <div class="grid grid-cols-2 gap-6">
          <div><div class="text-xs uppercase tracking-wider text-slate-400 mb-2">Before</div>
            <div class="rounded-lg border border-slate-200 bg-white p-4"><pre class="mermaid">
flowchart LR
  BP[_runBatchWithQueue] --> O[callOllama / callOllamaStream]
  Chat[sendChat] --> O
  O --> S[app.settings.ollamaUrl]
  O --> S2[app.settings.ollamaModel]
  classDef leak stroke:#dc2626,stroke-width:1px;
  class O leak
              </pre></div>
          </div>
          <div><div class="text-xs uppercase tracking-wider text-slate-400 mb-2">After</div>
            <div class="rounded-lg border border-slate-200 bg-white p-4"><pre class="mermaid">
flowchart LR
  subgraph Adapter[AiTransport module]
    IF[generate prompt onToken / deploy / getConfig setConfig]:::deep
  end
  BP[BatchRunner] --> IF
  Chat[sendChat] --> IF
  IF --> O[Ollama HTTP]
  IF -.-> A[Other provider]
  classDef deep stroke:#334155,stroke-width:3px,fill:#1e293b,color:#fff
  class IF deep
              </pre></div>
          </div>
        </div>
        <div class="grid grid-cols-3 gap-4 text-sm">
          <div><div class="font-semibold text-xs uppercase text-slate-400 mb-1">Problem</div><p>Two <code>callOllama*</code> functions float as globals. Every caller handles URL resolution, error logging, and streaming fallback independently. Adding a second provider touches every call site.</p></div>
          <div><div class="font-semibold text-xs uppercase text-slate-400 mb-1">Solution</div><p>One <code>AiTransport</code> adapter with <code>generate(prompt, opts)</code>. Streaming is an implementation detail. A second adapter just swaps the file.</p></div>
          <div><div class="font-semibold text-xs uppercase text-slate-400 mb-1">Wins</div><ul class="list-disc list-inside space-y-0.5 text-slate-600"><li><strong>seam</strong>: swap Ollama vs OpenAI at config time</li><li><strong>locality</strong>: all transport error handling in one module</li><li>Streaming/non-streaming fallback hidden from callers</li><li>Deploy logic belongs inside the adapter, not settings UI</li></ul></div>
        </div>
      </div>
    </article>

    <!-- Card 5 -->
    <article class="bg-white rounded-xl shadow-sm border border-slate-200 overflow-hidden">
      <div class="p-6 space-y-4">
        <div class="flex items-start justify-between">
          <div>
            <h2 class="text-xl font-bold">5. Isolate timeline SVG generation from event dragging</h2>
            <div class="flex gap-2 mt-2">
              <span class="inline-block px-2 py-0.5 text-xs font-semibold rounded-full bg-slate-100 text-slate-800">Speculative</span>
              <span class="inline-block px-2 py-0.5 text-xs font-semibold rounded-full bg-slate-100 text-slate-600">in-process</span>
            </div>
          </div>
        </div>
        <div class="text-sm font-mono text-slate-500">renderTimeline, startDrag, onDrag, endDrag, showEventDetail, timelineContainer</div>
        <div class="grid grid-cols-2 gap-6">
          <div><div class="text-xs uppercase tracking-wider text-slate-400 mb-2">Before</div>
            <div class="rounded-lg border border-slate-200 bg-white p-4 h-64 flex items-center justify-center">
              <div style="display:flex;flex-direction:column;width:220px;border:1px solid #cbd5e1;font-size:10px;text-align:center">
                <div style="height:32px;background:#fecaca;border-bottom:1px solid #cbd5e1;display:flex;align-items:center;justify-content:center;color:#991b1b">SVG layout</div>
                <div style="height:32px;background:#fecaca;border-bottom:1px solid #cbd5e1;display:flex;align-items:center;justify-content:center;color:#991b1b">Drag math</div>
                <div style="height:32px;background:#fecaca;border-bottom:1px solid #cbd5e1;display:flex;align-items:center;justify-content:center;color:#991b1b">Event click</div>
                <div style="height:32px;background:#fecaca;border-bottom:1px solid #cbd5e1;display:flex;align-items:center;justify-content:center;color:#991b1b">Modal open</div>
                <div style="height:32px;background:#fecaca;display:flex;align-items:center;justify-content:center;color:#991b1b">State update</div>
                <div style="padding:4px;color:#dc2626;font-weight:bold;font-size:9px">5 thin layers - no seam</div>
              </div>
            </div>
          </div>
          <div><div class="text-xs uppercase tracking-wider text-slate-400 mb-2">After</div>
            <div class="rounded-lg border border-slate-200 bg-white p-4 h-64 flex items-center justify-center">
              <div style="display:flex;flex-direction:column;width:220px;border:1px solid #334155;font-size:10px;text-align:center">
                <div style="height:100px;background:#1e293b;display:flex;align-items:center;justify-content:center;flex-direction:column;color:#e2e8f0;font-weight:bold"><div>TimelineModule</div><div style="font-weight:normal;font-size:9px;color:#94a3b8;margin-top:4px">render(svg) / onDrag(cb) / onClick(cb)</div></div>
                <div style="height:60px;background:#1e293b;border-top:1px dashed #475569;display:flex;align-items:center;justify-content:center;color:#94a3b8;font-size:9px">Internal: mousedown/mousemove/mouseup handlers, event lookup</div>
                <div style="padding:4px;color:#166534;font-weight:bold;font-size:9px">1 deep layer - 3 methods exposed</div>
              </div>
            </div>
          </div>
        </div>
        <div class="grid grid-cols-3 gap-4 text-sm">
          <div><div class="font-semibold text-xs uppercase text-slate-400 mb-1">Problem</div><p>SVG generation, drag coordinates, event click handling, and modal management are intertwined in 5 functions sharing globals. Deletion test: removing <code>renderTimeline</code> would concentrate nothing.</p></div>
          <div><div class="font-semibold text-xs uppercase text-slate-400 mb-1">Solution</div><p>Wrap in a <code>TimelineModule(container)</code> that owns the SVG element and exposes <code>.render(data)</code>, <code>.onDrag(cb)</code>, <code>.onClick(cb)</code>. Drag state is local.</p></div>
          <div><div class="font-semibold text-xs uppercase text-slate-400 mb-1">Wins</div><ul class="list-disc list-inside space-y-0.5 text-slate-600"><li><strong>locality</strong>: drag math and SVG layout live together</li><li><strong>testability</strong>: inject data, assert SVG output</li><li>No more global _dragStartX / _dragStartY</li><li>Unit-testable drag coordinate math</li></ul></div>
        </div>
      </div>
    </article>

  </section>

  <section id="top-recommendation" class="bg-white rounded-xl shadow-sm border-2 border-emerald-400 overflow-hidden">
    <div class="p-6 space-y-3">
      <div class="text-xs uppercase tracking-wider text-emerald-600 font-semibold">Top recommendation</div>
      <h2 class="text-xl font-bold">Candidate 1: StoryStore module</h2>
      <p class="text-sm text-slate-600">The <code>app</code> global is referenced 80+ times across 75 functions. Extracting a StoryStore is the highest-leverage move: every other candidate (BatchRunner, TemplateEditor, AiTransport) depends on state. Deepening the state module first creates the seam that makes the other four candidates coherent.</p>
      <p class="text-sm text-slate-600 mt-2">The <strong>deletion test</strong> confirms it: if you removed the <code>app</code> object, the entire tool collapses. It is the most load-bearing module -- but its interface is an untyped mutable object. Formalising it behind a <code>StoryStore</code> interface turns load-bearing into leverage: one place to change, one place to test, one place to trust.</p>
    </div>
  </section>

</main>
</body>
</html>
'@
Set-Content -Path $out -Value $html -Encoding UTF8
Write-Host "Report written to: $out"
Start-Process $out
