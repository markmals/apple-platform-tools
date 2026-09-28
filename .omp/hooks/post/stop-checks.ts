import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

// Before the agent finishes, run the checks that lint and CI would fail on and
// send the agent back to fix them.
export default function stopChecks(pi: ExtensionAPI): void {
  pi.on("session_stop", async (event) => {
    // One refusal per stop, so a failure the agent can't fix doesn't trap the session.
    if (event.stop_hook_active) return;

    const run = (command: string, args: string[]) => pi.exec(command, args, { signal: event.signal });
    const failures: string[] = [];

    const swiftDiff = await run("git", ["diff", "--quiet", "HEAD", "--", "*.swift"]);
    if (swiftDiff.code !== 0) {
      const lint = await run("mise", ["run", "lint"]);
      if (lint.code !== 0) failures.push(report("Lint failures", lint));
    }

    // Unconditional: the check is sub-second, and a dirty-tree gate would miss
    // specs edited and committed within the same session.
    const contracts = await run("mise", ["run", "mac-dev-skills-contracts:check"]);
    if (contracts.code !== 0) {
      failures.push(report("mac-dev-skills contract exports drifted (CI job: downstream-contracts)", contracts));
    }

    if (failures.length > 0) return { decision: "block", reason: failures.join("\n\n") };
  });
}

function report(title: string, result: { stdout: string; stderr: string }): string {
  return `${title}:\n\n${(result.stdout + result.stderr).trim()}`;
}
