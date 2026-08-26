export const CHANNEL_MARKER = "tenx.provider-accounts.v1";

export interface ChannelCommand {
	id: string;
	command: string;
	params?: unknown;
}

export type ChannelReply = { id: string; ok: true; data: unknown } | { id: string; ok: false; error: string };

interface ChannelUI {
	input(title: string, placeholder?: string): Promise<string | undefined>;
}

/**
 * Holds one awaited request open at all times. The client answers it with a
 * command; the extension carries the previous reply forward in `placeholder`,
 * so a single primitive serves both directions.
 */
export async function openCommandChannel(
	ui: ChannelUI,
	handle: (command: ChannelCommand) => Promise<unknown>,
	shouldContinue: () => boolean = () => true,
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
		carry = JSON.stringify(reply);
	}
}
