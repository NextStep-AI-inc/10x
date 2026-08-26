import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { openCommandChannel } from "./src/command-channel";

export default function (pi: ExtensionAPI) {
	// `ExtensionHandler<E> = (event: E, ctx: ExtensionContext) => ...` — the UI
	// context lives on the second parameter, not on the session_start event
	// (which is just `{ type: "session_start" }`).
	pi.on("session_start", async (_event, ctx) => {
		void openCommandChannel(ctx.ui, async command => {
			if (command.command === "ping") return "pong";
			throw new Error(`Unknown command: ${command.command}`);
		});
	});
}
