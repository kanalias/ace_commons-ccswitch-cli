---
name: system-ai-gateway
description: Consumer contract cho @acegalaxy/lib-ai-gateway — env, dispatchCall (never throws), audit log, cấm import SDK/CLI trực tiếp, model override, tier fallback, Claude CLI limit. LAZY, load khi chạm code gọi LLM.
status: live
updated: 2026-10-13
paths:
  - "src/**"
  - "**/ai-gateway*"
metadata:
  type: reference
---

# AI Gateway — Mọi runtime LLM call BẮT BUỘC qua gateway

Mọi code gọi LLM runtime (features, runners, schedulers, handlers) PHẢI đi qua `@acegalaxy/lib-ai-gateway` (git-dependency, repo private `acegalaxy-co/lib-ai-gateway`). KHÔNG có bản in-repo — gateway sống trong `node_modules/@acegalaxy/lib-ai-gateway`.

## Scope

**Áp dụng:** runtime LLM call (extract / summarize / classify / browse / generate) tới Anthropic / OpenAI / DeepSeek / Gemini / Claude CLI — cả API key lẫn subscription/CLI.

**Không áp dụng:** delegate-LLM dev-time workflow (`scripts/delegate/run-*.sh`, xem [[delegate-llm]]); embedding/rerank API riêng nếu có.

## Consume qua git-dependency

Pin tag `#vX.Y.Z` trong `package.json`; mọi callsite `require("@acegalaxy/lib-ai-gateway")`. Subpath exports: `@acegalaxy/lib-ai-gateway/lib/claude-limit`, `@acegalaxy/lib-ai-gateway/audit/logger`. Git-dependency chính thức ≠ deep-import cross-scope (cái sau vẫn cấm).

**Update gateway = 1 nơi:** sửa repo `acegalaxy-co/lib-ai-gateway` → build + commit dist → tag mới → bump `#vX.Y.Z` → `npm install` (skill `ace-library`).

**Env contract:**
- `AI_GATEWAY_CONFIG_ROOT` — dir chứa `config/llm-config.json` + `data/llm-models-cache.json`. Unset → gateway walk-up từ node_modules tới repo root. Set absolute cho container.
- `AI_GATEWAY_AUDIT_LOG_PATH` — **BẮT BUỘC trỏ NGOÀI node_modules** (vd `data/ai-gateway-audit.log`) vì `npm install` wipe node_modules → mất audit log. Khai báo trong `.env` + `.env.example`.

## 5 layers (default-deny, theo thứ tự)

```text
dispatchCall({ skill, tier, prompt, schema? })
  ▶ L1 Adapter           provider tồn tại + usable?
  ▶ L2 Authz             skill+tier → allowed provider/model?  (policies.json)
  ▶ L3 Budget            còn quota token trong 24h cho skill?  (reserve→commit)
  ▶ L4 Circuit breaker   provider có đang fail liên tiếp?
  ▶ L5 Audit             append-only JSONL: outcome + tokens + latency
```

Deny reasons: `L1_provider_unavailable | L2_authz | L3_budget_exhausted | L4_circuit_open | L5_audit_fatal`.

## Entry point — `dispatchCall()`

```js
const { dispatchCall } = require("@acegalaxy/lib-ai-gateway");

const r = await dispatchCall({
  skill: "<feature>.<action>",
  tier: "balanced",
  prompt: "...",
  schema: null,
});
// r.outcome === "allow" → r.text + r.tokensOut + r.latencyMs
// r.outcome === "deny"  → r.denyReason + r.latencyMs
```

`dispatchCall` **NEVER throws** — luôn trả response object; caller xử lý `outcome`, không bọc try/catch thay cho check `deny`.

Adapter (chỉ trong lib) implement `IAIAdapter`:

```ts
class IAIAdapter {
  get provider(): string;   // "anthropic-api" | "anthropic-cli" | "openai-api" | "deepseek-api" | "gemini-cli"
  async complete({ prompt, model, maxOutputTokens, schema }): Promise<{ text, schemaJson, tokensIn, tokensOut }>;
  estimateTokens(prompt: string): number;
}
```

## Audit log — append-only

- Mỗi call (allow hay deny) log 1 dòng `OutcomeRecord`: skill, provider, model, tokensIn/Out, latencyMs.
- Path mặc định `<package>/audit/audit.log` trong node_modules — **mất khi `npm install`** → luôn override bằng `AI_GATEWAY_AUDIT_LOG_PATH` (ngoài node_modules).
- Retention: không xoá. Archive OK.

## Cấm tuyệt đối

- ❌ `require("@anthropic-ai/sdk")` / `require("openai")` / `require("@google/generative-ai")` trong code repo. SDK chỉ được import trong package lib (node_modules).
- ❌ Spawn `claude` / `gemini` / `codex` CLI subprocess runtime trong code repo. CLI spawn chỉ trong adapter của lib.
- ❌ Bypass authz / budget / audit — kể cả "test" / "throwaway script" trong runtime path.
- ❌ Pass API key vào prompt content. Key chỉ đọc qua `process.env.*_API_KEY` trong adapter của lib.
- ❌ Xoá audit log (archive OK, xoá KHÔNG).

## Audit trước commit (bắt buộc)

