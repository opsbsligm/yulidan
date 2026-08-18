import Foundation

/// 内嵌 Web 页面（单文件 HTML/CSS/JS，无外部资源，与桌面端同风格深色主题）
enum WebUIPage {
    static let html = """
    <!DOCTYPE html>
    <html lang="zh">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Harness Web</title>
    <style>
      :root {
        --bg: #111315; --bg-side: #0c0e10; --bg-panel: #1a1d21; --bg-input: #21252b;
        --border: #2a2f36; --text: #e6e9ec; --text-dim: #8b939c; --accent: #4f8cff;
      }
      * { box-sizing: border-box; margin: 0; padding: 0; }
      html, body { height: 100%; }
      body { display: flex; background: var(--bg); color: var(--text); font: 14px/1.55 -apple-system, "SF Pro Text", "PingFang SC", sans-serif; }
      /* ── 侧栏 ── */
      #sidebar { width: 240px; min-width: 240px; background: var(--bg-side); border-right: 1px solid var(--border); display: flex; flex-direction: column; }
      #brand { padding: 14px 16px 10px; font-size: 15px; font-weight: 600; letter-spacing: .3px; }
      #brand span { color: var(--accent); }
      #new-chat { margin: 4px 12px 10px; padding: 8px 10px; background: var(--bg-panel); color: var(--text);
        border: 1px solid var(--border); border-radius: 8px; cursor: pointer; font-size: 13px; text-align: left; }
      #new-chat:hover { border-color: var(--accent); }
      #sessions { flex: 1; overflow-y: auto; padding: 0 8px 12px; }
      .session { padding: 8px 10px; border-radius: 8px; cursor: pointer; color: var(--text-dim); font-size: 13px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
      .session:hover { background: var(--bg-panel); color: var(--text); }
      .session.active { background: var(--bg-panel); color: var(--text); }
      /* ── 主区 ── */
      #main { flex: 1; display: flex; flex-direction: column; min-width: 0; }
      #messages { flex: 1; overflow-y: auto; padding: 28px 0 12px; }
      #thread { max-width: 760px; margin: 0 auto; padding: 0 24px; }
      .msg { margin-bottom: 18px; }
      .msg .who { font-size: 12px; color: var(--text-dim); margin-bottom: 4px; }
      .msg .bubble { white-space: pre-wrap; word-break: break-word; }
      .msg.user .bubble { background: var(--bg-panel); border: 1px solid var(--border); border-radius: 10px; padding: 10px 14px; }
      .msg.assistant .bubble { padding: 2px 2px; }
      .msg.error .bubble { color: #ff7a7a; font-size: 13px; }
      #thinking { max-width: 760px; margin: 0 auto; padding: 0 24px; color: var(--text-dim); font-size: 13px; display: none; }
      #thinking.show { display: block; }
      #thinking::before { content: "●"; margin-right: 6px; animation: blink 1s infinite; }
      @keyframes blink { 50% { opacity: .25; } }
      /* ── 输入框（贴底） ── */
      #composer { padding: 10px 24px 18px; }
      #composer-box { max-width: 760px; margin: 0 auto; background: var(--bg-input); border: 1px solid var(--border);
        border-radius: 12px; display: flex; align-items: flex-end; gap: 8px; padding: 10px 10px 10px 14px; }
      #composer-box:focus-within { border-color: var(--accent); }
      #input { flex: 1; background: transparent; border: none; outline: none; color: var(--text); font: inherit; resize: none; max-height: 180px; padding: 2px 0; }
      #send { width: 30px; height: 30px; border: none; border-radius: 8px; background: var(--accent); color: #fff; font-size: 15px; cursor: pointer; flex-shrink: 0; }
      #send:disabled { background: var(--border); cursor: default; }
      #hint { max-width: 760px; margin: 6px auto 0; text-align: center; color: var(--text-dim); font-size: 11px; }
    </style>
    </head>
    <body>
      <div id="sidebar">
        <div id="brand">Harness <span>Web</span></div>
        <button id="new-chat" onclick="newChat()">＋ 新会话</button>
        <div id="sessions"></div>
      </div>
      <div id="main">
        <div id="messages"><div id="thread"></div></div>
        <div id="thinking">思考中</div>
        <div id="composer">
          <div id="composer-box">
            <textarea id="input" rows="1" placeholder="发送消息给 Harness Agent（Enter 发送，Shift+Enter 换行）"></textarea>
            <button id="send" onclick="send()">↑</button>
          </div>
          <div id="hint">本地服务 · 会话仅保存在进程内，重启后清空</div>
        </div>
      </div>
    <script>
      let currentSession = null;
      const thread = document.getElementById("thread");
      const input = document.getElementById("input");
      const sendBtn = document.getElementById("send");
      const thinking = document.getElementById("thinking");

      input.addEventListener("keydown", (e) => {
        if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); send(); }
      });
      input.addEventListener("input", () => {
        input.style.height = "auto";
        input.style.height = Math.min(input.scrollHeight, 180) + "px";
      });

      function esc(s) { const d = document.createElement("div"); d.textContent = s; return d.innerHTML; }

      function addMsg(kind, text) {
        const div = document.createElement("div");
        div.className = "msg " + kind;
        const who = kind === "user" ? "你" : (kind === "error" ? "错误" : "Harness");
        div.innerHTML = '<div class="who">' + who + '</div><div class="bubble">' + esc(text) + "</div>";
        thread.appendChild(div);
        document.getElementById("messages").scrollTop = 1e9;
      }

      async function api(path, opts) {
        const r = await fetch(path, opts);
        let body = null;
        try { body = await r.json(); } catch (_) {}
        if (!r.ok) throw new Error((body && body.error) || ("HTTP " + r.status));
        return body;
      }

      function renderSessions(list) {
        const box = document.getElementById("sessions");
        box.innerHTML = "";
        for (const s of list) {
          const el = document.createElement("div");
          el.className = "session" + (s.id === currentSession ? " active" : "");
          el.textContent = s.title;
          el.title = s.title;
          el.onclick = () => { currentSession = s.id; renderSessions(list); };
          box.appendChild(el);
        }
      }

      async function loadSessions() {
        try { renderSessions(await api("/api/sessions")); } catch (_) {}
      }

      function newChat() {
        currentSession = null;
        thread.innerHTML = "";
        loadSessions();
        input.focus();
      }

      async function send() {
        const text = input.value.trim();
        if (!text || sendBtn.disabled) return;
        input.value = ""; input.style.height = "auto";
        addMsg("user", text);
        thinking.classList.add("show");
        sendBtn.disabled = true;
        try {
          const res = await api("/api/chat", {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify({ sessionId: currentSession, message: text })
          });
          currentSession = res.sessionId;
          if (res.reply) addMsg("assistant", res.reply);
          if (res.error) addMsg("error", res.error);
        } catch (e) {
          addMsg("error", String(e && e.message ? e.message : e));
        } finally {
          thinking.classList.remove("show");
          sendBtn.disabled = false;
          input.focus();
          loadSessions();
        }
      }

      newChat();
    </script>
    </body>
    </html>
    """
}
