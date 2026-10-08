#define _GNU_SOURCE
/* OS filesystem/process boundary only; storage/protocol decisions remain in Lean. */
#include <lean/lean.h>
#include <errno.h>
#include <dirent.h>
#include <fcntl.h>
#include <inttypes.h>
#include <pthread.h>
#include <spawn.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <sys/sysctl.h>
#include <libproc.h>
#elif defined(__linux__)
#include <link.h>
#endif

typedef struct { int fd; } egg_read_handle;
static lean_external_class *egg_read_class;
static pthread_once_t egg_read_once = PTHREAD_ONCE_INIT;

static void egg_read_finalize(void *pointer) {
    egg_read_handle *handle = pointer;
    if (handle->fd >= 0) close(handle->fd);
    free(handle);
}
static void egg_read_foreach(void *pointer, b_lean_obj_arg visitor) {
    (void)pointer; (void)visitor;
}
static void egg_read_register(void) {
    egg_read_class = lean_register_external_class(egg_read_finalize, egg_read_foreach);
}
static lean_obj_res egg_read_error(int error) {
    return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string(strerror(error))));
}

/* Resolve every component relative to a held directory descriptor. A path
   check followed by ordinary open() would race with symlink replacement.
   NONBLOCK avoids hanging on a FIFO before its type can be rejected. */
static int egg_open_fd(b_lean_obj_arg path, int access, int directory, int *failure) {
    const char *text = lean_string_cstr(path);
    if (text[0] != '/' || strlen(text) + 1 != lean_string_size(path)) {
        *failure = EINVAL; return -1;
    }
    char *parts = strdup(text);
    if (!parts) { *failure = ENOMEM; return -1; }
    int fd = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    int error = fd < 0 ? errno : 0;
    char *cursor = NULL;
    char *part = strtok_r(parts, "/", &cursor);
    if (!part && !error) error = EISDIR;
    while (part && !error) {
        char *next = strtok_r(NULL, "/", &cursor);
        if (!strcmp(part, "..") || !strcmp(part, ".")) { error = EINVAL; break; }
        int flags = (next ? O_RDONLY : access) | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK;
        if (next) flags |= O_DIRECTORY;
        int child = openat(fd, part, flags);
        if (child < 0) { error = errno; break; }
        close(fd);
        fd = child;
        part = next;
    }
    free(parts);
    struct stat info;
    if (!error && fstat(fd, &info) < 0) error = errno;
    if (!error && (!(directory ? S_ISDIR(info.st_mode) : S_ISREG(info.st_mode)) || info.st_size < 0)) error = EINVAL;
    if (error) { if (fd >= 0) close(fd); *failure = error; return -1; }
    return fd;
}

static lean_obj_res egg_open_regular(b_lean_obj_arg path, int access) {
    int error = 0;
    int fd = egg_open_fd(path, access, 0, &error);
    if (fd < 0) return egg_read_error(error);
    egg_read_handle *handle = malloc(sizeof(*handle));
    if (!handle) { close(fd); return egg_read_error(ENOMEM); }
    handle->fd = fd;
    pthread_once(&egg_read_once, egg_read_register);
    return lean_io_result_mk_ok(lean_alloc_external(egg_read_class, handle));
}

LEAN_EXPORT lean_obj_res eggshell_read_open(b_lean_obj_arg path, lean_obj_arg world) {
    (void)world;
    return egg_open_regular(path, O_RDONLY);
}

LEAN_EXPORT lean_obj_res eggshell_read_try_lock(b_lean_obj_arg object, uint8_t exclusive,
        lean_obj_arg world) {
    (void)world;
    egg_read_handle *handle = lean_get_external_data(object);
    if (flock(handle->fd, (exclusive ? LOCK_EX : LOCK_SH) | LOCK_NB) == 0)
        return lean_io_result_mk_ok(lean_box(1));
    if (errno == EWOULDBLOCK || errno == EAGAIN) return lean_io_result_mk_ok(lean_box(0));
    return egg_read_error(errno);
}

LEAN_EXPORT lean_obj_res eggshell_read_unlock(b_lean_obj_arg object, lean_obj_arg world) {
    (void)world;
    egg_read_handle *handle = lean_get_external_data(object);
    if (flock(handle->fd, LOCK_UN) != 0) return egg_read_error(errno);
    return lean_io_result_mk_ok(lean_box(0));
}

