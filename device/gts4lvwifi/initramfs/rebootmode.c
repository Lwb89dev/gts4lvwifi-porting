/* rebootmode <command>: reboot(2) with LINUX_REBOOT_CMD_RESTART2 and a command
 * string, which busybox reboot cannot pass. The qcom-pon reboot-mode driver
 * maps the string ("android", "recovery", "download") to the PMIC restart
 * reason. Run it only after qcom-pon is loaded; without it nothing is written.
 */
#include <linux/reboot.h>
#include <stdio.h>
#include <sys/syscall.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	if (argc != 2) {
		fprintf(stderr, "usage: rebootmode android|recovery|download\n");
		return 2;
	}
	sync();
	syscall(SYS_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
		LINUX_REBOOT_CMD_RESTART2, argv[1]);
	perror("reboot");
	return 1;
}
