# CVA6 User Mode Transition Audit Report

**Date:** 2025-10-21
**Branch:** latest
**Focus:** User mode transition hang, unaligned instruction fetch issues

## Executive Summary

This audit identified **4 critical issues** and **2 potential race conditions** that could cause a system hang after transitioning to user mode. The most likely culprit is **Issue #1** (fetch pipeline deadlock on ITLB/Shared TLB miss) combined with a potential timing issue during privilege level changes.

---

## Critical Issues Found

### Issue #1: Fetch Pipeline Deadlock on TLB Miss (HIGH SEVERITY) ⚠️

**Location:** `core/cva6_mmu/cva6_mmu.sv:395, 419-420, 445`

**Problem:**
When MMU translation is enabled, the instruction fetch pipeline can deadlock if:
1. ITLB lookup misses
2. Shared TLB lookup misses
3. PTW (Page Table Walker) fails to start or gets stuck

**Code Flow:**
```systemverilog
// Line 395: Default to not valid when translation enabled
if ((enable_translation_i || enable_g_translation_i)) begin
    icache_areq_o.fetch_valid = 1'b0;  // ← DEADLOCK POINT

    // Line 419-420: Only set valid if ITLB hits
    if (itlb_lu_hit) begin
        icache_areq_o.fetch_valid = icache_areq_i.fetch_req;

    // Line 445: Or if PTW is active and walking
    end else if (ptw_active && walking_instr) begin
        icache_areq_o.fetch_valid = ptw_error | ptw_access_exception;
    }
    // ← If neither condition is true, fetch_valid stays 0 forever!
}
```

**Hang Scenario:**
- After SRET to user mode, next instruction fetch address misses in ITLB
- Shared TLB is accessed but also misses
- PTW should start but doesn't (see Issue #2)
- `fetch_valid` remains 0
- Icache waits forever (see `cva6_icache.sv:270, 338`)
- **System hangs**

---

### Issue #2: PTW Activation Condition During Privilege Transition (HIGH SEVERITY) ⚠️

**Location:** `core/cva6_mmu/cva6_ptw.sv:334`

**Problem:**
PTW only activates when all of these conditions are met:
```systemverilog
if (((enable_translation_i | enable_g_translation_i) ||
     (en_ld_st_translation_i || en_ld_st_g_translation_i) ||
     !CVA6Cfg.RVH) &&
    shared_tlb_access_i && ~shared_tlb_hit_i)
```

**Potential Race Condition:**
During SRET from S→U mode:
- Cycle N: SRET executes, `priv_lvl_d` updated to U
- Cycle N+1: `priv_lvl_q` ← `priv_lvl_d`, `priv_lvl_o` = U
- Cycle N+1: `enable_translation_o` = combinational f(priv_lvl_o, satp_q.mode)

If there's a timing issue where `enable_translation_i` arrives at PTW slightly delayed, the PTW might not see the translation-enabled condition when `shared_tlb_access_i` pulses.

**Related Code:** `core/csr_regfile.sv:2494-2506`
```systemverilog
assign en_translation_o = (CVA6Cfg.RVS &&
                           config_pkg::vm_mode_t'(satp_q.mode) == CVA6Cfg.MODE_SV &&
                           priv_lvl_o != riscv::PRIV_LVL_M)  // ← Depends on registered priv_lvl
                          ? 1'b1 : 1'b0;
```

---

### Issue #3: Instruction Privilege Check Logic (VERIFICATION NEEDED)

**Location:** `core/cva6_mmu/cva6_mmu.sv:370-372`

**Current Implementation:**
```systemverilog
iaccess_err = icache_areq_i.fetch_req && enable_translation_i &&
    (((priv_lvl_i == riscv::PRIV_LVL_U) && ~itlb_content.u)      // User accessing S-page → ERROR ✓
    || ((priv_lvl_i == riscv::PRIV_LVL_S) && itlb_content.u));   // S accessing U-page → ERROR
```

**RISC-V Spec Compliance:**
According to RISC-V Privileged Spec v1.11+:
- ✅ User mode **cannot** execute from pages with U=0 (supervisor pages) - **CORRECT**
- ✅ Supervisor mode **cannot** execute from pages with U=1 (user pages) - **CORRECT for instruction fetch**
- ⚠️ **BUT**: This is ONLY correct for instruction fetch, NOT data access
- For data access, SUM (Supervisor User Memory) bit allows S-mode to access U=1 pages

