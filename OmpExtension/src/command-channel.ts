export const CHANNEL_MARKER = "tenx.provider-accounts.v1";

export interface ChannelCommand {
	id: string;
	command: string;
	params?: unknown;
}

export type ChannelReply =
	| { id: string; ok: true; data: unknown; events?: unknown[] }
	| { id: string; ok: false; error: string; events?: unknown[] };

interface ChannelUI {
	input(title: string, placeholder?: string): Promise<string | undefined>;
}

/**
 * Holds one awaited request open at all times. The client answers it with a
 * command; the extension carries the previous reply forward in `placeholder`,
 * so a single primitive serves both directions.
 *
 * This is also the only way an unsolicited event (an availability change, a
 * failover OMP applied on its own) reaches the client: there is no push
 * primitive, only this request/reply turn. `drainEvents` is polled once per
 * turn, right before a reply is carried forward, and whatever it returns
 * rides along under an `events` key on THAT reply — the same reply the
 * client's own command triggered. Two consequences worth being explicit
 * about, since neither is a bug: (1) an event that fires while no command is
 * pending (the common case — the client mostly sits idle on the open
 * `input()` call) is not lost, but it is not delivered either, until the
 * client happens to send its next command, whatever that command is; there
 * is no bound on how long that can take. (2) `events` is omitted entirely
 * — not sent as `events: []` — whenever `drainEvents` returns nothing, so a
 * reply with nothing to report is byte-identical to what this function
 * produced before `drainEvents` existed (see the Task 1 test in
 * `command-channel.test.ts`, which spawns a real `omp` and asserts the
 * pinged reply's exact shape).
 */
export async function openCommandChannel(
	ui: ChannelUI,
	handle: (command: ChannelCommand) => Promise<unknown>,
	shouldContinue: () => boolean = () => true,
	drainEvents: () => unknown[] = () => [],
): Promise<void> {
	let carry: string | undefined;
	while (shouldContinue()) {
		const raw = await ui.input(CHANNEL_MARKER, carry);
		if (raw === undefined) return;
		// Declared outside the try so a `handle` rejection can still report the
		// command's own id in the catch block below, not just JSON.parse failures.
		let command: ChannelCommand | undefined;
		let reply: ChannelReply;
		try {
			command = JSON.parse(raw) as ChannelCommand;
			reply = { id: command.id, ok: true, data: await handle(command) };
		} catch (error) {
			reply = {
				id: command?.id ?? "unknown",
				ok: false,
				error: error instanceof Error ? error.message : String(error),
			};
		}
		// Attached on the error path too — a malformed or failing command must
		// not blackhole a frame that was already waiting to go out.
		const events = drainEvents();
		carry = JSON.stringify(events.length > 0 ? { ...reply, events } : reply);
	}
}
