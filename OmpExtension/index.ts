import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { listAccounts, pinAccount, removeAccount } from "./src/accounts";
import { openCommandChannel } from "./src/command-channel";

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null;
}

function requireString(params: unknown, key: string): string {
	const value = isRecord(params) ? params[key] : undefined;
	if (typeof value !== "string" || value.length === 0) {
		throw new Error(`Missing or invalid "${key}" parameter`);
	}
	return value;
}

export default function (pi: ExtensionAPI) {
	// `ExtensionHandler<E> = (event: E, ctx: ExtensionContext) => ...` — the UI
	// context lives on the second parameter, not on the session_start event
	// (which is just `{ type: "session_start" }`).
	pi.on("session_start", async (_event, ctx) => {
		void openCommandChannel(ctx.ui, async command => {
			switch (command.command) {
				case "ping":
					return "pong";
				case "hello":
					return { contractVersion: 1 };
				case "list_accounts":
					return { accounts: await listAccounts(ctx, requireString(command.params, "providerId")) };
				case "pin_account":
					await pinAccount(ctx, requireString(command.params, "providerId"), requireString(command.params, "accountRef"));
					return { pinned: true };
				case "remove_account":
					return removeAccount(ctx, requireString(command.params, "providerId"), requireString(command.params, "accountRef"));
				default:
					throw new Error(`Unknown command: ${command.command}`);
			}
		});
	});
}
