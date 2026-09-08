import { expect, test } from "bun:test";
import { accountChangedFrame, createEventQueue, createEventSequencer } from "../src/events";

test("sequence numbers are monotonic within a process", () => {
	const seq = createEventSequencer();
	const first = seq.next("anthropic", "ref-a", "manual");
	const second = seq.next("anthropic", "ref-b", "failover");
	expect(first.sequence).toBe(1);
	expect(second.sequence).toBe(2);
	expect(second.reason).toBe("failover");
});

test("a repeated account for the same provider still advances the sequence", () => {
	const seq = createEventSequencer();
	seq.next("anthropic", "ref-a", "manual");
	expect(seq.next("anthropic", "ref-a", "manual").sequence).toBe(2);
});

// --- accountChangedFrame: wire shape and the reason translation ---

test("accountChangedFrame carries providerId, accountRef, and sequence verbatim", () => {
	const frame = accountChangedFrame("openai-codex", "ref-a", "manual", 5);
	expect(frame.type).toBe("provider_account_changed");
	expect(frame.providerId).toBe("openai-codex");
	expect(frame.accountRef).toBe("ref-a");
	expect(frame.sequence).toBe(5);
});

test("a manual reason passes through unchanged on the wire", () => {
	expect(accountChangedFrame("anthropic", "ref-a", "manual", 1).reason).toBe("manual");
});

test("a failover reason is translated to the wire literal automaticFailover", () => {
	// Verified against the already-committed Swift decoder
	// (OmpKit/Sources/OmpKit/Providers/ProviderAccount.swift:180-188), which
	// matches the exact string "automaticFailover" and would otherwise bucket
	// the brief's literal "failover" into .unknown("failover").
	expect(accountChangedFrame("anthropic", "ref-a", "failover", 1).reason).toBe("automaticFailover");
});

test("an unavailable reason passes through unchanged, for Swift's forward-compatible .unknown fallback", () => {
	expect(accountChangedFrame("anthropic", "ref-a", "unavailable", 1).reason).toBe("unavailable");
});

// --- createEventQueue: coalescing and drain semantics ---

test("drain returns nothing when the queue is empty", () => {
	expect(createEventQueue().drain()).toEqual([]);
});

test("drain empties the queue: a second drain call sees nothing new", () => {
	const queue = createEventQueue();
	queue.push(accountChangedFrame("anthropic", "ref-a", "manual", 1));
	expect(queue.drain()).toHaveLength(1);
	expect(queue.drain()).toEqual([]);
});

test("frames for different providers are both delivered, in sequence order", () => {
	const queue = createEventQueue();
	queue.push(accountChangedFrame("openai-codex", "ref-b", "manual", 2));
	queue.push(accountChangedFrame("anthropic", "ref-a", "manual", 1));

	const drained = queue.drain();

	expect(drained.map(f => f.providerId)).toEqual(["anthropic", "openai-codex"]);
});

test("a second frame for the same provider coalesces: only the newer one is delivered", () => {
	const queue = createEventQueue();
	queue.push(accountChangedFrame("anthropic", "ref-a", "failover", 1));
	queue.push(accountChangedFrame("anthropic", "ref-b", "failover", 2));

	const drained = queue.drain();

	expect(drained).toHaveLength(1);
	expect(drained[0]?.accountRef).toBe("ref-b");
	expect(drained[0]?.sequence).toBe(2);
});