static int egg_link_parent(b_lean_obj_arg path, char **name, int *failure) {
    const char *text = lean_string_cstr(path);
    if (text[0] != '/' || strlen(text) + 1 != lean_string_size(path)) {
        *failure = EINVAL; return -1;
    }
    char *parent = strdup(text);
    if (!parent) { *failure = ENOMEM; return -1; }
    char *last = strrchr(parent, '/');
    if (!last || !last[1] || !strcmp(last + 1, ".") || !strcmp(last + 1, "..")) {
        free(parent); *failure = EINVAL; return -1;
    }
    *name = strdup(last + 1);
    if (!*name) { free(parent); *failure = ENOMEM; return -1; }
    int fd;
    if (last == parent) {
        fd = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (fd < 0) *failure = errno;
    } else {
        *last = 0;
        lean_object *value = lean_mk_string(parent);
        fd = egg_open_fd(value, O_RDONLY | O_DIRECTORY, 1, failure);
        lean_dec(value);
    }
    free(parent);
    return fd;
}

/* A publication keeps the same securely resolved parent for creation,
   install, durability and cleanup. Rewalking the absolute path at every
   phase is both expensive and weaker against parent replacement races.
   Lean owns phase order and exact-byte agreement for an existing object. */
typedef struct {
    int parent, file, temporary_present, phase;
    char *target, *temporary, *path;
} egg_publication;
static lean_external_class *egg_publication_class;
static pthread_once_t egg_publication_once = PTHREAD_ONCE_INIT;

static int egg_publication_cleanup(egg_publication *handle) {
    int error = 0;
    if (handle->temporary_present && handle->parent >= 0 && handle->file >= 0) {
        struct stat owned, named;
        if (fstat(handle->file, &owned) < 0) error = errno;
        else if (fstatat(handle->parent, handle->temporary, &named, AT_SYMLINK_NOFOLLOW) < 0) {
            if (errno != ENOENT) error = errno;
        } else if (!S_ISREG(named.st_mode) || named.st_dev != owned.st_dev ||
                named.st_ino != owned.st_ino) error = EINVAL;
        else if (unlinkat(handle->parent, handle->temporary, 0) < 0) error = errno;
    }
    handle->temporary_present = 0;
    if (handle->file >= 0 && close(handle->file) < 0 && !error) error = errno;
    if (handle->parent >= 0 && close(handle->parent) < 0 && !error) error = errno;
    handle->file = handle->parent = -1;
    return error;
}
static void egg_publication_finalize(void *pointer) {
    egg_publication *handle = pointer;
    egg_publication_cleanup(handle);
    free(handle->target); free(handle->temporary); free(handle->path); free(handle);
}
static void egg_publication_foreach(void *pointer, b_lean_obj_arg visitor) {
    (void)pointer; (void)visitor;
}
static void egg_publication_register(void) {
    egg_publication_class = lean_register_external_class(
        egg_publication_finalize, egg_publication_foreach);
}
static int egg_publication_phase(egg_publication *handle, int phase) {
    if (handle->parent < 0 || handle->file < 0) return EBADF;
    return handle->phase == phase ? 0 : EINVAL;
}
static lean_obj_res egg_publication_error(egg_publication *handle, int error) {
    handle->phase = -1;
    return egg_read_error(error);
}
/* Existing final names must be regular files. NOFOLLOW also applies to
   the exclusive temporary create and every collision read below. */
static int egg_publication_target_regular(egg_publication *handle) {
    struct stat info;
    if (fstatat(handle->parent, handle->target, &info, AT_SYMLINK_NOFOLLOW) == 0)
        return S_ISREG(info.st_mode) ? 0 : EINVAL;
    return errno == ENOENT ? 0 : errno;
}

