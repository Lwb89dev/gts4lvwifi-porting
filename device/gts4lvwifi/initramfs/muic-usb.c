/* Route the SM5705 MUIC to USB, or report whether charger VBUS is present.
 * Same transfer as: i2cset -y <bus> 0x25 0x13 0x24
 * Usage: muic-usb <bus> [--vbus]
 * --vbus exits 0 when VBUS is present, 1 when absent, and 2 on an error.
 * This does not touch eMMC.
 */
#include <fcntl.h>
#include <linux/i2c-dev.h>
#include <linux/i2c.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define MUIC_ADDR 0x25
#define MANSW1 0x13
#define MANSW1_USB 0x24
#define CHARGER_ADDR 0x49
#define CHG_REG_STATUS1 0x08
#define CHG_STATUS1_VBUSPOK 0x01

int main(int argc, char **argv)
{
	int fd;
	int bus;
	int vbus = 0;
	union i2c_smbus_data data;
	struct i2c_smbus_ioctl_data xfer;
	char path[32];

	if (argc != 2 && argc != 3)
		return 2;
	if (argc == 3) {
		if (strcmp(argv[2], "--vbus") != 0)
			return 2;
		vbus = 1;
	}
	bus = atoi(argv[1]);
	if (snprintf(path, sizeof path, "/dev/i2c-%d", bus) >= (int)sizeof path)
		return 2;
	fd = open(path, O_RDWR);
	if (fd < 0)
		return vbus ? 2 : 1;
	if (ioctl(fd, I2C_SLAVE, vbus ? CHARGER_ADDR : MUIC_ADDR) < 0 &&
	    ioctl(fd, I2C_SLAVE_FORCE, vbus ? CHARGER_ADDR : MUIC_ADDR) < 0)
		return vbus ? 2 : 1;
	if (vbus) {
		xfer.read_write = I2C_SMBUS_READ;
		xfer.command = CHG_REG_STATUS1;
		xfer.size = I2C_SMBUS_BYTE_DATA;
		xfer.data = &data;
		if (ioctl(fd, I2C_SMBUS, &xfer) < 0)
			return 2;
		close(fd);
		return (data.byte & CHG_STATUS1_VBUSPOK) ? 0 : 1;
	}
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
