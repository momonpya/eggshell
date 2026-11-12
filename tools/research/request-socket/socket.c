/* Nonblocking OS calls only. Framing, bounds, deadlines and cancellation are Lean. */
#include <lean/lean.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

typedef struct { int fd; } egg_socket;

static lean_obj_res egg_socket_error(int error) {
    return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string(strerror(error))));
}
static void egg_socket_finalize(void *pointer) {
    egg_socket *socket = pointer;
    if (socket->fd >= 0) close(socket->fd);
    free(socket);
}
static void egg_socket_foreach(void *pointer, b_lean_obj_arg visitor) {
    (void)pointer; (void)visitor;
}
/* Public lean.h describes this two-callback ABI. Static lifetime avoids a
   lazy registry, mutable initialization flag, once lock, or allocation per class. */
static lean_external_class egg_socket_class = {egg_socket_finalize, egg_socket_foreach};
LEAN_EXPORT lean_obj_res eggshell_socket_connect(uint16_t port, lean_obj_arg world) {
    (void)world;
    if (!port) return egg_socket_error(EINVAL);
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return egg_socket_error(errno);
    int flags = fcntl(fd, F_GETFL);
    int failure = 0, enabled = 1;
    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0 ||
        fcntl(fd, F_SETFD, FD_CLOEXEC) < 0) failure = errno;
    if (!failure && setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &enabled, sizeof(enabled)) < 0)
        failure = errno;
#ifdef SO_NOSIGPIPE
    if (!failure && setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, sizeof(enabled)) < 0)
        failure = errno;
#endif
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(port);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (!failure && connect(fd, (struct sockaddr *)&address, sizeof(address)) < 0 && errno != EINPROGRESS)
        failure = errno;
    if (failure) { close(fd); return egg_socket_error(failure); }
    egg_socket *owned = malloc(sizeof(*owned));
    if (!owned) { close(fd); return egg_socket_error(ENOMEM); }
    owned->fd = fd;
    return lean_io_result_mk_ok(lean_alloc_external(&egg_socket_class, owned));
}
LEAN_EXPORT lean_obj_res eggshell_socket_poll(b_lean_obj_arg object, uint8_t writing, lean_obj_arg world) {
    (void)world;
    egg_socket *socket = lean_get_external_data(object);
    if (socket->fd < 0) return egg_socket_error(EBADF);
    struct pollfd descriptor = {socket->fd, writing ? POLLOUT : POLLIN, 0};
    int result = poll(&descriptor, 1, 25);
    if (result < 0 && errno != EINTR) return egg_socket_error(errno);
    if (descriptor.revents & POLLNVAL) return egg_socket_error(EBADF);
    return lean_io_result_mk_ok(lean_box(result > 0));
}
LEAN_EXPORT lean_obj_res eggshell_socket_connected(b_lean_obj_arg object, lean_obj_arg world) {
    (void)world;
    egg_socket *socket = lean_get_external_data(object);
    if (socket->fd < 0) return egg_socket_error(EBADF);
    int failure = 0;
    socklen_t length = sizeof(failure);
    if (getsockopt(socket->fd, SOL_SOCKET, SO_ERROR, &failure, &length) < 0) return egg_socket_error(errno);
    if (failure) return egg_socket_error(failure);
    return lean_io_result_mk_ok(lean_box(0));
}
LEAN_EXPORT lean_obj_res eggshell_socket_send(b_lean_obj_arg object, b_lean_obj_arg bytes,
        size_t offset, lean_obj_arg world) {
    (void)world;
    egg_socket *socket = lean_get_external_data(object);
    size_t size = lean_sarray_size(bytes);
    if (socket->fd < 0) return egg_socket_error(EBADF);
    if (offset >= size) return egg_socket_error(EINVAL);
    size_t amount = size - offset;
    if (amount > 65536) amount = 65536;
    int flags = 0;
#ifdef MSG_NOSIGNAL
    flags |= MSG_NOSIGNAL;
#endif
    ssize_t sent = send(socket->fd, lean_sarray_cptr(bytes) + offset, amount, flags);
    if (sent < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR))
        return lean_io_result_mk_ok(lean_box_usize(0));
    if (sent < 0) return egg_socket_error(errno);
    if (!sent) return egg_socket_error(EPIPE);
    return lean_io_result_mk_ok(lean_box_usize((size_t)sent));
}
LEAN_EXPORT lean_obj_res eggshell_socket_receive(b_lean_obj_arg object, size_t amount, lean_obj_arg world) {
    (void)world;
    egg_socket *socket = lean_get_external_data(object);
    if (socket->fd < 0) return egg_socket_error(EBADF);
    if (!amount || amount > 65536) return egg_socket_error(EINVAL);
    lean_object *bytes = lean_alloc_sarray(1, 0, amount);
    ssize_t received = recv(socket->fd, lean_sarray_cptr(bytes), amount, 0);
    if (received < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)) {
        lean_dec(bytes);
        return lean_io_result_mk_ok(lean_alloc_sarray(1, 0, 0));
    }
    if (received <= 0) {
        int failure = received < 0 ? errno : ECONNRESET;
        lean_dec(bytes);
        return egg_socket_error(failure);
    }
    lean_sarray_set_size(bytes, (size_t)received);
    return lean_io_result_mk_ok(bytes);
}
LEAN_EXPORT lean_obj_res eggshell_socket_close(b_lean_obj_arg object, lean_obj_arg world) {
    (void)world;
    egg_socket *socket = lean_get_external_data(object);
    int fd = socket->fd;
    socket->fd = -1;
    if (fd >= 0) close(fd);
    return lean_io_result_mk_ok(lean_box(0));
}
