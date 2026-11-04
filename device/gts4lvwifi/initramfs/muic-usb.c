/* Route the SM5705 MUIC to USB: MANSW1 = 0x24.
 * Same transfer as: i2cset -y <bus> 0x25 0x13 0x24
 * The bus number is the only argument. This does not touch eMMC.
 */
#include <fcntl.h>
#include <linux/i2c-dev.h>
#include <linux/i2c.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define MUIC_ADDR 0x25
#define MANSW1 0x13
#define MANSW1_USB 0x24

static int claim(int fd)
{
	if (ioctl(fd, I2C_SLAVE, MUIC_ADDR) == 0)
		return 0;
	return ioctl(fd, I2C_SLAVE_FORCE, MUIC_ADDR);
}

int main(int argc, char **argv)
{
	int fd;
	int bus;
	union i2c_smbus_data data;
	struct i2c_smbus_ioctl_data xfer;
	char path[32];

	if (argc != 2)
		return 2;
	bus = atoi(argv[1]);
	if (snprintf(path, sizeof path, "/dev/i2c-%d", bus) >= (int)sizeof path)
		return 2;
	fd = open(path, O_RDWR);
	if (fd < 0)
		return 1;
	if (claim(fd) < 0)
		return 1;
	data.byte = MANSW1_USB;
	xfer.read_write = I2C_SMBUS_WRITE;
	xfer.command = MANSW1;
	xfer.size = I2C_SMBUS_BYTE_DATA;
	xfer.data = &data;
	if (ioctl(fd, I2C_SMBUS, &xfer) < 0)
		return 1;
	close(fd);
	return 0;
}
