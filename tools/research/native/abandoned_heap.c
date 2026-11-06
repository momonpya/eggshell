/* Diagnostic boundary to the allocator shipped by the selected Lean runtime.
   No allocator policy, reclamation or application decision is implemented here. */
#include <lean/lean.h>
#include <lean/mimalloc.h>
#include <stdint.h>
#include <stdio.h>
#include <pthread.h>
#include <mach/mach.h>

typedef struct {
    size_t areas, reserved, committed, recorded, blocks, allocated;
    bool census;
} census;

static bool visit(const mi_heap_t *heap, const mi_heap_area_t *area,
                  void *block, size_t size, void *argument) {
    (void)heap;
    census *sum = argument;
    if (block == NULL) {
        sum->areas++;
        sum->reserved += area->reserved;
        sum->committed += area->committed;
        sum->recorded += area->used * area->block_size;
    } else {
        sum->blocks++;
        sum->allocated += size;
    }
    /* A bounded diagnostic, never an unbounded walk of application objects. */
    return sum->areas <= 32768 && sum->blocks <= 4000000;
}

LEAN_EXPORT lean_obj_res eggshell_research_abandoned_enable(void) {
    if (mi_version() != 223)
        return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string("allocator ABI changed")));
    mi_option_enable(mi_option_visit_abandoned);
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res eggshell_research_abandoned_snapshot(uint8_t blocks) {
    census sum = {0};
    sum.census = blocks != 0;
    bool complete = mi_abandoned_visit_blocks(mi_subproc_main(), -1, sum.census, visit, &sum);
    char text[768];
    int length = snprintf(text, sizeof(text),
        "version=%d\nenabled=%u\ncomplete=%u\ncensus=%u\nareas=%zu\nreservedBytes=%zu\n"
        "committedBytes=%zu\nrecordedBytes=%zu\nallocatedBlocks=%zu\nallocatedBytes=%zu\n",
        mi_version(), mi_option_is_enabled(mi_option_visit_abandoned) ? 1u : 0u,
        complete ? 1u : 0u, sum.census ? 1u : 0u, sum.areas, sum.reserved,
        sum.committed, sum.recorded, sum.blocks, sum.allocated);
    if (length < 0 || (size_t)length >= sizeof(text))
        return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string("oversized abandoned heap observation")));
    return lean_io_result_mk_ok(lean_mk_string(text));
}

LEAN_EXPORT lean_obj_res eggshell_research_abandoned_thread_id(void) {
    uint64_t tid = 0;
    if (pthread_threadid_np(NULL, &tid) != 0 || tid == 0 || tid >= ((uint64_t)1 << 63))
        return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string("thread identity unavailable")));
    return lean_io_result_mk_ok(lean_usize_to_nat((size_t)tid));
}

LEAN_EXPORT lean_obj_res eggshell_research_abandoned_thread_alive(b_lean_obj_arg identity) {
    thread_act_array_t threads = NULL;
    mach_msg_type_number_t count = 0;
    if (task_threads(mach_task_self(), &threads, &count) != KERN_SUCCESS)
        return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string("thread inventory unavailable")));
    bool alive = false, valid = true;
    size_t wanted = lean_usize_of_nat(identity);
    for (mach_msg_type_number_t i = 0; i < count; ++i) {
        thread_identifier_info_data_t info;
        mach_msg_type_number_t size = THREAD_IDENTIFIER_INFO_COUNT;
        if (thread_info(threads[i], THREAD_IDENTIFIER_INFO, (thread_info_t)&info, &size) != KERN_SUCCESS) valid = false;
        else if (info.thread_id == wanted) alive = true;
        mach_port_deallocate(mach_task_self(), threads[i]);
    }
    if (vm_deallocate(mach_task_self(), (vm_address_t)threads, count * sizeof(thread_t)) != KERN_SUCCESS) valid = false;
    if (!valid) return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string("transient thread inventory")));
    return lean_io_result_mk_ok(lean_box(alive));
}
