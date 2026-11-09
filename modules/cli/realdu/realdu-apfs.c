/*
 * realdu-apfs DIR
 *
 * Prints one line per entry of DIR: name, allocated bytes (what du counts),
 * and private bytes, the blocks no APFS clone shares (ATTR_CMNEXT_PRIVATESIZE).
 * A hard-linked file counts once, under the first entry the walk reaches it
 * from. The walk stays on DIR's volume, like du -x.
 */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/attr.h>
#include <sys/vnode.h>
#include <unistd.h>

typedef struct {
  char *name;
  uint64_t alloc, priv;
} entry_t;

static entry_t *entries;
static size_t n_entries, cap_entries;
static uint64_t unreadable;
static dev_t root_dev;

static uint64_t *seen;
static size_t seen_cap = 1 << 16, seen_n;

static int first_sight(uint64_t id) {
  if ((seen_n + 1) * 2 > seen_cap) {
    size_t old_cap = seen_cap;
    uint64_t *old = seen;
    seen_cap *= 2;
    seen = calloc(seen_cap, sizeof *seen);
    seen_n = 0;
    for (size_t i = 0; i < old_cap; i++)
      if (old[i])
        first_sight(old[i]);
    free(old);
  }
  size_t mask = seen_cap - 1;
  size_t h = (size_t)((id * 0x9E3779B97F4A7C15ull) >> 17) & mask;
  while (seen[h]) {
    if (seen[h] == id)
      return 0;
    h = (h + 1) & mask;
  }
  seen[h] = id;
  seen_n++;
  return 1;
}

static void scan(int dfd, long owner) {
  struct attrlist al;
  memset(&al, 0, sizeof al);
  al.bitmapcount = ATTR_BIT_MAP_COUNT;
  al.commonattr = ATTR_CMN_RETURNED_ATTRS | ATTR_CMN_NAME | ATTR_CMN_DEVID |
                  ATTR_CMN_OBJTYPE | ATTR_CMN_FILEID | ATTR_CMN_ERROR;
  al.fileattr = ATTR_FILE_LINKCOUNT | ATTR_FILE_ALLOCSIZE;
  al.forkattr = ATTR_CMNEXT_PRIVATESIZE;

  size_t size = 128 * 1024;
  char *buf = malloc(size);
  for (;;) {
    int n = getattrlistbulk(dfd, &al, buf, size, FSOPT_ATTR_CMN_EXTENDED);
    if (n < 0)
      unreadable++;
    if (n <= 0)
      break;

    char *rec = buf;
    for (int i = 0; i < n; i++) {
      /*
       * Only the attributes named in the returned set are packed, in bit
       * order, except ATTR_CMN_ERROR, which comes right after the set. A
       * directory carries no file attributes. Fields may sit on 4-byte
       * boundaries, hence memcpy.
       */
      uint32_t len;
      memcpy(&len, rec, sizeof len);
      char *f = rec + sizeof len;
      rec += len;

      attribute_set_t got;
      memcpy(&got, f, sizeof got);
      f += sizeof got;

      uint32_t err = 0;
      if (got.commonattr & ATTR_CMN_ERROR) {
        memcpy(&err, f, sizeof err);
        f += sizeof err;
      }
      char *name = "";
      if (got.commonattr & ATTR_CMN_NAME) {
        attrreference_t ref;
        memcpy(&ref, f, sizeof ref);
        name = f + ref.attr_dataoffset;
        f += sizeof ref;
      }
      dev_t dev = root_dev;
      if (got.commonattr & ATTR_CMN_DEVID) {
        memcpy(&dev, f, sizeof dev);
        f += sizeof dev;
      }
      fsobj_type_t type = VNON;
      if (got.commonattr & ATTR_CMN_OBJTYPE) {
        memcpy(&type, f, sizeof type);
        f += sizeof type;
      }
      uint64_t fileid = 0;
      if (got.commonattr & ATTR_CMN_FILEID) {
        memcpy(&fileid, f, sizeof fileid);
        f += sizeof fileid;
      }
      uint32_t links = 1;
      if (got.fileattr & ATTR_FILE_LINKCOUNT) {
        memcpy(&links, f, sizeof links);
        f += sizeof links;
      }
      off_t alloc = 0;
      if (got.fileattr & ATTR_FILE_ALLOCSIZE) {
        memcpy(&alloc, f, sizeof alloc);
        f += sizeof alloc;
      }
      off_t priv = alloc;
      if (got.forkattr & ATTR_CMNEXT_PRIVATESIZE)
        memcpy(&priv, f, sizeof priv);

      long e = owner;
      if (owner < 0) {
        if (n_entries == cap_entries) {
          cap_entries = cap_entries ? cap_entries * 2 : 256;
          entries = realloc(entries, cap_entries * sizeof *entries);
        }
        entries[n_entries] = (entry_t){.name = strdup(name)};
        e = (long)n_entries++;
      }

      if (err) {
        unreadable++;
      } else if (type == VDIR && dev == root_dev) {
        int fd = openat(dfd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
        if (fd < 0) {
          unreadable++;
        } else {
          scan(fd, e);
          close(fd);
        }
      } else if (type == VREG && (links < 2 || first_sight(fileid))) {
        entries[e].alloc += (uint64_t)alloc;
        entries[e].priv += (uint64_t)priv;
      }
    }
  }
  free(buf);
}

int main(int argc, char **argv) {
  if (argc != 2) {
    fputs("usage: realdu-apfs DIR\n", stderr);
    return 64;
  }
  int fd = open(argv[1], O_RDONLY | O_DIRECTORY);
  if (fd < 0) {
    perror(argv[1]);
    return 66;
  }

  struct attrlist al;
  memset(&al, 0, sizeof al);
  al.bitmapcount = ATTR_BIT_MAP_COUNT;
  al.commonattr = ATTR_CMN_DEVID;
  struct {
    uint32_t len;
    dev_t dev;
  } __attribute__((packed)) root;
  if (fgetattrlist(fd, &al, &root, sizeof root, 0) != 0) {
    perror(argv[1]);
    return 66;
  }
  root_dev = root.dev;

  seen = calloc(seen_cap, sizeof *seen);
  scan(fd, -1);
  for (size_t i = 0; i < n_entries; i++)
    printf("%s\t%llu\t%llu\n", entries[i].name,
           (unsigned long long)entries[i].alloc,
           (unsigned long long)entries[i].priv);
  if (unreadable)
    fprintf(stderr, "realdu: skipped %llu unreadable directories\n",
            (unsigned long long)unreadable);
  return 0;
}
