import { expect, test } from "bun:test";
import os from "node:os";
import path from "node:path";

const MARKER = "tenx.provider-accounts.v1";

test("the extension receives a command from the client and answers it", async () => {
	const sessionDir = path.join(os.tmpdir(), `tenx-channel-${Date.now()}`);
	const child = Bun.spawn(
		["omp", "--mode", "rpc", "--no-title", "--no-session", "-e", path.join(import.meta.dir, "..", "index.ts")],
		{ env: { ...Bun.env, PI_CODING_AGENT_DIR: sessionDir }, stdin: "pipe", stdout: "pipe", stderr: "pipe" },
	);
	const enc = new TextEncoder();
	const reader = child.stdout.getReader();
	const dec = new TextDecoder();
	let buf = "";
	const frames: Record<string, unknown>[] = [];
	const readUntil = async (match: (f: Record<string, unknown>) => boolean) => {
		for (;;) {
			const { value, done } = await reader.read();
			if (done) throw new Error("omp exited early");
			buf += dec.decode(value, { stream: true });
			let nl: number;
			while ((nl = buf.indexOf("\n")) >= 0) {
				const line = buf.slice(0, nl).trim();
				buf = buf.slice(nl + 1);
				if (!line) continue;
				const frame = JSON.parse(line) as Record<string, unknown>;
				frames.push(frame);
				if (match(frame)) return frame;
			}
		}
	};

	const opened = await readUntil(f => f.type === "extension_ui_request" && f.title === MARKER);
	// Wire contract verified against OMP's rpc-types.ts (`RpcExtensionUIResponse`)
	// and OmpKit's already-tested `RpcCommand.extensionUIResponse` encoder: the
	// reply is flat — `value` sits alongside `type`/`id`, with no `body` wrapper.
	child.stdin.write(
		enc.encode(
			`${JSON.stringify({
				type: "extension_ui_response",
				id: opened.id,
				value: JSON.stringify({ id: "c1", command: "ping" }),
			})}\n`,
		),
	);
	child.stdin.flush();
	const answered = await readUntil(
		f => f.type === "extension_ui_request" && f.title === MARKER && typeof f.placeholder === "string",
	);
	child.kill();

	expect(JSON.parse(answered.placeholder as string)).toEqual({ id: "c1", ok: true, data: "pong" });
}, 60_000);
