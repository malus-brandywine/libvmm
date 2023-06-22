/*
 * Copyright 2020, Data61, CSIRO (ABN 41 687 119 230)
 * Copyright 2022, UNSW (ABN 57 195 873 179)
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include <stdbool.h>
#include "psci.h"
#include "smc.h"
#include "fault.h"
#include "util/util.h"
#include "vmm.h"

bool secondary_vcpus_on[GUEST_NUM_VCPUS - 1];

bool handle_psci(uint64_t vcpu_id, seL4_UserContext *regs, uint64_t fn_number, uint32_t hsr)
{
    // @ivanv: write a note about what convention we assume, should we be checking
    // the convention?
    switch (fn_number) {
        case PSCI_VERSION: {
            /* We support PSCI version 1.2 */
            uint32_t version = PSCI_MAJOR_VERSION(1) | PSCI_MINOR_VERSION(2);
            smc_set_return_value(regs, version);
            break;
        }
        case PSCI_CPU_ON: {
            uintptr_t target_vcpu = smc_get_arg(regs, 1);
            // Right now we only have one vCPU and so any fault for a target vCPU
            // that isn't the one that's already on we consider an error on the
            // guest's side.
            // @ivanv: adapt for starting other vCPUs
            if (target_vcpu < GUEST_NUM_VCPUS && target_vcpu >= 0) {
                /* The guest has given a valid target vCPU */
                if (secondary_vcpus_on[target_vcpu]) {
                    smc_set_return_value(regs, PSCI_ALREADY_ON);
                } else {
                    /* We have a valid target vCPU, that is not started yet. So let's turn it on. */
                    uintptr_t vcpu_entry_point = smc_get_arg(regs, 2);
                    // @SMP: double check the this type is correct
                    size_t context_id = smc_get_arg(regs, 3);

                    // @SMP: explain
                    seL4_UserContext regs = {0};
                    regs.x0 = context_id;
                    regs.spsr = 5; // PMODE_EL1h
                    regs.pc = vcpu_entry_point;

                    seL4_Error err = seL4_TCB_WriteRegisters(
                        BASE_VM_TCB_CAP + target_vcpu,
                        false, // We'll explcitly start the guest below rather than in this call
                        0, // No flags
                        SEL4_USER_CONTEXT_SIZE,
                        &regs
                    );
                    assert(err == seL4_NoError);
                    if (err != seL4_NoError) {
                        return err;
                    }

                    /* Now that we have started the vCPU, we can set is as turned on. */
                    secondary_vcpus_on[target_vcpu] = true;

                    LOG_VMM("starting guest vCPU (0x%lx) with entry point 0x%lx, context ID: 0x%lx\n", target_vcpu, regs.pc, context_id);
                    sel4cp_vm_restart(target_vcpu, regs.pc);
                }
            } else {
                // The guest has requested to turn on a virtual CPU that does
                // not exist.
                smc_set_return_value(regs, PSCI_INVALID_PARAMETERS);
            }
            break;
        }
        case PSCI_MIGRATE_INFO_TYPE:
            /*
             * There are multiple possible return values for MIGRATE_INFO_TYPE.
             * In this case returning 2 will tell the guest that this is a
             * system that does not use a "Trusted OS" as the PSCI
             * specification says.
             */
            smc_set_return_value(regs, 2);
            break;
        case PSCI_FEATURES:
            // @ivanv: seems weird that we just return nothing here.
            smc_set_return_value(regs, PSCI_NOT_SUPPORTED);
            break;
        case PSCI_SYSTEM_RESET: {
            bool success = guest_restart();
            if (!success) {
                LOG_VMM_ERR("Failed to restart guest\n");
                smc_set_return_value(regs, PSCI_INTERNAL_FAILURE);
            } else {
                /*
                 * If we've successfully restarted the guest, all we want to do
                 * is reply to the fault that caused us to handle the PSCI call
                 * so that the guest can continue executing. We do not need to
                 * advance the vCPU program counter as we typically do when
                 * handling a fault since the correct PC has been set when we
                 * call guest_restart().
                 */
                return true;
            }
            break;
        }
        case PSCI_SYSTEM_OFF:
            guest_stop();
            return true;
        default:
            LOG_VMM_ERR("Unhandled PSCI function ID 0x%lx\n", fn_number);
            return false;
    }

    bool success = fault_advance_vcpu(regs, vcpu_id);
    assert(success);

    return success;
}