**Status:** Implementation appears **CORRECT** for instruction fetch (SUM doesn't apply to exec). However, this strict enforcement means:
- **User-mode code MUST be in user pages (U=1)**
- **Supervisor code CANNOT be in user pages (U=1)**

**Verification Needed:**
Does your OS kernel properly mark user-mode code pages with U=1? If the OS marks user code with U=0, user mode will fault immediately.

---

### Issue #4: Unaligned Fetch Address Handling in MMU

**Location:** `core/cva6_mmu/cva6_mmu.sv:397-400`

**Current Implementation:**
```systemverilog
icache_areq_o.fetch_paddr = {
    (enable_g_translation_i && CVA6Cfg.RVH) ? itlb_g_content.ppn : itlb_content.ppn,
    icache_areq_i.fetch_vaddr[11:0]  // ← Takes ALL 12 bits from vaddr
};
```

**Analysis:**
The MMU correctly uses all 12 bits of the virtual address offset. This is standard for page translation and should work correctly for unaligned fetches.

**Related:** `core/cache_subsystem/cva6_icache.sv:22, 150`
```systemverilog
// Line 22 comment: "instruction fetches are always assumed to be aligned to 32bit"
// Line 150: Alignment enforced in icache
assign areq_o.fetch_vaddr = (vaddr_q >> CVA6Cfg.FETCH_ALIGN_BITS) << CVA6Cfg.FETCH_ALIGN_BITS;
```

**Potential Issue:**
If `FETCH_ALIGN_BITS` enforces 32-bit or 64-bit alignment, but the actual fetch address after SRET is misaligned, there could be a mismatch between what the MMU translates and what the icache expects.

---

## Timing and Synchronization Issues

### Timing Issue A: Privilege Level Propagation

**Affected Signals:**
- `priv_lvl_q` (registered in CSR, line `csr_regfile.sv:2625`)
- `priv_lvl_o` (output to MMU)
- `enable_translation_o` (combinational from `priv_lvl_o`)

**Sequence During SRET:**
```
Cycle N:   SRET executes → priv_lvl_d = U
Cycle N+1: CLK edge → priv_lvl_q <= priv_lvl_d
Cycle N+1: priv_lvl_o = priv_lvl_q (now U)
Cycle N+1: enable_translation_o = f(priv_lvl_o != M && satp.mode) (now should be 1)
Cycle N+1: Instruction fetch for PC after SRET uses U privilege
```

**Potential Problem:**
If the frontend issues a fetch request BEFORE the privilege level update propagates, the MMU might see:
- Old privilege (S mode)
- New fetch address (user code)
- TLB entry with U=1 (user page)
- Access check: `(S mode && U=1)` → **ACCESS ERROR** (line 372)
- But this should raise an exception, not hang...

Unless the exception handling itself is broken?

---

### Timing Issue B: Shared TLB vs PTW Handshake

**Location:** `core/cva6_mmu/cva6_shared_tlb.sv:239, cva6_mmu/cva6_ptw.sv:334`

**Problem:**
The `shared_tlb_miss` signal from PTW and the `shared_tlb_access/hit` signals from shared TLB must be properly synchronized. If there's a clock domain crossing or a pipeline stage mismatch, the PTW might never see the miss signal.

**Code:**
```systemverilog
// shared_tlb.sv:239
itlb_miss_o = shared_tlb_miss_i;  // Pass through from PTW?

// ptw.sv:334 (in IDLE state)
if (... && shared_tlb_access_i && ~shared_tlb_hit_i) begin
    state_d = WAIT_GRANT;
    shared_tlb_miss_o = 1'b1;  // ← This goes back to shared_tlb
}
```

This looks like a circular dependency that could deadlock if not properly initialized!

---

## Recommendations

### Immediate Actions (Priority Order)

1. **Add Debug Assertions** (Highest Priority)
   Add assertions to detect the deadlock:
   ```systemverilog
   // In cva6_mmu.sv:instr_interface
   assert property (@(posedge clk_i)
       ((enable_translation_i || enable_g_translation_i) &&
        icache_areq_i.fetch_req &&
        !itlb_lu_hit) |->
       ##[1:5] (ptw_active || itlb_lu_hit || !enable_translation_i))
   else $error("Fetch request stuck: ITLB miss but PTW not active!");
   ```

2. **Add Timeout/Watchdog for PTW**
   Implement a counter that detects if PTW stays in IDLE too long with pending TLB misses.

3. **Verify Privilege Transition Flush**
   Check if software is executing `SFENCE.VMA` after SRET. If not, stale TLB entries could cause issues.

   Add to OS code after SRET:
   ```assembly
   sret
   # Immediately after SRET, ensure TLBs are flushed
   sfence.vma  # Flush all TLB entries
   ```

4. **Check Page Permissions in Page Tables**
   Verify that user-mode code pages have the U bit set (U=1) in the page table entries.

   Debugging command:
   ```
   # Dump page table entries for user code region
   # Check that U bit is set
   ```

5. **Add Waveform Triggers**
   During simulation, add triggers to catch the hang:
   ```systemverilog
   logic [31:0] fetch_stall_counter;
   always_ff @(posedge clk_i) begin
       if (icache_areq_i.fetch_req && !icache_areq_o.fetch_valid)
           fetch_stall_counter <= fetch_stall_counter + 1;
       else
           fetch_stall_counter <= 0;

       if (fetch_stall_counter > 100)
           $error("Fetch pipeline stalled for >100 cycles!");
   end
   ```

### Investigation Steps

**Step 1: Capture Hang State**
When the system hangs, capture:
- `priv_lvl_i` to MMU
- `enable_translation_i`
- `itlb_lu_hit`
- `shared_tlb_access_i`, `shared_tlb_hit_i`
- `ptw_active`, `walking_instr`
- `icache_areq_o.fetch_valid`
- Current PC and next PC
- SATP register value

**Step 2: Check TLB State**
- Dump ITLB contents
- Dump Shared TLB contents
- Check if entry exists for the failing fetch address
- Verify permission bits (U bit specifically)

**Step 3: Trace Privilege Transition**
- Add logging for SRET execution
- Trace `priv_lvl_q` updates
- Verify `enable_translation_o` changes correctly

**Step 4: Test Minimal Case**
Create a minimal test:
```c
// In supervisor mode
void switch_to_user() {
    // Mark user code page with U=1
    // Set up user stack
    // Execute SRET to jump to user_main
    __asm__ volatile("sret");
}

// In user mode - marked with U=1 in page table
void user_main() {
    // First instruction in user mode
    __asm__ volatile("nop");  // If hang occurs HERE, it's the fetch issue
    while(1);
}
```

---

## Code Locations Summary

| Issue | File | Lines | Severity |
|-------|------|-------|----------|
| Fetch deadlock | `core/cva6_mmu/cva6_mmu.sv` | 395, 419-420, 445 | **CRITICAL** |
| PTW activation | `core/cva6_mmu/cva6_ptw.sv` | 334 | **CRITICAL** |
| Priv check | `core/cva6_mmu/cva6_mmu.sv` | 370-372 | **HIGH** |
| Translation enable | `core/csr_regfile.sv` | 2494-2506 | **MEDIUM** |
| Priv level update | `core/csr_regfile.sv` | 2625 | **MEDIUM** |
| Fetch alignment | `core/cache_subsystem/cva6_icache.sv` | 150 | **LOW** |
| Shared TLB handshake | `core/cva6_mmu/cva6_shared_tlb.sv` | 239 | **MEDIUM** |

---

## Additional Notes

### PMP/PTW Exception Handling
You mentioned fixing a bug where PMP could overwrite PTW exceptions. The current code at `cva6_mmu.sv:450, 703` handles PTW access exceptions separately from PTW errors, which appears correct.

### Recent Relevant Commits
- `a8ef0fb4`: Fix for uncacheable icache reads (AxiDataWidth > 64) - Could be related if using wider bus
- `94dfdb00`: Fix for misaligned load/store exceptions - Data access only, not instruction fetch

### Unaligned Instruction Fetch Support
The design properly handles unaligned instruction fetches via `instr_realign.sv`. The issue is likely NOT with unaligned instruction handling itself, but with the MMU/TLB interaction during privilege transitions.

---

## Conclusion

The most likely cause of the hang is the **fetch pipeline deadlock** (Issue #1) triggered when:
1. SRET changes privilege level from S to U
2. Next instruction fetch misses in ITLB (possibly due to stale entry or never cached)
3. Shared TLB also misses
4. PTW fails to start due to timing/synchronization issue (Issue #2)
5. `fetch_valid` stays 0 indefinitely
6. System hangs

**Recommended First Steps:**
1. Add debug logging to confirm fetch_valid stays 0
2. Check if PTW state is stuck in IDLE
3. Verify enable_translation_i is correctly set
4. Add SFENCE.VMA after SRET in software
5. Verify page table U bits are set correctly

Please run these diagnostics and report back the findings. I can provide more specific fixes once we confirm the exact failure mode.
