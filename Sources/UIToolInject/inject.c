#include "UIToolInject.h"

#include <dlfcn.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <pthread.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>

// SPEC: domain.uitool.injection
// The cooperative attach-to-running injector. We write two tiny arm64 code blobs
// into the target and run them on a fresh mach thread:
//
//   mach blob (thread entry): pthread_create_from_mach_thread(&pt, NULL, thunk, path)
//                             then spin (the bootstrap thread is short-lived).
//   thunk (the pthread's start routine): dlopen(path, RTLD_NOW), then return.
//
// A raw mach thread can't safely call dlopen (no pthread TSD), so we use
// libpthread's pthread_create_from_mach_thread to bootstrap a real pthread that
// runs the dlopen — the standard, robust technique. dlopen's and
// pthread_create_from_mach_thread's addresses come from the dyld shared cache,
// which has one slide per boot shared across processes, so the addresses in this
// process are valid in the target.

extern int pthread_create_from_mach_thread(
    pthread_t *_Nullable, const pthread_attr_t *_Nullable, void *_Nullable (*_Nonnull)(void *_Nullable),
    void *_Nullable);

// Emit the 4 instructions (movz + 3×movk) that load a 64-bit value into x<reg>.
static int emit_load_imm64(uint32_t *code, uint32_t reg, uint64_t value) {
  code[0] = 0xD2800000u | ((uint32_t)(value & 0xFFFF) << 5) | reg;                   // movz
  code[1] = 0xF2800000u | (1u << 21) | ((uint32_t)((value >> 16) & 0xFFFF) << 5) | reg;  // movk 16
  code[2] = 0xF2800000u | (2u << 21) | ((uint32_t)((value >> 32) & 0xFFFF) << 5) | reg;  // movk 32
  code[3] = 0xF2800000u | (3u << 21) | ((uint32_t)((value >> 48) & 0xFFFF) << 5) | reg;  // movk 48
  return 4;
}

