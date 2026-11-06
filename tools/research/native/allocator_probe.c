/* Diagnostic adapter to the allocator already linked into Lean. No new allocator. */
#include <lean/lean.h>
#include <lean/mimalloc.h>
#include <stdio.h>
#include <string.h>

typedef struct {
    size_t areas, reserved, committed, used, blocks;
} owner_areas;

static bool visit_area(const mi_heap_t *heap, const mi_heap_area_t *area,
                       void *block, size_t block_size, void *arg) {
    (void)heap; (void)block; (void)block_size;
    owner_areas *sum = (owner_areas *)arg;
    sum->areas++;
    sum->reserved += area->reserved;
    sum->committed += area->committed;
    sum->used += area->used * area->block_size;
    sum->blocks += area->used;
    return true;
}

typedef struct { char bytes[32768]; size_t used; bool truncated; } bounded_text;
static void append_stats(const char *message, void *arg) {
    bounded_text *text = (bounded_text *)arg;
    if (message == NULL) return;
    size_t count = strlen(message);
    size_t room = sizeof(text->bytes) - 1 - text->used;
    if (count > room) { count = room; text->truncated = true; }
    memcpy(text->bytes + text->used, message, count);
    text->used += count;
    text->bytes[text->used] = '\0';
}

LEAN_EXPORT lean_obj_res eggshell_research_allocator_snapshot(uint8_t detailed) {
    owner_areas areas = {0};
    /* Only visit the calling thread's own heap. Never walk another live heap. */
    bool visited = mi_heap_visit_blocks(mi_heap_get_default(), false, visit_area, &areas);
    mi_stats_merge();
    size_t elapsed, user, system, rss, peak_rss, committed, peak_committed, faults;
    mi_process_info(&elapsed, &user, &system, &rss, &peak_rss,
                    &committed, &peak_committed, &faults);
    bounded_text text = {{0}, 0, false};
    int count = snprintf(text.bytes, sizeof(text.bytes),
        "version=%d\nvisited=%u\nownerAreas=%zu\nownerReservedBytes=%zu\n"
        "ownerCommittedBytes=%zu\nownerUsedBytes=%zu\nownerUsedBlocks=%zu\n"
        "allocatorReportedRssBytes=%zu\nallocatorReportedPeakRssBytes=%zu\n"
        "committedBytes=%zu\npeakCommittedBytes=%zu\n--\n",
        mi_version(), visited ? 1u : 0u, areas.areas, areas.reserved,
        areas.committed, areas.used, areas.blocks, rss, peak_rss,
        committed, peak_committed);
    if (count < 0 || (size_t)count >= sizeof(text.bytes)) text.truncated = true;
    else text.used = (size_t)count;
    /* Call detailed global printing only at a coordinator's quiescent barrier. */
    if (detailed && !text.truncated) mi_stats_print_out(append_stats, &text);
    if (text.truncated) return lean_io_result_mk_error(
        lean_mk_io_user_error(lean_mk_string("allocator diagnostic exceeded32768 bytes")));
    return lean_io_result_mk_ok(lean_mk_string(text.bytes));
}

LEAN_EXPORT lean_obj_res eggshell_research_allocator_collect(uint8_t force) {
    mi_collect(force != 0);
    return lean_io_result_mk_ok(lean_box(0));
}

/* Owner-only observer: no global counter merge, global print or collection.
   The earlier fixture found unusable global committed counters. Keep those
   raw fixture results, but do not reuse that counter as service evidence. */
LEAN_EXPORT lean_obj_res eggshell_research_allocator_owner(void) {
    owner_areas areas = {0};
    bool visited = mi_heap_visit_blocks(mi_heap_get_default(), false, visit_area, &areas);
    char text[512];
    int count = snprintf(text, sizeof(text),
        "version=%d\nvisited=%u\nownerAreas=%zu\nownerReservedBytes=%zu\n"
        "ownerCommittedBytes=%zu\nownerUsedBytes=%zu\nownerUsedBlocks=%zu\n",
        mi_version(), visited ? 1u : 0u, areas.areas, areas.reserved,
        areas.committed, areas.used, areas.blocks);
    if (count < 0 || (size_t)count >= sizeof(text)) return lean_io_result_mk_error(
        lean_mk_io_user_error(lean_mk_string("owner heap diagnostic exceeded512 bytes")));
    return lean_io_result_mk_ok(lean_mk_string(text));
}
