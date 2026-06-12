# 0001 — Doctor (preconditions & attachable apps)

This folder specifies the two detection commands that run *before* any injection: `doctor`, which verifies the SIP/AMFI/LV/arm64e-ABI/arch/uitool-built/target-running precondition stack independently and reports exactly which link failed with a one-line remedy (and, only under the opt-in `--fix` flag, remediates the boot-arg / library-validation checks under sudo per [[domain.uitool.injection]]), and `list-apps`, which enumerates attachable processes with their pid, bundle id, hardened flag, and arch. Both inspect only the local machine and a process list — they touch no target process and carry zero injection risk, which is why they are the M0 starting point.

Depends on [[domain.uitool.injection]] (the precondition stack and attach-path model) and [[domain.uitool.ipc]] (the exit-code mapping these commands report against).