LEAN_EXPORT lean_obj_res eggshell_publication_open(b_lean_obj_arg path,
        b_lean_obj_arg temporary, lean_obj_arg world) {
    (void)world;
    const char *name = lean_string_cstr(temporary);
    if (strlen(name) + 1 != lean_string_size(temporary) || strchr(name, '/') ||
            (strncmp(name, ".egg-tmp-", 9) && strncmp(name, ".egg-object-", 12)))
        return egg_read_error(EINVAL);
    egg_publication *handle = calloc(1, sizeof(*handle));
    if (!handle) return egg_read_error(ENOMEM);
    handle->parent = handle->file = -1;
    int error = 0;
    handle->parent = egg_link_parent(path, &handle->target, &error);
    handle->temporary = strdup(name);
    if (!handle->temporary && !error) error = ENOMEM;
    handle->path = strdup(lean_string_cstr(path));
    if (!handle->path && !error) error = ENOMEM;
    if (!error) error = egg_publication_target_regular(handle);
    if (!error) {
        handle->file = openat(handle->parent, name,
            O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0600);
        if (handle->file < 0) error = errno;
        else handle->temporary_present = 1;
    }
    if (error) {
        egg_publication_finalize(handle);
        return egg_read_error(error);
    }
    pthread_once(&egg_publication_once, egg_publication_register);
    return lean_io_result_mk_ok(lean_alloc_external(egg_publication_class, handle));
}