```bash
# SDK imports trong code (phải RỖNG — SDK chỉ ở package lib)
grep -rn "@anthropic-ai/sdk\|require.*['\"]openai['\"]\|@google/generative-ai" \
  src/ \
  --include="*.ts" --include="*.js" \
  --exclude-dir=node_modules

# Spawn CLI subprocess runtime trong code (phải RỖNG ngoài delegate wrapper)
grep -rn "spawn.*['\"]claude['\"]\|spawn.*['\"]gemini['\"]" \
  src/ \
  --include="*.ts" --include="*.js" \
  --exclude-dir=node_modules \
  --exclude-dir=scripts/delegate
```

Chỉnh `src/` theo thư mục source thực tế của project. Match (ngoài path exempt) → fix hoặc dừng hỏi user.

## 9router — gateway LLM dùng chung

- Service gọi LLM qua 9router bằng `AI_9ROUTER_BASE_URL` + `AI_9ROUTER_TOKEN` (tên lib đọc). Key theo project, KHÔNG dùng key provider trực tiếp trong service. `AI_9ROUTER_API_KEY` = tên cũ → chỉ đọc fallback ở chỗ đã có, không thêm chỗ dùng mới.
- Thêm service dùng LLM → khai 2 biến trên vào `.env.example` (không value).

## Runtime env model override

Ngoài `modelOverride` param, operator chọn model tại runtime **KHÔNG cần đổi code**.

**Priority (cao → thấp):**

1. `req.modelOverride` param — caller code
2. `AI_GATEWAY_MODEL_<SKILL_UPPER>` — theo skill
3. `AI_GATEWAY_MODEL_DEFAULT` — mọi skill Anthropic
4. Policy tier binding — `policies.json`

**Naming:** skill `<feature>.<action>` → `AI_GATEWAY_MODEL_<FEATURE>_<ACTION>` (uppercase, `.` và `-` → `_`).

**Constraint:** env override CHỈ áp cho provider Anthropic (`anthropic-api` / `anthropic-cli`). Skill bound `openai-compat` (DeepSeek/Gemini) không bị đụng — cross-provider swap cần `baseUrl` + `apiKeyEnv`, không truyền được qua env đơn giản.

Model resolved cuối cùng (sau override) ghi vào audit log field `model`.

## Fallback — 2 cơ chế KHÁC NHAU, đừng nhầm

**1. Caller-side tier fallback (trong 1 provider).** Caller khai `fallbackTier` để retry tier cao hơn khi call đầu fail parse JSON:

```ts
buildGatewayClaudeRunner({ skill: "<feature>.<action>", tier: "balanced", fallbackTier: "deep" });
```

1. Gọi primary tier. 2. `schemaJson != null` → ok. 3. Manual parse được (strip fence, block `[...]`/`{...}` đầu tiên) → ok, không fallback. 4. Vẫn không parse được → retry `fallbackTier`, cùng skill. 5. Fail lần 2 → error nêu cả 2 tier.

Trigger CHỈ cho schema parse fail, KHÔNG cho gateway deny (L2/L3/L4) — deny là terminal, retry cùng model = cùng deny. `fallbackTier: null` = tắt.

**2. Provider-chain fallback (giữa các provider, nếu project dùng runner chain).** Chỉ trigger cho lỗi transient (quota, 429, session lock, auth, ENOENT, timeout); schema-parse fail KHÔNG nhảy provider (cùng input fail y hệt). Khác cơ chế 1: tier fallback = cùng provider, parse fail; provider chain = đổi provider, transient error.

## Claude CLI realtime limit handling (Session 5h / Weekly 7d)

Mọi scheduler dùng Claude CLI realtime (adapter `anthropic-cli` qua `dispatchCall` hoặc direct spawn) PHẢI detect limit qua barrel `@acegalaxy/lib-ai-gateway/lib/claude-limit`:

- **detect.ts** — parse stderr → `{kind, resetAt}` cho `session_5h` | `weekly_7d` | `rate_limit`.
- **state.ts** — cooldown in-memory per-skill: `markLimitHit` / `shouldSkip` / `clearLimit`. Mất khi restart (chấp nhận — tick sau re-hit + alert lại 1 lần).
- **error.ts** — `ClaudeCliLimitError` (flag `isClaudeCliLimit`, `kind`, `resetAt`).
- **alert.ts** — `alertClaudeCliLimit(schedulerName, skill, kind, resetAt, sendAlert)`; caller inject `sendAlert(message, channelId)` (lib standalone KHÔNG resolve kênh alert của consumer). Luôn dùng dạng 5 tham số này.

CLI không có subcommand `usage`/`quota` → không precheck proactive được; chỉ detect reactive sau khi spawn fail.

**Bắt buộc cho callsite mới chạy CLI realtime:**

1. Trước spawn: `if (shouldSkip(skill).skip) throw ClaudeCliLimitError`.
2. Spawn fail: parse stderr → `markLimitHit` + throw `ClaudeCliLimitError` nếu là limit.
3. Spawn success: `clearLimit(skill)`.
4. Scheduler boundary: catch `err.isClaudeCliLimit === true` → `alertClaudeCliLimit(schedulerName, skill, err.kind, err.resetAt, sendAlert)`.

**Cấm:**

- ❌ Spawn `claude -p` mà không check `shouldSkip()` → đốt token khi đang cooldown.
- ❌ Gửi limit alert vào kênh public → chỉ kênh alert của project.
- ❌ `Error("claude exit...")` generic cho limit → mất phân biệt + cron tick alert spam.

Audit: limit deny vẫn dùng `denyReason: "L4_circuit_open"` (gần nghĩa nhất, không thêm reason mới); caller phân biệt bằng `err.isClaudeCliLimit`.
