#include <lean/lean.h>
#include <lean/mimalloc.h>
#include <pthread.h>

/* Diagnostic intervention only. The Lean caller selects sham versus collect;
   this uses the allocator already linked by the selected Lean runtime. */
LEAN_EXPORT lean_obj_res eggshell_research_reclaim(uint8_t collect) {
    if (mi_version() != 223)
        return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string("allocator ABI changed")));
    const bool os_main = pthread_main_np() != 0;
    if (collect) mi_collect(true);
    return lean_io_result_mk_ok(lean_box(os_main));
}
