#pragma once

// SPEC: domain.uitool.injection
// Remote-inject the boot dylib into an already-running process (the cooperative
// attach-to-running path). Acquires the target's task port (task_for_pid — needs
// uitool signed with com.apple.security.cs.debugger, or root), then bootstraps a
// pthread inside the target that dlopen()s the dylib, which fires UIToolBoot's
// +load and starts the server. arm64 only (no PAC); the arm64e/unrestricted path
// is deferred.
//
// Returns 0 on success, or a non-zero stage code:
//   1  task_for_pid denied (missing debugger entitlement / not permitted)
//   2  could not allocate memory in the target
//   3  dylib path too long for the injected region
//   4  could not write the bootstrap into the target
//   5  could not make the bootstrap executable
//   6  could not allocate the bootstrap stack
//   7  could not create the bootstrap thread
int uitool_inject(int pid, const char *dylib_path);
