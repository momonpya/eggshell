"""Hold verified cache directories for one complete numerical request."""
from context_candidate import once

TARGETS = '''
lean_lib DirectoryReadResearch where
  roots := #[`tools.DirectoryReads]

lean_exe directory_read_tests where
  root := `tools.DirectoryReadTests
'''
HELPERS = ['DirectoryReads.lean', 'DirectoryReadTests.lean']

NATIVE = '''LEAN_EXPORT lean_obj_res eggshell_read_directory_open(b_lean_obj_arg path, lean_obj_arg world) {
    (void)world;
    const char *text = lean_string_cstr(path);
    if (lean_string_size(path) == 2 && text[0] == '/' && text[1] == 0) {
        int root = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        return root < 0 ? egg_read_error(errno) : egg_read_adopt(root);
    }
    int error = 0;
    int fd = egg_open_fd(path, O_RDONLY | O_DIRECTORY, 1, &error);
    if (fd < 0) return egg_read_error(error);
    return egg_read_adopt(fd);
}

LEAN_EXPORT lean_obj_res eggshell_read_open_at(b_lean_obj_arg directory, b_lean_obj_arg name,
        lean_obj_arg world) {
    (void)world;
    const char *leaf = lean_string_cstr(name);
    if (!leaf[0] || strlen(leaf) + 1 != lean_string_size(name) || strchr(leaf, '/') ||
            !strcmp(leaf, ".") || !strcmp(leaf, "..")) return egg_read_error(EINVAL);
    egg_read_handle *parent = lean_get_external_data(directory);
    int fd = openat(parent->fd, leaf, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
    if (fd < 0) return egg_read_error(errno);
    struct stat info;
    int error = fstat(fd, &info) < 0 ? errno : 0;
    if (!error && (!S_ISREG(info.st_mode) || info.st_size < 0)) error = EINVAL;
    if (error) { close(fd); return egg_read_error(error); }
    return egg_read_adopt(fd);
}

'''


def native(source):
    start = source.index('static lean_obj_res egg_open_regular(')
    allocation = source.index('    egg_read_handle *handle = malloc', start)
    end = source.index('\n}\n', allocation) + len('\n}\n')
    original = source[start:allocation]
    adopter = 'static lean_obj_res egg_read_adopt(int fd) {\n' + source[allocation:end]
    source = source[:start] + adopter + '\n' + original + '    return egg_read_adopt(fd);\n}\n' + source[end:]
    return once(source, 'LEAN_EXPORT lean_obj_res eggshell_read_try_lock',
        NATIVE + 'LEAN_EXPORT lean_obj_res eggshell_read_try_lock')


def filesystem(source):
    source = once(source, '@[extern "eggshell_read_version"] opaque readVersion', '''/-- A directory reached without following any symbolic-link ancestor. Its
native descriptor is owned until this request-local object is released. -/
opaque ReadDirectory : Type
@[extern "eggshell_read_directory_open"] opaque openReadDirectory (path : @& String) : IO ReadDirectory
@[extern "eggshell_read_open_at"] opaque openReadAt (directory : @& ReadDirectory)
    (name : @& String) : IO ReadHandle

@[extern "eggshell_read_version"] opaque readVersion''')
    lo = source.index('def boundedBytes (')
    hi = source.index('/-- Atomic create-if-absent:', lo)
    reader = source[lo:hi]
    reader = once(reader, 'def boundedBytes (path : System.FilePath) (limit : Nat)',
        'def boundedRead (handle : ReadHandle) (limit : Nat)')
    reader = once(reader, '  let handle ← openRead path.toString\n', '')
    reader += '''theorem bounded_read_original (path : System.FilePath) (limit : Nat) :
    boundedBytes path limit = (do boundedRead (← openRead path.toString) limit) := by
  rfl

'''
    return source[:hi] + reader + source[hi:]


def provider(source):
    source = once(source, 'public import Eggshell.Receipt\n',
        'public import Eggshell.Receipt\npublic import tools.DirectoryReads\n')
    source = once(source, '  metrics : Option MetricsSink := none\n',
        '  metrics : Option MetricsSink := none\n  directories : Option DirectoryReads := none\n')
    lo = source.index('def loadVector (')
    hi = source.index('def readCachedVector (', lo)
    decoder = source[lo:hi]
    decoder = once(decoder, 'def loadVector (path : System.FilePath)',
        'def decodeVectorBytes (bytes : ByteArray)')
    decoder = once(decoder, '  let bytes ← FileSystem.boundedBytes path 1048576\n', '')
    decoder += '''theorem load_vector_original (path : System.FilePath) :
    loadVector path = (do decodeVectorBytes (← FileSystem.boundedBytes path 1048576)) := by
  rfl

def loadIndexedVector (options : Options) (path : System.FilePath) : IO CachedVector := do
  let bytes ← match options.directories with
    | none => FileSystem.boundedBytes path 1048576
    | some reads => FileSystem.boundedRead (← reads.open path) 1048576
  decodeVectorBytes bytes

'''
    source = source[:hi] + decoder + source[hi:]
    lo = source.index('def indexedWindow (')
    hi = source.index('def indexedVectors (', lo)
    indexed = once(source[lo:hi], '      let cached ← loadVector path',
        '      let cached ← loadIndexedVector options path')
    source = source[:lo] + indexed + source[hi:]
    source = once(source, '    FileSystem.atomicBytes path encoded.toUTF8\n',
        '''    FileSystem.atomicBytes path encoded.toUTF8
  if let some reads := options.directories then reads.invalidate path
''')
    return once(source, '  let candidates ← IO.ofExcept (request.getObjValAs? (Array Json) "documents")\n',
        '''  let options := {options with directories := some (← DirectoryReads.new)}
  let candidates ← IO.ofExcept (request.getObjValAs? (Array Json) "documents")
''')


def audit(source):
    source = once(source, '  for theoremName in #[', '''  for theoremName in #[``Eggshell.FileSystem.bounded_read_original,
      ``Eggshell.SearchProvider.load_vector_original,''')
    return source + '''
example (path : System.FilePath) (limit : Nat) :
    Eggshell.FileSystem.boundedBytes path limit =
      (do Eggshell.FileSystem.boundedRead (← Eggshell.FileSystem.openRead path.toString) limit) :=
  Eggshell.FileSystem.bounded_read_original path limit

run_meta do
  let environment ← getEnv
  for (caller, required) in #[
      (``Eggshell.SearchProvider.loadIndexedVector, ``Eggshell.FileSystem.boundedRead),
      (``Eggshell.SearchProvider.loadIndexedVector, ``Eggshell.SearchProvider.decodeVectorBytes),
      (``Eggshell.SearchProvider.indexedWindow, ``Eggshell.SearchProvider.loadIndexedVector),
      (``Eggshell.SearchProvider.handleIndexedUsing, ``Eggshell.DirectoryReads.new),
      (``Eggshell.SearchProvider.saveVector, ``Eggshell.DirectoryReads.invalidate),
      (``Eggshell.DirectoryReads.open, ``Eggshell.FileSystem.openReadAt)] do
    let some declaration := environment.find? caller | throwError "Missing directory read caller: {caller}"
    let some body := declaration.value? | throwError "Directory read caller has no body: {caller}"
    unless body.getUsedConstants.contains required do
      throwError "Directory reads bypass the secure bounded decoder: {caller}, {required}"
'''


SOURCES = {
    'Eggshell/Storage/sync.c': native,
    'Eggshell/FileSystem.lean': filesystem,
    'Eggshell/SearchProvider.lean': provider,
    'Eggshell/ContractAudit.lean': audit,
}
