import Foundation

// Seeded from OMP's shipped settings schema by scripts/seed_setting_metadata.ts.
// Hand-maintain from here; SettingMetadataDriftTests flag drift against the
// installed omp binary.

struct SettingOption: Equatable {
    let value: String
    var label: String? = nil
    var detail: String? = nil

    init(_ value: String, label: String? = nil, detail: String? = nil) {
        self.value = value
        self.label = label
        self.detail = detail
    }
}

enum SettingMetadata {
    static let enumOptions: [String: [SettingOption]] = [
        "power.sleepPrevention": [
            SettingOption("off", label: "Off", detail: "Do not prevent any sleep"),
            SettingOption("idle", label: "Prevent Idle Sleep", detail: "Keep the system awake while a session is open (macOS `caffeinate -i`)"),
            SettingOption("display", label: "Prevent Display Sleep", detail: "Also keep the display from idle-sleeping (macOS `caffeinate -i -d`)"),
            SettingOption("system", label: "Prevent System Sleep", detail: "Also block all system sleep on AC and declare the user active (macOS `caffeinate -i -d -s -u`)"),
        ],
        "advisor.syncBacklog": [
            SettingOption("off"),
            SettingOption("1"),
            SettingOption("3"),
            SettingOption("5"),
        ],
        "providers.openai-codex.codeMode": [
            SettingOption("off"),
            SettingOption("on"),
            SettingOption("auto"),
        ],
        "modelRoleStorage": [
            SettingOption("global", label: "Global", detail: "Save role models in the active profile config (current behavior)"),
            SettingOption("project", label: "Per-project", detail: "Save project role models in .omp/config.yml; missing project roles use global defaults"),
        ],
        "symbolPreset": [
            SettingOption("unicode", label: "Unicode", detail: "Standard symbols (default)"),
            SettingOption("nerd", label: "Nerd Font", detail: "Requires Nerd Font"),
            SettingOption("ascii", label: "ASCII", detail: "Maximum compatibility"),
        ],
        "statusLine.preset": [
            SettingOption("default", label: "Default", detail: "Model, path, git, context, tokens, cost"),
            SettingOption("minimal", label: "Minimal", detail: "Path and git only"),
            SettingOption("compact", label: "Compact", detail: "Model, git, cost, context"),
            SettingOption("full", label: "Full", detail: "All segments including time"),
            SettingOption("nerd", label: "Nerd", detail: "Maximum info with Nerd Font icons"),
            SettingOption("ascii", label: "ASCII", detail: "No special characters"),
            SettingOption("custom", label: "Custom", detail: "User-defined segments"),
        ],
        "statusLine.separator": [
            SettingOption("powerline", label: "Powerline", detail: "Solid arrows (Nerd Font)"),
            SettingOption("powerline-thin", label: "Thin chevron", detail: "Thin arrows (Nerd Font)"),
            SettingOption("slash", label: "Slash", detail: "Forward slashes"),
            SettingOption("pipe", label: "Pipe", detail: "Vertical pipes"),
            SettingOption("block", label: "Block", detail: "Solid blocks"),
            SettingOption("none", label: "None", detail: "Space only"),
            SettingOption("ascii", label: "ASCII", detail: "Greater-than signs"),
        ],
        "statusLine.contextLine": [
            SettingOption("off", label: "Off", detail: "Solid accent line, no context feedback"),
            SettingOption("percentage", label: "Percentage", detail: "Used portion in accent color, remainder dimmed"),
            SettingOption("annotated", label: "Annotated", detail: "Percentage plus ticks at the speculative and auto-compaction boundaries"),
            SettingOption("embedded", label: "Embedded", detail: "Annotated line with the context percentage and window embedded in the gauge"),
        ],
        "tui.resizeScrollback": [
            SettingOption("append", label: "Append", detail: "Replay the transcript at the new width below retained history"),
            SettingOption("rebuild", label: "Rebuild", detail: "Erase all terminal scrollback, then replay one current-width transcript"),
            SettingOption("preserve", label: "Preserve", detail: "Repaint only the viewport and keep history wrapped at its old width"),
        ],
        "tui.hyperlinks": [
            SettingOption("off"),
            SettingOption("auto"),
            SettingOption("always"),
        ],
        "display.shimmer": [
            SettingOption("classic", label: "Classic", detail: "Soft cosine wave sweeping across the text"),
            SettingOption("kitt", label: "KITT Scanner", detail: "Knight Rider 1982 red light bouncing left-right"),
            SettingOption("disabled", label: "Disabled", detail: "No animation; static muted text"),
        ],
        "defaultThinkingLevel": [
            SettingOption("auto", detail: "Auto-detect per prompt"),
            SettingOption("minimal", label: "min", detail: "Very brief reasoning (~1k tokens)"),
            SettingOption("low", detail: "Light reasoning (~2k tokens)"),
            SettingOption("medium", detail: "Moderate reasoning (~8k tokens)"),
            SettingOption("high", detail: "Deep reasoning (~16k tokens)"),
            SettingOption("xhigh", detail: "Extended reasoning (~32k tokens)"),
            SettingOption("max", detail: "Maximum reasoning the model supports"),
        ],
        "inlineToolDescriptors": [
            SettingOption("auto", label: "Auto", detail: "Inline descriptors for Gemini models; keep them in tool schemas otherwise"),
            SettingOption("on", label: "On", detail: "Always inline descriptors in the system prompt"),
            SettingOption("off", label: "Off", detail: "Keep descriptors in provider tool schemas only"),
        ],
        "personality": [
            SettingOption("default", label: "Default", detail: "Terse, evidence-first engineer; dense, action-oriented replies"),
            SettingOption("friendly", label: "Friendly", detail: "Warm, encouraging collaborator focused on momentum and morale"),
            SettingOption("pragmatic", label: "Pragmatic", detail: "Direct, efficient engineer focused on clarity and rigor"),
            SettingOption("none", label: "None", detail: "Omit the personality block entirely"),
        ],
        "textVerbosity": [
            SettingOption("low", label: "Low", detail: "Prefer concise responses"),
            SettingOption("medium", label: "Medium", detail: "Balance brevity and detail (default)"),
            SettingOption("high", label: "High", detail: "Prefer detailed responses"),
        ],
        "tier.openai": [
            SettingOption("none", label: "None", detail: "Omit service_tier (standard processing)"),
            SettingOption("auto", label: "Auto", detail: "Provider default tier selection"),
            SettingOption("default", label: "Default", detail: "Standard priority processing"),
            SettingOption("flex", label: "Flex", detail: "Lower cost, higher latency when available"),
            SettingOption("scale", label: "Scale", detail: "Scale Tier credits when available"),
            SettingOption("priority", label: "Priority", detail: "Faster, higher cost (premium request)"),
        ],
        "tier.anthropic": [
            SettingOption("none", label: "None", detail: "Standard processing"),
            SettingOption("priority", label: "Priority", detail: "Fast mode (`speed: \"fast\"`) on supported direct Claude models; ignored on Bedrock/Vertex"),
        ],
        "tier.google": [
            SettingOption("none", label: "None", detail: "Standard processing"),
            SettingOption("flex", label: "Flex", detail: "Lower cost, higher latency (Gemini API + Vertex)"),
            SettingOption("priority", label: "Priority", detail: "Faster, higher reliability (Gemini API + Vertex)"),
        ],
        "tier.subagent": [
            SettingOption("inherit", label: "Inherit", detail: "Match the main agent's live per-family tiers"),
            SettingOption("none", label: "None", detail: "Standard processing"),
            SettingOption("auto", label: "Auto", detail: "Provider default tier selection (OpenAI family)"),
            SettingOption("default", label: "Default", detail: "Standard priority processing (OpenAI family)"),
            SettingOption("flex", label: "Flex", detail: "Flexible capacity tier (OpenAI/Google families)"),
            SettingOption("scale", label: "Scale", detail: "Scale Tier credits (OpenAI family)"),
            SettingOption("priority", label: "Priority", detail: "Priority on every supported family of the spawned model"),
        ],
        "tier.advisor": [
            SettingOption("inherit", label: "Inherit", detail: "Match the main agent's live per-family tiers"),
            SettingOption("none", label: "None", detail: "Standard processing"),
            SettingOption("auto", label: "Auto", detail: "Provider default tier selection (OpenAI family)"),
            SettingOption("default", label: "Default", detail: "Standard priority processing (OpenAI family)"),
            SettingOption("flex", label: "Flex", detail: "Flexible capacity tier (OpenAI/Google families)"),
            SettingOption("scale", label: "Scale", detail: "Scale Tier credits (OpenAI family)"),
            SettingOption("priority", label: "Priority", detail: "Priority on every supported family of the spawned model"),
        ],
        "retry.usageReservePolicy": [
            SettingOption("confirm", label: "Confirm interactively", detail: "Keep interactive sessions on the primary until confirmed; background agents auto-fallback"),
            SettingOption("auto", label: "Auto-fallback", detail: "Always select the next eligible configured fallback"),
            SettingOption("fail-closed", label: "Fail closed", detail: "Do not spend reserve quota or select a fallback"),
        ],
        "retry.fallbackRevertPolicy": [
            SettingOption("cooldown-expiry", label: "Cooldown expiry", detail: "Return to the primary model after its suppression window ends"),
            SettingOption("never", label: "Never", detail: "Stay on the fallback model until manually changed"),
        ],
        "steeringMode": [
            SettingOption("all"),
            SettingOption("one-at-a-time"),
        ],
        "followUpMode": [
            SettingOption("all"),
            SettingOption("one-at-a-time"),
        ],
        "interruptMode": [
            SettingOption("immediate"),
            SettingOption("wait"),
        ],
        "loop.mode": [
            SettingOption("prompt", label: "Prompt", detail: "Re-submit the prompt as a follow-up message (current behavior)"),
            SettingOption("compact", label: "Compact", detail: "Compact the session context, then re-submit the prompt"),
            SettingOption("reset", label: "Reset", detail: "Start a new session, then re-submit the prompt"),
        ],
        "doubleEscapeAction": [
            SettingOption("rewind"),
            SettingOption("tree"),
            SettingOption("none"),
        ],
        "treeFilterMode": [
            SettingOption("default"),
            SettingOption("no-tools"),
            SettingOption("user-only"),
            SettingOption("labeled-only"),
            SettingOption("all"),
        ],
        "update.channel": [
            SettingOption("stable", label: "Stable"),
            SettingOption("canary", label: "Canary"),
        ],
        "marketplace.autoUpdate": [
            SettingOption("off", label: "Off", detail: "Don't check for plugin updates"),
            SettingOption("notify", label: "Notify", detail: "Check on startup and notify when updates are available"),
            SettingOption("auto", label: "Auto", detail: "Check on startup and auto-install updates"),
        ],
        "startup.changelogMode": [
            SettingOption("summary", label: "Summary", detail: "Show release and change counts with a /changelog hint"),
            SettingOption("expanded", label: "Expanded", detail: "Show the recent release notes in full"),
            SettingOption("hidden", label: "Hidden", detail: "Do not show release notes on startup"),
        ],
        "completion.notify": [
            SettingOption("on"),
            SettingOption("off"),
        ],
        "error.notify": [
            SettingOption("on"),
            SettingOption("off"),
        ],
        "ask.notify": [
            SettingOption("on"),
            SettingOption("off"),
        ],
        "share.store": [
            SettingOption("blob", label: "Encrypted Blob", detail: "Upload to the share server (no GitHub account needed; avoids gist API rate limits)"),
            SettingOption("gist", label: "GitHub Gist", detail: "Push to a secret gist (needs authenticated gh), falling back to the share server"),
        ],
        "stt.modelName": [
            SettingOption("fast", label: "Fast (Whisper base)", detail: "Whisper base, multilingual. Smallest + fastest; lowest accuracy. Best for low-resource machines."),
            SettingOption("balanced", label: "Balanced (Whisper small)", detail: "Whisper small, multilingual. More accurate than Fast, still light on CPU/RAM."),
            SettingOption("turbo", label: "Turbo (Whisper large-v3)", detail: "Whisper large-v3-turbo, 99 languages. Widest language coverage; large download, slower."),
            SettingOption("parakeet", label: "Parakeet TDT v3 (SoTA)", detail: "NVIDIA Parakeet TDT 0.6B v3, 25 languages. Open ASR Leaderboard leader — best accuracy and far fastest decoding. Default."),
        ],
        "stt.submitTrigger": [
            SettingOption("never", label: "Never", detail: "Never automatically submit; insert dictation and remain in editor."),
            SettingOption("release", label: "Release", detail: "Submit on release if the utterance has 2+ words to avoid accidental sends."),
            SettingOption("release-complete", label: "Release with complete sentence", detail: "Submit on release if the utterance ends with sentence-terminal punctuation (. ? ! etc.)."),
            SettingOption("say-submit", label: "When I Say Submit", detail: "Submit if the utterance ends with a word containing 'submit' (strips that word before submitting)."),
        ],
        "snapcompact.systemPrompt": [
            SettingOption("none", label: "None", detail: "Keep the system prompt as text."),
            SettingOption("agents-md", label: "AGENTS.md", detail: "Only move loaded context-file instructions to images, when that saves tokens."),
            SettingOption("all", label: "All", detail: "Move the full system prompt to images, when that saves tokens."),
        ],
        "tools.format": [
            SettingOption("auto", label: "Auto", detail: "Use native tool calls unless the model is known not to support them."),
            SettingOption("native", label: "Native", detail: "Use provider-native tool calls."),
            SettingOption("glm", label: "GLM", detail: "Use GLM-style in-band tool calls."),
            SettingOption("hermes", label: "Hermes", detail: "Use Hermes-style in-band tool calls."),
            SettingOption("kimi", label: "Kimi", detail: "Use Kimi-style in-band tool calls."),
            SettingOption("xml", label: "XML", detail: "Use generic XML in-band tool calls."),
            SettingOption("anthropic", label: "Anthropic", detail: "Use Anthropic-style in-band tool calls."),
            SettingOption("deepseek", label: "DeepSeek", detail: "Use DeepSeek-style in-band tool calls."),
            SettingOption("harmony", label: "Harmony", detail: "Use Harmony-style in-band tool calls."),
            SettingOption("qwen3", label: "Qwen3", detail: "Use the Qwen3 owned dialect."),
            SettingOption("gemini", label: "Gemini", detail: "Use the Gemini owned dialect."),
            SettingOption("gemma", label: "Gemma", detail: "Use the Gemma owned dialect."),
            SettingOption("minimax", label: "MiniMax", detail: "Use the MiniMax owned dialect."),
        ],
        "snapcompact.shape": [
            SettingOption("auto", label: "Auto", detail: "Picks a shape tuned for the current model, falling back to its provider family."),
            SettingOption("8x8r-bw", label: "8x8 repeated, black", detail: "unscii square cell, black ink, every line printed twice with the copy on a pale highlight band."),
            SettingOption("8x8r-sent", label: "8x8 repeated, sentence hues", detail: "Repeated grid with ink cycling six hues at sentence boundaries."),
            SettingOption("8x8u-bw", label: "8x8, black", detail: "Plain unscii square cell, single-printed lines, black ink."),
            SettingOption("8x8u-sent", label: "8x8, sentence hues", detail: "Plain unscii square cell with sentence-hue ink."),
            SettingOption("6x6u-bw", label: "6x6 dense, black", detail: "unscii squeezed to 6x6 — densest readable cell, fewest frames — in black ink."),
            SettingOption("6x6u-sent", label: "6x6 dense, sentence hues", detail: "Densest cell with sentence-hue ink."),
            SettingOption("5x8-bw", label: "5x8 legacy, black", detail: "Original X.org 5x8 glyphs on the 2576px frame, black ink."),
            SettingOption("5x8-sent", label: "5x8 legacy, sentence hues", detail: "The original snapcompact shape (pre-shape-table sessions rendered this)."),
            SettingOption("6x12-dim", label: "6x12, dimmed stopwords", detail: "X.org 6x12 glyphs, black ink, function words dimmed gray."),
            SettingOption("8x13-bw", label: "8x13, black", detail: "X.org 8x13 glyphs, black ink."),
            SettingOption("8on16-bw", label: "8x13 on 16px pitch, black", detail: "8x13 glyphs on an 8x16 cell (extra leading), black ink."),
            SettingOption("8on22-bw", label: "8x13 on 22px pitch (leading), black", detail: "8x13 glyphs on an 8x22 cell — extra line spacing so rows don't crowd. Default for OpenAI/Google."),
            SettingOption("11on16-bw", label: "8x13 on 11px advance (tracking), black", detail: "8x13 glyphs on an 11x16 cell — extra letter spacing so characters don't merge. Default for Anthropic."),
            SettingOption("silver16-bw", label: "Silver 16, CJK", detail: "Embedded Silver TrueType font on a 16px grid for CJK and other non-Latin text."),
            SettingOption("doc-8on16-bw", label: "Doc 8on16, black", detail: "Two word-wrapped newspaper columns of 8x13 glyphs on a 16px pitch, black ink."),
            SettingOption("doc-8on16-sent", label: "Doc 8on16, sentence hues", detail: "Two-column doc layout with sentence-hue ink."),
            SettingOption("doc-8on16-sent-dim", label: "Doc 8on16, sentence hues + dimmed stopwords", detail: "Two-column doc layout, sentence-hue ink, function words dimmed gray."),
        ],
        "memory.backend": [
            SettingOption("off", label: "Off", detail: "No memory subsystem runs"),
            SettingOption("local", label: "Local", detail: "Local rollout summarisation pipeline (memory_summary.md)"),
            SettingOption("hindsight", label: "Hindsight", detail: "Vectorize Hindsight remote memory service"),
            SettingOption("mnemopi", label: "Mnemopi", detail: "Local SQLite recall/retain backend with optional embeddings"),
            SettingOption("sharpshooter", label: "Sharpshooter", detail: "Friction-gated project decision files (architecture/product/style), consolidated in the background"),
        ],
        "mnemopi.scoping": [
            SettingOption("global", label: "Global", detail: "One shared Mnemopi bank for every project"),
            SettingOption("per-project", label: "Per project", detail: "Project-local Mnemopi bank per cwd basename"),
            SettingOption("per-project-tagged", label: "Per project (tagged)", detail: "Write to a project-local bank but merge project + shared recall results"),
        ],
        "mnemopi.embeddingVariant": [
            SettingOption("en", label: "English (bge-base-en-v1.5)", detail: "BAAI/bge-base-en-v1.5 (768d), English-only"),
            SettingOption("multilingual", label: "Multilingual (multilingual-e5-large)", detail: "intfloat/multilingual-e5-large (1024d), cross-language recall"),
        ],
        "mnemopi.llmMode": [
            SettingOption("none", label: "None", detail: "Disable Mnemopi LLM-backed extraction"),
            SettingOption("smol", label: "Online (tiny)", detail: "Use the online tiny model (the TINY role from /models, else @smol)"),
            SettingOption("remote", label: "Remote", detail: "Use the Mnemopi remote LLM settings below"),
        ],
        "hindsight.scoping": [
            SettingOption("global", label: "Global", detail: "One shared bank — every project sees the same memories"),
            SettingOption("per-project", label: "Per project", detail: "Isolated bank per cwd basename — projects cannot see each other's memories"),
            SettingOption("per-project-tagged", label: "Per project (tagged)", detail: "Shared bank, retains tagged with project:<cwd>. Recall surfaces project + untagged global memories together"),
        ],
        "hindsight.retainMode": [
            SettingOption("full-session", label: "Full session", detail: "Upsert one document per session (recommended)"),
            SettingOption("last-turn", label: "Last turn", detail: "Chunked retention sliced by turn boundaries"),
        ],
        "hindsight.recallBudget": [
            SettingOption("low"),
            SettingOption("mid"),
            SettingOption("high"),
        ],
        "ttsr.contextMode": [
            SettingOption("discard"),
            SettingOption("keep"),
        ],
        "ttsr.interruptMode": [
            SettingOption("always", detail: "Interrupt on prose and tool streams"),
            SettingOption("prose-only", detail: "Interrupt only on reply/thinking matches"),
            SettingOption("tool-only", detail: "Interrupt only on tool-call argument matches"),
            SettingOption("never", detail: "Never interrupt; inject warning after completion"),
        ],
        "ttsr.repeatMode": [
            SettingOption("once"),
            SettingOption("after-gap"),
        ],
        "edit.mode": [
            SettingOption("apply_patch"),
            SettingOption("hashline"),
            SettingOption("patch"),
            SettingOption("replace"),
            SettingOption("sloppy"),
        ],
        "bash.direnv": [
            SettingOption("auto"),
            SettingOption("off"),
        ],
        "shellMinimizer.sourceOutlineLevel": [
            SettingOption("default"),
            SettingOption("aggressive"),
        ],
        "python.kernelMode": [
            SettingOption("session"),
            SettingOption("per-call"),
        ],
        "tools.approvalMode": [
            SettingOption("always-ask", label: "Always ask", detail: "Auto-approve read-only tools; require confirmation for write and exec tools."),
            SettingOption("write", label: "Write", detail: "Auto-approve read-only and write tools; require confirmation for exec tools such as bash, eval, browser, and task."),
            SettingOption("yolo", label: "Yolo", detail: "Auto-approve read, write, and exec tools. User policy can still require confirmation or block calls."),
        ],
        "todo.eager": [
            SettingOption("default", label: "Default", detail: "Model decides; no automatic todo list"),
            SettingOption("preferred", label: "Preferred", detail: "Suggests a todo list on the first message (reminder, not forced)"),
            SettingOption("always", label: "Always", detail: "Forces a comprehensive todo list on the first message"),
        ],
        "async.pollWaitDuration": [
            SettingOption("5s", label: "5 seconds"),
            SettingOption("10s", label: "10 seconds"),
            SettingOption("30s", label: "30 seconds"),
            SettingOption("1m", label: "1 minute"),
            SettingOption("5m", label: "5 minutes"),
            SettingOption("smart", label: "Smart", detail: "Default — adaptive 5s→5m, resets when you stop polling"),
        ],
        "tools.xdevDocs": [
            SettingOption("inline", label: "All Devices", detail: "Inline docs and schemas for every mounted device."),
            SettingOption("builtins", label: "Built-ins Only", detail: "Inline built-in docs; fetch MCP and extension docs on demand."),
            SettingOption("catalog", label: "Catalog Only", detail: "List every device; fetch all docs on demand."),
        ],
        "isolation.backend": [
            SettingOption("auto", label: "Auto", detail: "Let the PAL pick the best available backend"),
            SettingOption("apfs", label: "APFS", detail: "macOS clonefile reflink (APFS)"),
            SettingOption("btrfs", detail: "btrfs subvolume snapshot"),
            SettingOption("zfs", label: "ZFS", detail: "ZFS snapshot + clone"),
            SettingOption("reflink", label: "Reflink", detail: "Linux FICLONE per-file reflink"),
            SettingOption("overlayfs", label: "Overlayfs", detail: "Linux kernel overlay (or fuse-overlayfs fallback)"),
            SettingOption("projfs", label: "ProjFS", detail: "Windows Projected File System"),
            SettingOption("block-clone", label: "Block clone", detail: "Windows FSCTL_DUPLICATE_EXTENTS_TO_FILE (NTFS/ReFS)"),
            SettingOption("rcopy", label: "Recursive copy", detail: "git worktree if available, otherwise recursive copy"),
        ],
        "task.isolation.merge": [
            SettingOption("patch", label: "Patch", detail: "Combine diffs and git apply"),
            SettingOption("branch", label: "Branch", detail: "Commit per task, merge with --no-ff"),
        ],
        "task.isolation.commits": [
            SettingOption("generic", label: "Generic", detail: "Static commit message"),
            SettingOption("ai", label: "AI", detail: "AI-generated commit message from diff"),
        ],
        "task.eager": [
            SettingOption("default", label: "Default", detail: "Uses the selected model's policy; some models require an explicit delegation request"),
            SettingOption("preferred", label: "Preferred", detail: "Adds delegation guidance to the system prompt"),
            SettingOption("always", label: "Always", detail: "Prompt guidance plus a first-turn delegation reminder"),
        ],
        "task.maxEffort": [
            SettingOption("minimal", label: "min", detail: "Very brief reasoning (~1k tokens)"),
            SettingOption("low", detail: "Light reasoning (~2k tokens)"),
            SettingOption("medium", detail: "Moderate reasoning (~8k tokens)"),
            SettingOption("high", detail: "Deep reasoning (~16k tokens)"),
            SettingOption("xhigh", detail: "Extended reasoning (~32k tokens)"),
            SettingOption("max", detail: "Maximum reasoning the model supports"),
        ],
        "providers.antigravityEndpoint": [
            SettingOption("auto", label: "Auto", detail: "Try production endpoint, fail over to sandbox on 5xx/429"),
            SettingOption("production", label: "Production Only", detail: "Force production endpoint only"),
            SettingOption("sandbox", label: "Sandbox Only", detail: "Force sandbox endpoint only"),
        ],
        "providers.fireworksTier": [
            SettingOption("standard", label: "Standard", detail: "Default serving path (no service_tier)"),
            SettingOption("priority", label: "Priority", detail: "Priority serving path: higher reliability, premium per-token pricing"),
        ],
        "live.voice": [
            SettingOption("arbor", label: "Arbor"),
            SettingOption("breeze", label: "Breeze"),
            SettingOption("cove", label: "Cove"),
            SettingOption("ember", label: "Ember"),
            SettingOption("juniper", label: "Juniper"),
            SettingOption("maple", label: "Maple"),
            SettingOption("sol", label: "Sol"),
            SettingOption("spruce", label: "Spruce"),
            SettingOption("vale", label: "Vale"),
        ],
        "providers.tts": [
            SettingOption("auto", label: "Auto", detail: "Prefer local on-device TTS; route .mp3 output to xAI when credentials exist"),
            SettingOption("local", label: "Local", detail: "On-device neural TTS (Kokoro-82M); output is WAV/PCM16"),
            SettingOption("xai", label: "xAI Grok Voice", detail: "Requires xAI Grok OAuth or XAI_API_KEY; MP3 or WAV"),
            SettingOption("deepinfra", label: "DeepInfra Speech", detail: "Requires DEEPINFRA_API_KEY; MP3 or WAV"),
        ],
        "tts.localModel": [
            SettingOption("kokoro", label: "Kokoro-82M", detail: "Kokoro-82M neural TTS — SoTA on-device quality, multi-voice, fully local"),
        ],
        "tts.localVoice": [
            SettingOption("af_heart", label: "Heart (American female)"),
            SettingOption("af_bella", label: "Bella (American female)"),
            SettingOption("af_nicole", label: "Nicole (American female)"),
            SettingOption("af_aoede", label: "Aoede (American female)"),
            SettingOption("af_kore", label: "Kore (American female)"),
            SettingOption("af_sarah", label: "Sarah (American female)"),
            SettingOption("am_michael", label: "Michael (American male)"),
            SettingOption("am_fenrir", label: "Fenrir (American male)"),
            SettingOption("am_puck", label: "Puck (American male)"),
            SettingOption("bf_emma", label: "Emma (British female)"),
            SettingOption("bm_george", label: "George (British male)"),
            SettingOption("bm_fable", label: "Fable (British male)"),
        ],
        "speech.mode": [
            SettingOption("all", label: "All (messages + thinking)"),
            SettingOption("assistant", label: "Assistant messages"),
            SettingOption("yield", label: "Final message only"),
        ],
        "speech.voice": [
            SettingOption("af_heart", label: "Heart (American female)"),
            SettingOption("af_bella", label: "Bella (American female)"),
            SettingOption("af_nicole", label: "Nicole (American female)"),
            SettingOption("af_aoede", label: "Aoede (American female)"),
            SettingOption("af_kore", label: "Kore (American female)"),
            SettingOption("af_sarah", label: "Sarah (American female)"),
            SettingOption("am_michael", label: "Michael (American male)"),
            SettingOption("am_fenrir", label: "Fenrir (American male)"),
            SettingOption("am_puck", label: "Puck (American male)"),
            SettingOption("bf_emma", label: "Emma (British female)"),
            SettingOption("bm_george", label: "George (British male)"),
            SettingOption("bm_fable", label: "Fable (British male)"),
        ],
        "providers.tinyModel": [
            SettingOption("online", label: "Online (TINY role, else @smol)", detail: "Online title generation: the TINY model role (set one in /models) when assigned, otherwise the online fallback (commit role, then @smol). No local download or on-device inference."),
            SettingOption("lfm2.5-230m", label: "LFM2.5 230M", detail: "Recommended local model; fastest LFM2.5 option, about 214 MB cached."),
            SettingOption("lfm2.5-350m", label: "LFM2.5 350M", detail: "Larger LFM2.5 option, about 292 MB cached; tends toward terse titles."),
            SettingOption("falcon-h1-90m", label: "Falcon H1 Tiny 90M", detail: "Smallest option, about 147 MB cached; lower fidelity on complex prompts."),
        ],
        "providers.tinyModelDevice": [
            SettingOption("default", label: "Default", detail: "CPU-only inference"),
            SettingOption("gpu", label: "GPU", detail: "Accelerated provider (WebGPU/Metal, CUDA, or DirectML)"),
            SettingOption("cpu", label: "CPU", detail: "CPU-only inference"),
            SettingOption("mlx", label: "MLX", detail: "Apple silicon GPU via mlx-lm (Python subprocess; macOS arm64)"),
            SettingOption("metal", label: "Metal", detail: "Alias for MLX"),
            SettingOption("webgpu", label: "WebGPU", detail: "WebGPU/Metal backend"),
            SettingOption("cuda", label: "CUDA", detail: "NVIDIA CUDA (Linux x64)"),
            SettingOption("dml", label: "DirectML", detail: "DirectML backend (Windows)"),
            SettingOption("coreml", label: "CoreML", detail: "Apple CoreML (opt-in; can fail to load)"),
            SettingOption("auto", label: "Auto", detail: "Let ONNX Runtime choose a provider"),
            SettingOption("wasm", label: "WASM", detail: "WebAssembly backend"),
            SettingOption("webnn", label: "WebNN", detail: "WebNN backend"),
            SettingOption("webnn-gpu", label: "WebNN GPU", detail: "WebNN GPU device"),
            SettingOption("webnn-cpu", label: "WebNN CPU", detail: "WebNN CPU device"),
            SettingOption("webnn-npu", label: "WebNN NPU", detail: "WebNN NPU device"),
        ],
        "providers.tinyModelDtype": [
            SettingOption("default", label: "Default", detail: "Each model's shipped dtype (currently q4)"),
            SettingOption("q4", detail: "4-bit weights; smallest and fastest"),
            SettingOption("q4f16", detail: "4-bit weights with fp16 activations"),
            SettingOption("q8", detail: "8-bit quantization"),
            SettingOption("fp16", detail: "16-bit float; higher fidelity, larger"),
            SettingOption("fp32", detail: "Full precision; largest and slowest"),
            SettingOption("int8", detail: "Signed 8-bit integer"),
            SettingOption("uint8", detail: "Unsigned 8-bit integer"),
            SettingOption("bnb4", detail: "bitsandbytes 4-bit"),
            SettingOption("q2", detail: "2-bit weights"),
            SettingOption("q2f16", detail: "2-bit weights with fp16 activations"),
            SettingOption("q1", detail: "1-bit weights"),
            SettingOption("q1f16", detail: "1-bit weights with fp16 activations"),
            SettingOption("auto", label: "Auto", detail: "Let transformers.js choose per device"),
        ],
        "providers.memoryModel": [
            SettingOption("online", label: "Online (TINY role, else @smol)", detail: "Use the online model: the TINY role from /models when set, otherwise @smol. No local model download or on-device inference."),
            SettingOption("qwen3-1.7b", label: "Qwen3 1.7B", detail: "MLX only (providers.tinyModelDevice=mlx): onnxruntime-node cannot run this ONNX export's RotaryEmbedding cache updates."),
            SettingOption("llama3.2:3b", label: "Llama 3.2 3B", detail: "Larger Llama 3.2 option for local memory/classifier tasks; higher quality potential at higher disk/RAM/latency cost."),
            SettingOption("gemma-3-1b", label: "Gemma 3 1B", detail: "Best consolidation/dedup; lighter footprint, but leaks small talk during extraction."),
            SettingOption("qwen2.5-1.5b", label: "Qwen2.5 1.5B", detail: "Best extraction granularity (atomic facts); weaker consolidation."),
            SettingOption("lfm2-1.2b", label: "LFM2 1.2B", detail: "Fastest load; solid all-rounder, slightly noisier extraction labels."),
        ],
        "providers.autoThinkingModel": [
            SettingOption("online", label: "Online (TINY role, else @smol)", detail: "Classify prompt difficulty online with the TINY role model (set one in /models) or @smol; no local download or on-device inference."),
            SettingOption("qwen3-1.7b", label: "Qwen3 1.7B", detail: "MLX only (providers.tinyModelDevice=mlx): onnxruntime-node cannot run this ONNX export's RotaryEmbedding cache updates."),
            SettingOption("llama3.2:3b", label: "Llama 3.2 3B", detail: "Larger Llama 3.2 option for local memory/classifier tasks; higher quality potential at higher disk/RAM/latency cost."),
            SettingOption("gemma-3-1b", label: "Gemma 3 1B", detail: "Best consolidation/dedup; lighter footprint, but leaks small talk during extraction."),
            SettingOption("qwen2.5-1.5b", label: "Qwen2.5 1.5B", detail: "Best extraction granularity (atomic facts); weaker consolidation."),
            SettingOption("lfm2-1.2b", label: "LFM2 1.2B", detail: "Fastest load; solid all-rounder, slightly noisier extraction labels."),
        ],
        "providers.autoThinkingMaxEffort": [
            SettingOption("xhigh", detail: "Classifier stops at xhigh (default)"),
            SettingOption("max", detail: "Classifier may resolve max where the model supports it"),
        ],
        "features.unexpectedStopDetection": [
            SettingOption("none", label: "None", detail: "Disabled"),
            SettingOption("mechanical", label: "Mechanical", detail: "Retry stops with no visible assistant message; tool calls are excluded (default)"),
            SettingOption("smart", label: "Smart", detail: "Mechanical + small-model classification of text-only stops"),
        ],
        "providers.unexpectedStopModel": [
            SettingOption("online", label: "Online (TINY role, else @smol)", detail: "Use the online model: the TINY role from /models when set, otherwise @smol. No local model download or on-device inference."),
            SettingOption("qwen3-1.7b", label: "Qwen3 1.7B", detail: "MLX only (providers.tinyModelDevice=mlx): onnxruntime-node cannot run this ONNX export's RotaryEmbedding cache updates."),
            SettingOption("llama3.2:3b", label: "Llama 3.2 3B", detail: "Larger Llama 3.2 option for local memory/classifier tasks; higher quality potential at higher disk/RAM/latency cost."),
            SettingOption("gemma-3-1b", label: "Gemma 3 1B", detail: "Best consolidation/dedup; lighter footprint, but leaks small talk during extraction."),
            SettingOption("qwen2.5-1.5b", label: "Qwen2.5 1.5B", detail: "Best extraction granularity (atomic facts); weaker consolidation."),
            SettingOption("lfm2-1.2b", label: "LFM2 1.2B", detail: "Fastest load; solid all-rounder, slightly noisier extraction labels."),
        ],
        "providers.kimiApiFormat": [
            SettingOption("auto", label: "Auto", detail: "Use the model's server-declared protocol"),
            SettingOption("openai", label: "OpenAI", detail: "api.kimi.com"),
            SettingOption("anthropic", label: "Anthropic", detail: "api.moonshot.ai"),
        ],
        "providers.openaiWebsockets": [
            SettingOption("auto", label: "Auto", detail: "Use model/provider default websocket behavior"),
            SettingOption("off", label: "Off", detail: "Disable websockets for OpenAI Codex models"),
            SettingOption("on", label: "On", detail: "Force websockets for OpenAI Codex models"),
        ],
        "providers.cacheRetention": [
            SettingOption("auto", label: "Auto", detail: "Provider default — Anthropic uses 5m entries kept warm by idle keep-alive refreshes; PI_CACHE_RETENTION still applies"),
            SettingOption("short", label: "Short (5m)", detail: "Cheapest cache writes; Anthropic keeps the entry warm with bounded keep-alive refreshes while idle"),
            SettingOption("long", label: "Long (1h)", detail: "1h TTL where the provider supports it; pricier writes, no keep-alive refresh requests"),
            SettingOption("none", label: "Off", detail: "Disable prompt caching and cache-affinity routing"),
        ],
        "providers.openrouterVariant": [
            SettingOption("default", label: "Default", detail: "No suffix; use OpenRouter's default routing"),
            SettingOption("nitro", label: ":nitro", detail: "Prioritize throughput / lowest latency"),
            SettingOption("floor", label: ":floor", detail: "Prioritize cheapest available provider"),
            SettingOption("online", label: ":online", detail: "Enable OpenRouter's web-search plugin"),
            SettingOption("exacto", label: ":exacto", detail: "Cherry-picked high-quality providers (only defined for select models)"),
        ],
        "providers.fetch": [
            SettingOption("auto", label: "Auto", detail: "Priority: native > trafilatura > lynx > parallel > firecrawl > jina"),
            SettingOption("native", label: "Native", detail: "In-process HTML→Markdown converter (always available)"),
            SettingOption("trafilatura", label: "Trafilatura", detail: "Auto-installs via uv/pip"),
            SettingOption("lynx", label: "Lynx", detail: "Requires lynx system package"),
            SettingOption("parallel", label: "Parallel", detail: "Requires PARALLEL_API_KEY"),
            SettingOption("firecrawl", label: "Firecrawl", detail: "Requires FIRECRAWL_API_KEY"),
            SettingOption("jina", label: "Jina", detail: "Uses r.jina.ai reader (JINA_API_KEY optional)"),
        ],
        "codexResets.autoRedeem": [
            SettingOption("unset", label: "Unset", detail: "Check eligibility, then ask before spending the first saved reset."),
            SettingOption("yes", label: "Yes", detail: "Spend eligible saved resets without prompting."),
            SettingOption("no", label: "No", detail: "Do not run the saved-reset auto-redeem check."),
        ],
        "provider.appendOnlyContext": [
            SettingOption("auto", label: "Auto", detail: "Enable for known prefix-cache providers (recommended)"),
            SettingOption("on", label: "On", detail: "Always enable append-only context"),
            SettingOption("off", label: "Off", detail: "Disable append-only context"),
        ],
        "dev.autoqaConsent": [
            SettingOption("unset"),
            SettingOption("granted"),
            SettingOption("denied"),
        ],
    ]

    /// Gap-fill text for keys whose omp config list entry ships no description.
    /// OMP's own runtime description always wins when present. Hand-written;
    /// the schema documents no keys beyond what config list already reports.
    static let descriptions: [String: String] = [:]

    /// Closed value sets for array settings, where OMP's source enumerates them.
    static let knownArrayValues: [String: [String]] = [
        "cycleOrder": ["default", "plan", "advisor", "smol", "commit", "designer", "slow", "task", "tiny", "vision"],
        "compaction.methodOrder": ["remote", "snapcompact", "handoff", "soft", "shake"],
        "providers.webSearchOrder": ["perplexity", "gemini", "anthropic", "codex", "xai", "zai", "exa", "tinyfish", "jina", "kagi", "tavily", "firecrawl", "brave", "kimi", "parallel", "synthetic", "searxng", "startpage", "duckduckgo", "ecosia", "google", "mojeek", "public"],
        "providers.imageOrder": ["openai", "openai-codex", "antigravity", "xai", "gemini", "openrouter", "deepinfra"],
    ]

    /// Array keys whose values come from the live model/provider catalog.
    static let catalogFedArrays: Set<String> = [
        "enabledModels", "modelProviderOrder", "enabledProviders", "disabledProviders",
    ]
}