int uitool_inject(int pid, const char *dylib_path) {
  task_t task = MACH_PORT_NULL;
  if (task_for_pid(mach_task_self(), pid, &task) != KERN_SUCCESS) {
    return 1;  // task_for_pid denied — entitlement / permission
  }

  const mach_vm_size_t region_size = 0x2000;
  const uint64_t thunk_off = 0x200;
  const uint64_t path_off = 0x400;  // the dylib path string (read-only is fine)

  const size_t path_len = strlen(dylib_path) + 1;
  if (path_off + path_len > region_size) {
    mach_port_deallocate(mach_task_self(), task);
    return 3;
  }

  // Writable region: the bootstrap stack (grows down from the top) plus, at its
  // base, the pthread_t out-param _pthread_create writes through. This MUST be
  // writable — putting it in the execute-only code region faults _pthread_create.
  mach_vm_address_t stack = 0;
  const mach_vm_size_t stack_size = 0x80000;  // 512 KB
  if (mach_vm_allocate(task, &stack, stack_size, VM_FLAGS_ANYWHERE) != KERN_SUCCESS) {
    mach_port_deallocate(mach_task_self(), task);
    return 6;
  }
  const uint64_t pt_addr = stack;  // 8 bytes at the bottom; the stack grows down from the top
  const uint64_t sp = (stack + stack_size - 0x100) & ~0xFULL;

  // Execute-only code region: the mach blob, the thunk, and the path string.
  mach_vm_address_t base = 0;
  if (mach_vm_allocate(task, &base, region_size, VM_FLAGS_ANYWHERE) != KERN_SUCCESS) {
    mach_vm_deallocate(task, stack, stack_size);
    mach_port_deallocate(mach_task_self(), task);
    return 2;
  }

  uint8_t buffer[0x2000];
  memset(buffer, 0, sizeof(buffer));

  const uint64_t thunk_addr = base + thunk_off;
  const uint64_t path_addr = base + path_off;
  const uint64_t sym_off = 0x600;
  const uint64_t sym_addr = base + sym_off;
  static const char boot_symbol[] = "uitool_boot_start";

  // mach blob @ 0: pthread_create_from_mach_thread(&pt, NULL, thunk, path); spin.
  uint32_t *m = (uint32_t *)buffer;
  int i = 0;
  i += emit_load_imm64(m + i, 0, pt_addr);    // x0 = &pt
  m[i++] = 0xD2800001u;                        // movz x1, #0   (attr)
  i += emit_load_imm64(m + i, 2, thunk_addr);  // x2 = thunk
  i += emit_load_imm64(m + i, 3, path_addr);   // x3 = path (the thunk's arg)
  i += emit_load_imm64(m + i, 16, (uint64_t)&pthread_create_from_mach_thread);
  m[i++] = 0xD63F0200u;  // blr x16
  m[i++] = 0x14000000u;  // b .  (spin until the caller terminates this thread)

  // thunk @ thunk_off (the pthread start routine): dlopen the dylib, then dlsym +
  // call uitool_boot_start. The explicit call is what makes re-attach work — on an
  // already-resident dylib dlopen does NOT refire +load, so we start the server
  // directly. RTLD_DEFAULT (-2) finds the symbol regardless of the dlopen handle.
  uint32_t *t = (uint32_t *)(buffer + thunk_off);
  int j = 0;
  t[j++] = 0xA9BF7BFDu;                      // stp x29, x30, [sp, #-16]!
  t[j++] = 0xD2800041u;                      // movz x1, #2  (RTLD_NOW)
  j += emit_load_imm64(t + j, 16, (uint64_t)&dlopen);
  t[j++] = 0xD63F0200u;                      // blr x16   ; dlopen(path, RTLD_NOW)
  t[j++] = 0x92800020u;                      // movn x0, #1  -> x0 = RTLD_DEFAULT (-2)
  j += emit_load_imm64(t + j, 1, sym_addr);  // x1 = "uitool_boot_start"
  j += emit_load_imm64(t + j, 16, (uint64_t)&dlsym);
  t[j++] = 0xD63F0200u;                      // blr x16   ; dlsym(RTLD_DEFAULT, name) -> x0
  t[j++] = 0xD63F0000u;                      // blr x0    ; uitool_boot_start()
  t[j++] = 0xA8C17BFDu;                      // ldp x29, x30, [sp], #16
  t[j++] = 0xD65F03C0u;                      // ret

  memcpy(buffer + path_off, dylib_path, path_len);
  memcpy(buffer + sym_off, boot_symbol, sizeof(boot_symbol));

  if (mach_vm_write(task, base, (vm_offset_t)buffer, (mach_msg_type_number_t)region_size)
      != KERN_SUCCESS) {
    mach_port_deallocate(mach_task_self(), task);
    return 4;
  }
  if (mach_vm_protect(task, base, region_size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE)
      != KERN_SUCCESS) {
    mach_port_deallocate(mach_task_self(), task);
    return 5;
  }

  // arm64 (no PAC): set the entry pc and stack directly.
  arm_thread_state64_t state;
  memset(&state, 0, sizeof(state));
  state.__pc = base;
  state.__sp = sp;

  thread_act_t thread = MACH_PORT_NULL;
  if (thread_create_running(
          task, ARM_THREAD_STATE64, (thread_state_t)&state, ARM_THREAD_STATE64_COUNT, &thread)
      != KERN_SUCCESS) {
    mach_port_deallocate(mach_task_self(), task);
    return 7;
  }

  // The bootstrap mach thread spins after handing off to the real pthread; give it
  // a moment to create that pthread, then terminate it. The dlopen runs on the
  // pthread, independent of this bootstrap thread.
  usleep(200000);  // 200 ms
  thread_terminate(thread);
  mach_port_deallocate(mach_task_self(), thread);
  mach_port_deallocate(mach_task_self(), task);
  return 0;
}
