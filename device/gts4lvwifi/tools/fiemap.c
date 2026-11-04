/* fiemap <file>: print where a file sits on its block device, one extent per
 * line: "logical physical length flags" (bytes; flags in hex). The kernel is
 * asked to sync first, so delayed allocation is resolved.
 *
 * Exit 1 if an extent cannot be read back through dm-linear: unwritten,
 * delayed, encoded, encrypted, inline or unaligned. Run it on the tablet
 * (Android), as root, on the rootfs image in /data.
 */
#include <errno.h>
#include <fcntl.h>
#include <linux/fiemap.h>
#include <linux/fs.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define EXTENTS 128
#define UNUSABLE (FIEMAP_EXTENT_UNKNOWN | FIEMAP_EXTENT_DELALLOC | \
		  FIEMAP_EXTENT_ENCODED | FIEMAP_EXTENT_DATA_ENCRYPTED | \
		  FIEMAP_EXTENT_NOT_ALIGNED | FIEMAP_EXTENT_DATA_INLINE | \
		  FIEMAP_EXTENT_DATA_TAIL | FIEMAP_EXTENT_UNWRITTEN)

static int print_batch(const struct fiemap *fm, unsigned long long *next,
		       int *bad)
{
	unsigned int i;

	for (i = 0; i < fm->fm_mapped_extents; i++) {
		const struct fiemap_extent *e = &fm->fm_extents[i];

		printf("%llu %llu %llu %x\n",
		       (unsigned long long)e->fe_logical,
		       (unsigned long long)e->fe_physical,
		       (unsigned long long)e->fe_length, e->fe_flags);
		if (e->fe_flags & UNUSABLE)
			*bad = 1;
		*next = e->fe_logical + e->fe_length;
		if (e->fe_flags & FIEMAP_EXTENT_LAST)
			return 1;
	}
	return 0;
}

int main(int argc, char **argv)
{
	struct fiemap *fm;
	unsigned long long next = 0;
	int bad = 0;
	int last = 0;
	int fd;

	if (argc != 2) {
		fprintf(stderr, "usage: fiemap <file>\n");
		return 2;
	}
	fd = open(argv[1], O_RDONLY);
	if (fd < 0) {
		perror(argv[1]);
		return 1;
	}
	fm = calloc(1, sizeof(*fm) + EXTENTS * sizeof(struct fiemap_extent));
	if (!fm)
		return 1;
	while (!last) {
		memset(fm, 0, sizeof(*fm));
		fm->fm_start = next;
		fm->fm_length = ~0ULL;
		fm->fm_flags = FIEMAP_FLAG_SYNC;
		fm->fm_extent_count = EXTENTS;
		if (ioctl(fd, FS_IOC_FIEMAP, fm) < 0) {
			perror("FS_IOC_FIEMAP");
			return 1;
		}
		if (!fm->fm_mapped_extents)
			break;
		last = print_batch(fm, &next, &bad);
	}
	if (bad)
		fprintf(stderr, "fiemap: an extent is not plain written data\n");
	return bad;
}
