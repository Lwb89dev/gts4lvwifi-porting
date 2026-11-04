/* dmlinear <name> <blockdev> <extents>: create the device-mapper device <name>
 * that concatenates byte ranges of <blockdev>, so a file inside a filesystem
 * that is never mounted can be used as a block device (here: the rootfs image
 * inside Android's userdata).
 *
 * <extents> has one line per extent, "logical physical length flags" (bytes),
 * as device/gts4lvwifi/tools/fiemap.c prints them. They must start at 0, follow
 * each other with no hole, and be multiples of 512. Prints "major:minor".
 * Needs /dev/mapper/control, so dm-mod must be loaded.
 */
#include <errno.h>
#include <fcntl.h>
#include <linux/dm-ioctl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/sysmacros.h>
#include <unistd.h>

#define BUF (4 << 20)
#define ALIGN8(n) (((n) + 7) & ~7UL)

static void header(struct dm_ioctl *io, size_t size, const char *name,
		   unsigned int flags)
{
	memset(io, 0, sizeof(*io));
	io->version[0] = DM_VERSION_MAJOR;
	io->version[1] = DM_VERSION_MINOR;
	io->version[2] = DM_VERSION_PATCHLEVEL;
	io->data_size = size;
	io->data_start = sizeof(*io);
	io->flags = flags;
	strncpy(io->name, name, sizeof(io->name) - 1);
}

/* Appends the "linear" targets at io->data; returns the end offset or 0. */
static size_t add_targets(struct dm_ioctl *io, const char *dev, FILE *list)
{
	unsigned long long logical, physical, length;
	unsigned int flags;
	unsigned long long expect = 0;
	size_t off = sizeof(*io);

	while (fscanf(list, "%llu %llu %llu %x", &logical, &physical, &length,
		      &flags) == 4) {
		struct dm_target_spec *spec = (void *)((char *)io + off);
		char *params = (char *)(spec + 1);
		size_t plen;

		if (logical != expect || (physical | length | logical) % 512) {
			fprintf(stderr, "dmlinear: hole or unaligned extent at %llu\n",
				logical);
			return 0;
		}
		/* room for the longest parameter string before it is written */
		if (off + sizeof(*spec) + 256 + 8 > BUF)
			return 0;
		plen = snprintf(params, 256, "%s %llu", dev, physical / 512) + 1;
		spec->sector_start = logical / 512;
		spec->length = length / 512;
		strcpy(spec->target_type, "linear");
		spec->next = sizeof(*spec) + ALIGN8(plen);
		off += spec->next;
		expect += length;
		io->target_count++;
	}
	return io->target_count ? off : 0;
}

static int ioctl_or_die(int fd, unsigned long cmd, struct dm_ioctl *io,
			const char *what)
{
	if (ioctl(fd, cmd, io) < 0) {
		fprintf(stderr, "dmlinear: %s: %s\n", what, strerror(errno));
		return -1;
	}
	return 0;
}

int main(int argc, char **argv)
{
	struct dm_ioctl *io;
	size_t end;
	FILE *list;
	int fd;

	if (argc != 4) {
		fprintf(stderr, "usage: dmlinear <name> <blockdev> <extents>\n");
		return 2;
	}
	list = fopen(argv[3], "r");
	io = calloc(1, BUF);
	fd = open("/dev/mapper/control", O_RDWR);
	if (!list || !io || fd < 0) {
		fprintf(stderr, "dmlinear: cannot open the extents or /dev/mapper/control\n");
		return 1;
	}

	header(io, BUF, argv[1], 0);
	if (ioctl_or_die(fd, DM_DEV_CREATE, io, "DM_DEV_CREATE"))
		return 1;

	header(io, BUF, argv[1], 0);
	end = add_targets(io, argv[2], list);
	if (!end) {
		fprintf(stderr, "dmlinear: no usable extents in %s\n", argv[3]);
		return 1;
	}
	io->data_size = end;
	if (ioctl_or_die(fd, DM_TABLE_LOAD, io, "DM_TABLE_LOAD"))
		return 1;

	header(io, sizeof(*io), argv[1], 0);
	if (ioctl_or_die(fd, DM_DEV_SUSPEND, io, "DM_DEV_SUSPEND (resume)"))
		return 1;
	printf("%u:%u\n", major(io->dev), minor(io->dev));
	return 0;
}
