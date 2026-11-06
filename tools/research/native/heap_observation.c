/* Diagnostic boundary to the allocator shipped by the selected Lean runtime.
   No allocator policy, reclamation or application decision is implemented here. */
#include <lean/lean.h>
#include <lean/mimalloc.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <pthread.h>
#include <mach/mach.h>

typedef struct {
    size_t areas, reserved, committed, recorded, blocks, allocated;
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

LEAN_EXPORT lean_obj_res eggshell_research_heap_owner(void) {
    census sum = {0};
    /* Only inspect the calling thread's own heap. */
    bool complete = mi_heap_visit_blocks(mi_heap_get_default(), true, visit, &sum);
    /* In this pinned API an empty heap returns false before invoking any
       visitor. Our visitor can stop only after recording an area. */
    complete = complete || sum.areas == 0;
    const long purge_delay = mi_option_get(mi_option_purge_delay);
    const unsigned long purge_magnitude = purge_delay < 0
        ? (unsigned long)(-(purge_delay + 1)) + 1UL : (unsigned long)purge_delay;
    char text[768];
    int length = snprintf(text, sizeof(text),
        "version=%d\ncomplete=%u\nareas=%zu\nreservedBytes=%zu\n"
        "committedBytes=%zu\nrecordedBytes=%zu\nallocatedBlocks=%zu\nallocatedBytes=%zu\n"
        "purgeDisabled=%u\npurgeDelayMagnitudeMs=%lu\narenaPurgeMultiplier=%ld\n"
        "purgeDecommits=%u\narenaEagerCommitMode=%ld\n",
        mi_version(), complete ? 1u : 0u, sum.areas, sum.reserved,
        sum.committed, sum.recorded, sum.blocks, sum.allocated,
        purge_delay < 0 ? 1u : 0u, purge_magnitude,
        mi_option_get(mi_option_arena_purge_mult),
        mi_option_is_enabled(mi_option_purge_decommits) ? 1u : 0u,
        mi_option_get(mi_option_arena_eager_commit));
    if (length < 0 || (size_t)length >= sizeof(text))
        return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string("oversized owner heap observation")));
    return lean_io_result_mk_ok(lean_mk_string(text));
}

typedef struct { char bytes[16384]; size_t used; bool complete; } bounded_text;
/* Registration occurs once before service workers. Capture is thread local;
   concurrent allocator messages from other threads retain stderr behavior. */
static _Thread_local bounded_text *active_capture;
static void output(const char *message, void *unused) {
    (void)unused;
    if (!message) return;
    bounded_text *text = active_capture;
    if (!text) { fputs(message, stderr); return; }
    size_t count = strlen(message);
    size_t remaining = sizeof(text->bytes)-1-text->used;
    if (count > remaining) { count = remaining; text->complete = false; }
    memcpy(text->bytes+text->used, message, count);
    text->used += count;
    text->bytes[text->used] = 0;
}
LEAN_EXPORT lean_obj_res eggshell_research_heap_observe_init(void) {
    if (mi_version() != 223)
        return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string("allocator ABI changed")));
    mi_register_output(output, NULL);
    return lean_io_result_mk_ok(lean_box(0));
}
LEAN_EXPORT lean_obj_res eggshell_research_heap_arenas(void) {
    bounded_text text = {{0},0,true};
    active_capture = &text;
    mi_arenas_print();
    active_capture = NULL;
    if (!text.complete)
        return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string("arena diagnostic exceeded16384bytes")));
    return lean_io_result_mk_ok(lean_mk_string(text.bytes));
}
LEAN_EXPORT lean_obj_res eggshell_research_heap_thread_id(void) {
    uint64_t tid = 0;
    if (pthread_threadid_np(NULL, &tid) != 0 || tid == 0 || tid >= ((uint64_t)1 << 63))
        return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string("thread identity unavailable")));
    return lean_io_result_mk_ok(lean_usize_to_nat((size_t)tid));
}

LEAN_EXPORT lean_obj_res eggshell_research_heap_thread_alive(b_lean_obj_arg identity) {
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