LEAN_EXPORT lean_obj_res eggshell_publication_write(b_lean_obj_arg object,
        b_lean_obj_arg bytes, lean_obj_arg world) {
    (void)world;
    egg_publication *handle = lean_get_external_data(object);
    int error = egg_publication_phase(handle, 0);
    size_t size = lean_sarray_size(bytes), written = 0;
    if (!error && size > INT64_MAX) error = EINVAL;
    while (!error && written < size) {
        size_t count = size - written;
        if (count > 65536) count = 65536;
        ssize_t result = pwrite(handle->file, lean_sarray_cptr(bytes) + written,
            count, (off_t)written);
        if (result < 0) error = errno;
        else if (!result) error = EIO;
        else written += (size_t)result;
    }
    if (error) return egg_publication_error(handle, error);
    handle->phase = 1;
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res eggshell_publication_sync_data(b_lean_obj_arg object,
        lean_obj_arg world) {
    (void)world;
    egg_publication *handle = lean_get_external_data(object);
    int error = egg_publication_phase(handle, 1);
    if (!error && fsync(handle->file) < 0) error = errno;
    if (error) return egg_publication_error(handle, error);
    handle->phase = 2;
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res eggshell_publication_install(b_lean_obj_arg object,
        uint8_t immutable, lean_obj_arg world) {
    (void)world;
    egg_publication *handle = lean_get_external_data(object);
    int error = egg_publication_phase(handle, 2), created = 0;
    if (!error) error = egg_publication_target_regular(handle);
    if (!error && immutable) {
        if (linkat(handle->parent, handle->temporary, handle->parent, handle->target, 0) == 0)
            created = 1;
        else if (errno != EEXIST) error = errno;
    } else if (!error) {
        if (renameat(handle->parent, handle->temporary, handle->parent, handle->target) < 0)
            error = errno;
        else { created = 1; handle->temporary_present = 0; }
    }
    if (error) return egg_publication_error(handle, error);
    handle->phase = 3;
    return lean_io_result_mk_ok(lean_box(created));
}

LEAN_EXPORT lean_obj_res eggshell_publication_target(b_lean_obj_arg object,
        lean_obj_arg world) {
    (void)world;
    egg_publication *handle = lean_get_external_data(object);
    int error = egg_publication_phase(handle, 3), fd = -1;
    if (!error) {
        fd = openat(handle->parent, handle->target, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
        if (fd < 0) error = errno;
    }
    struct stat info;
    if (!error && fstat(fd, &info) < 0) error = errno;
    if (!error && (!S_ISREG(info.st_mode) || info.st_size < 0)) error = EINVAL;
    if (error) {
        if (fd >= 0) close(fd);
        return egg_publication_error(handle, error);
    }
    egg_read_handle *reader = malloc(sizeof(*reader));
    if (!reader) { close(fd); return egg_publication_error(handle, ENOMEM); }
    reader->fd = fd;
    pthread_once(&egg_read_once, egg_read_register);
    return lean_io_result_mk_ok(lean_alloc_external(egg_read_class, reader));
}

LEAN_EXPORT lean_obj_res eggshell_publication_sync_parent(b_lean_obj_arg object,
        lean_obj_arg world) {
    (void)world;
    egg_publication *handle = lean_get_external_data(object);
    int error = egg_publication_phase(handle, 3);
    /* A renamed/replaced authority directory is not an acknowledged write
       to the original route, even though all IO stayed safely in its held
       descriptor. Recheck the route once, immediately before acknowledgement. */
    if (!error) {
        char *name = NULL;
        lean_object *path = lean_mk_string(handle->path);
        int current = egg_link_parent(path, &name, &error);
        lean_dec(path);
        struct stat held, routed;
        if (!error && (fstat(handle->parent, &held) < 0 || fstat(current, &routed) < 0))
            error = errno;
        if (!error && (held.st_dev != routed.st_dev || held.st_ino != routed.st_ino))
            error = ESTALE;
        if (current >= 0) close(current);
        free(name);
    }
    if (!error && fsync(handle->parent) < 0) error = errno;
    if (error) return egg_publication_error(handle, error);
    handle->phase = 4;
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res eggshell_publication_close(b_lean_obj_arg object,
        lean_obj_arg world) {
    (void)world;
    egg_publication *handle = lean_get_external_data(object);
    int error = egg_publication_cleanup(handle);
    if (error) return egg_publication_error(handle, error);
    return lean_io_result_mk_ok(lean_box(0));
}

/* Publish an initialized private DB directory without ever exposing an
   incomplete head, following parent links, or replacing an existing target. */
LEAN_EXPORT lean_obj_res eggshell_publish_directory(b_lean_obj_arg source,
        b_lean_obj_arg target, lean_obj_arg world) {
    (void)world;
    int error = 0;
    char *source_name = NULL, *target_name = NULL;
    int source_parent = egg_link_parent(source, &source_name, &error);
    if (source_parent < 0) return egg_read_error(error);
    int target_parent = egg_link_parent(target, &target_name, &error);
    if (target_parent < 0) { free(source_name); close(source_parent); return egg_read_error(error); }
    struct stat info;
    if (fstatat(source_parent, source_name, &info, AT_SYMLINK_NOFOLLOW) < 0) error = errno;
    if (!error && !S_ISDIR(info.st_mode)) error = EINVAL;
#if defined(__APPLE__)
    if (!error && renameatx_np(source_parent, source_name, target_parent, target_name, RENAME_EXCL) < 0) error = errno;
#else
    if (!error) error = ENOTSUP;
#endif
    if (!error && fsync(target_parent) < 0) error = errno;
    if (!error && fsync(source_parent) < 0) error = errno;
    free(source_name); free(target_name); close(source_parent); close(target_parent);
    return error ? egg_read_error(error) : lean_io_result_mk_ok(lean_box(0));
}

/* No stdio write buffer can survive a failed append or outlive the writer
   guard. Lean owns page layout, offsets, rollovers and publication order. */
LEAN_EXPORT lean_obj_res eggshell_append_open(b_lean_obj_arg path, lean_obj_arg world) {
    (void)world;
    return egg_open_regular(path, O_WRONLY);
}

LEAN_EXPORT lean_obj_res eggshell_append_write(b_lean_obj_arg object, uint64_t offset,
        b_lean_obj_arg bytes, lean_obj_arg world) {
    (void)world;
    size_t size = lean_sarray_size(bytes);
    if (offset > INT64_MAX || size > 65536 || size > (uint64_t)INT64_MAX - offset)
        return egg_read_error(EINVAL);
    egg_read_handle *handle = lean_get_external_data(object);
    struct stat info;
    if (handle->fd < 0) return egg_read_error(EBADF);
    if (fstat(handle->fd, &info) < 0) return egg_read_error(errno);
    if (!S_ISREG(info.st_mode) || info.st_size < 0 || (uint64_t)info.st_size != offset)
        return egg_read_error(EINVAL);
    size_t written = 0;
    while (written < size) {
        ssize_t result = pwrite(handle->fd, lean_sarray_cptr(bytes) + written,
            size - written, (off_t)(offset + written));
        /* Report EINTR, partial IO failure and ENOSPC without a retry loop.
           A positive partial write strictly decreases the remaining bytes. */
        if (result < 0) return egg_read_error(errno);
        if (result == 0) return egg_read_error(EIO);
        written += (size_t)result;
    }
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res eggshell_append_sync(b_lean_obj_arg object, lean_obj_arg world) {
    (void)world;
    egg_read_handle *handle = lean_get_external_data(object);
    if (handle->fd < 0) return egg_read_error(EBADF);
    if (fsync(handle->fd) < 0) return egg_read_error(errno);
    return lean_io_result_mk_ok(lean_box(0));
}

/* Only the chat's exclusive writer invokes this, after reading its durable
   manifest. Lean supplies the committed boundary; C checks the observed EOF
   and forbids extending a file. A failure is not acknowledged as recovery. */
LEAN_EXPORT lean_obj_res eggshell_append_truncate(b_lean_obj_arg object,
        uint64_t expected_end, uint64_t retained_end, lean_obj_arg world) {
    (void)world;
    if (expected_end > INT64_MAX || retained_end > expected_end)
        return egg_read_error(EINVAL);
    egg_read_handle *handle = lean_get_external_data(object);
    struct stat info;
    if (handle->fd < 0) return egg_read_error(EBADF);
    if (fstat(handle->fd, &info) < 0) return egg_read_error(errno);
    if (!S_ISREG(info.st_mode) || info.st_size < 0 || (uint64_t)info.st_size != expected_end)
        return egg_read_error(EINVAL);
    if (ftruncate(handle->fd, (off_t)retained_end) < 0) return egg_read_error(errno);
    if (fsync(handle->fd) < 0) return egg_read_error(errno);
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res eggshell_append_close(b_lean_obj_arg object, lean_obj_arg world) {
    (void)world;
    egg_read_handle *handle = lean_get_external_data(object);
    int fd = handle->fd;
    handle->fd = -1;
    if (fd >= 0 && close(fd) < 0) return egg_read_error(errno);
    return lean_io_result_mk_ok(lean_box(0));
}

LEAN_EXPORT lean_obj_res eggshell_read_version(b_lean_obj_arg object, lean_obj_arg world) {
    (void)world;
    egg_read_handle *handle = lean_get_external_data(object);
    struct stat info;
    if (fstat(handle->fd, &info) < 0) return egg_read_error(errno);
    if (!S_ISREG(info.st_mode) || info.st_size < 0) return egg_read_error(EINVAL);
#ifdef __APPLE__
    struct timespec modified = info.st_mtimespec, changed = info.st_ctimespec;
#else
    struct timespec modified = info.st_mtim, changed = info.st_ctim;
#endif
    char stamp[256];
    int count = snprintf(stamp, sizeof(stamp), "%ju:%ju:%jd:%jd:%ld:%jd:%ld",
        (uintmax_t)info.st_dev, (uintmax_t)info.st_ino, (intmax_t)info.st_size,
        (intmax_t)modified.tv_sec, modified.tv_nsec, (intmax_t)changed.tv_sec, changed.tv_nsec);
    if (count < 0 || (size_t)count >= sizeof(stamp)) return egg_read_error(EOVERFLOW);
    lean_object *version = lean_alloc_ctor(0, 2, 0);
    lean_ctor_set(version, 0, lean_mk_string(stamp));
    lean_ctor_set(version, 1, lean_uint64_to_nat((uint64_t)info.st_size));
    return lean_io_result_mk_ok(version);
}

LEAN_EXPORT lean_obj_res eggshell_read_page(b_lean_obj_arg object, uint64_t offset,
        size_t count, lean_obj_arg world) {
    (void)world;
    if (offset > INT64_MAX || count > 4096) return egg_read_error(EINVAL);
    egg_read_handle *handle = lean_get_external_data(object);
    lean_object *bytes = lean_alloc_sarray(1, count, count);
    ssize_t length = pread(handle->fd, lean_sarray_cptr(bytes), count, (off_t)offset);
    /* EINTR is reported; Lean may decline validation rather than retry beyond
       its budget. No unbounded retry loop lives at this boundary. */
    if (length < 0) { int error = errno; lean_dec(bytes); return egg_read_error(error); }
    lean_sarray_set_size(bytes, (size_t)length);
    return lean_io_result_mk_ok(bytes);
}

LEAN_EXPORT lean_obj_res eggshell_sync_path(b_lean_obj_arg path, uint8_t directory,
                                           lean_obj_arg world) {
    (void)world;
    int flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC;
    if (directory) flags |= O_DIRECTORY;
    int fd = open(lean_string_cstr(path), flags);
    int error = fd < 0 ? errno : 0;
    if (fd >= 0) {
        int result;
        do { result = fsync(fd); } while (result < 0 && errno == EINTR);
        if (result < 0) error = errno;
        if (close(fd) < 0 && !error) error = errno;
    }
    if (error) return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string(strerror(error))));
    return lean_io_result_mk_ok(lean_box(0));
}
