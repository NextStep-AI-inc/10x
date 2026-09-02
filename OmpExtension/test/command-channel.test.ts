import { expect, test } from "bun:test";
import os from "node:os";
import path from "node:path";
import { openCommandChannel } from "../src/command-channel";

const MARKER = "tenx.provider-accounts.v1";

/**
 * Scripted `ChannelUI` fake: each `input()` call records the placeholder it
 * was given (the carried reply from the previous turn) and returns the next
 * queued raw command, or `undefined` once the queue is exhausted — which
 * `openCommandChannel` treats as "the client hung up" and returns. Lets the
 * `drainEvents` integration be exercised without spawning a real `omp`.
 */
class FakeUI {
	calls: (string | undefined)[] = [];
	#queue: (string | undefined)[];
	constructor(commands: string[]) {
		this.#queue = [...commands, undefined];
	}
	async input(_title: string, placeholder?: string): Promise<string | undefined> {
		this.calls.push(placeholder);
		return this.#queue.shift();
	}
}

test("the extension receives a command from the client and answers it", async () => {
	const sessionDir = path.join(os.tmpdir(), `tenx-channel-${Date.now()}`);
	const ompExecutable = Bun.which("omp") ?? path.join(os.homedir(), ".bun", "bin", "omp");
	const child = Bun.spawn(
		[ompExecutable, "--mode", "rpc", "--no-title", "--no-session", "-e", path.join(import.meta.dir, "..", "index.ts")],
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

// --- drainEvents: piggybacking availability/failover frames onto the next carried reply ---

test("omits the events key entirely when nothing is queued, keeping the reply byte-identical to before drainEvents existed", async () => {
	const ui = new FakeUI([JSON.stringify({ id: "c1", command: "ping" })]);

	await openCommandChannel(
		ui,
		async () => "pong",
		() => true,
		() => [],
	);

	expect(JSON.parse(ui.calls[1] as string)).toEqual({ id: "c1", ok: true, data: "pong" });
});

test("attaches queued events to the next successful reply", async () => {
	const ui = new FakeUI([JSON.stringify({ id: "c1", command: "ping" })]);
	const events = [{ type: "provider_account_changed", providerId: "anthropic", accountRef: "ref-a", reason: "automaticFailover", sequence: 1 }];

	await openCommandChannel(
		ui,
		async () => "pong",
		() => true,
		() => events,
	);

	expect(JSON.parse(ui.calls[1] as string)).toEqual({ id: "c1", ok: true, data: "pong", events });
});

test("attaches queued events to an error reply too, so a bad command never blackholes a pending frame", async () => {
	const ui = new FakeUI([JSON.stringify({ id: "c1", command: "boom" })]);
	const events = [{ type: "provider_account_changed", providerId: "anthropic", accountRef: "ref-a", reason: "manual", sequence: 1 }];

	await openCommandChannel(
		ui,
		async () => {
			throw new Error("nope");
		},
		() => true,
		() => events,
	);

	expect(JSON.parse(ui.calls[1] as string)).toEqual({ id: "c1", ok: false, error: "nope", events });
});

test("drainEvents runs only after a command has been handled, never before the channel has anything to reply to", async () => {
	const ui = new FakeUI([JSON.stringify({ id: "c1", command: "ping" })]);
	let drainCalls = 0;

	await openCommandChannel(
		ui,
		async () => "pong",
		() => true,
		() => {
			drainCalls += 1;
			return [];
		},
	);

	expect(drainCalls).toBe(1);
});
