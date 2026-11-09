#include <lean/lean.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

/* Diagnostic boundary only. The borrowed immutable root remains alive for
   this synchronous call. Never follow refs, tasks, closures or external data.
   No allocator policy, global state, object mutation or pointer escapes. */
#define NODE_LIMIT ((size_t)262144)
#define TABLE_SIZE (NODE_LIMIT * 2)

typedef struct {
    lean_object **seen;
    lean_object **pending;
    size_t count, pending_count, bytes, duplicates, skipped;
    size_t constructors, arrays, scalar_arrays, strings, refs, closures;
    size_t scalar_bytes, string_bytes, array_bytes;
    int saturated;
} census;

static void push(census *c, lean_object *o) {
    if (lean_is_scalar(o)) return;
    if (c->pending_count == NODE_LIMIT) { c->saturated = 1; return; }
    c->pending[c->pending_count++] = o;
}

static int mark(census *c, lean_object *o) {
    uintptr_t value = (uintptr_t)o;
    size_t slot = (size_t)((value >> 3) * UINT64_C(11400714819323198485)) & (TABLE_SIZE - 1);
    while (c->seen[slot] && c->seen[slot] != o) slot = (slot + 1) & (TABLE_SIZE - 1);
    if (c->seen[slot]) { c->duplicates++; return 0; }
    if (c->count == NODE_LIMIT) { c->saturated = 1; return 0; }
    c->seen[slot] = o;
    c->count++;
    return 1;
}

LEAN_EXPORT lean_obj_res eggshell_research_object_census(b_lean_obj_arg root, lean_obj_arg world) {
    (void)world;
    census c = {0};
    c.seen = (lean_object **)calloc(TABLE_SIZE, sizeof(lean_object *));
    c.pending = (lean_object **)malloc(NODE_LIMIT * sizeof(lean_object *));
    if (!c.seen || !c.pending) {
        free(c.seen); free(c.pending);
        return lean_io_result_mk_ok(lean_mk_string("{\"allocationFailed\":true}"));
    }
    push(&c, root);
    while (c.pending_count && !c.saturated) {
        lean_object *o = c.pending[--c.pending_count];
        if (!mark(&c, o)) continue;
        unsigned tag = lean_ptr_tag(o);
        if (tag <= LeanMaxCtorTag) {
            c.constructors++;
            c.bytes += lean_object_byte_size(o);
            for (unsigned i = 0; i < lean_ctor_num_objs(o); i++) push(&c, lean_ctor_get(o, i));
        } else if (tag == LeanArray) {
            size_t bytes = lean_object_byte_size(o);
            c.arrays++; c.bytes += bytes; c.array_bytes += bytes;
            for (size_t i = 0; i < lean_array_size(o); i++) push(&c, lean_array_get_core(o, i));
        } else if (tag == LeanScalarArray) {
            size_t bytes = lean_object_byte_size(o);
            c.scalar_arrays++; c.bytes += bytes; c.scalar_bytes += bytes;
        } else if (tag == LeanString) {
            size_t bytes = lean_object_byte_size(o);
            c.strings++; c.bytes += bytes; c.string_bytes += bytes;
        } else {
            /* In particular, never race a foreign owner's mutable ref. */
            c.skipped++;
            if (tag == LeanRef) c.refs++;
            if (tag == LeanClosure) c.closures++;
        }
    }
    free(c.seen); free(c.pending);
    char result[1024];
    int length = snprintf(result, sizeof(result),
        "{\"objects\":%zu,\"bytes\":%zu,\"duplicates\":%zu,\"skipped\":%zu,"
        "\"constructors\":%zu,\"arrays\":%zu,\"scalarArrays\":%zu,\"strings\":%zu,"
        "\"skippedRefs\":%zu,\"skippedClosures\":%zu,\"scalarBytes\":%zu,"
        "\"stringBytes\":%zu,\"arrayBytes\":%zu,\"saturated\":%s,\"allocationFailed\":false}",
        c.count,c.bytes,c.duplicates,c.skipped,c.constructors,c.arrays,c.scalar_arrays,c.strings,
        c.refs,c.closures,c.scalar_bytes,c.string_bytes,c.array_bytes,c.saturated ? "true" : "false");
    if (length < 0 || (size_t)length >= sizeof(result))
        return lean_io_result_mk_ok(lean_mk_string("{\"allocationFailed\":true}"));
    return lean_io_result_mk_ok(lean_mk_string(result));
}
