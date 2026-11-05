// SPDX-License-Identifier: GPL-2.0-only
/*
 * STMicroelectronics FTS1BA90A touchscreen, as found in the Samsung Galaxy
 * Tab S5e (SM-T720).
 *
 * The protocol is not the one of the mainline stmfts driver (FTS5CU56A): the
 * commands, the event ids and the event layout differ. The facts used here
 * (command bytes, the 8 byte event layout, the reset and start sequence) were
 * read from Samsung's GPL-2.0 driver in android_kernel_samsung_sdm670,
 * drivers/input/touchscreen/stm/fts1ba90a, and checked against the chip on a
 * running tablet: the device id read answers "ST" 0x39 0x36 and the event FIFO
 * returns 8 byte events. The code is new; the skeleton follows stmfts.c.
 *
 * What it does: reset the controller, wait for its ready event, check the id,
 * switch touch scanning on, and report up to ten fingers as multitouch slots
 * on the panel's native axes (x 0..1599, y 0..2559). Orientation and
 * calibration are left to the compositor. No firmware update, no gestures, no
 * low power mode: nothing here writes the chip's flash.
 */

#include <linux/delay.h>
#include <linux/i2c.h>
#include <linux/input.h>
#include <linux/input/mt.h>
#include <linux/input/touchscreen.h>
#include <linux/interrupt.h>
#include <linux/module.h>
#include <linux/mod_devicetable.h>
#include <linux/of.h>
#include <linux/regulator/consumer.h>
#include <linux/string.h>

#define FTS_ID0				0x39
#define FTS_ID1				0x36

#define FTS_EVENT_SIZE			8
#define FTS_FIFO_MAX			32
#define FTS_FINGER_MAX			10

/* commands: written as one register byte, optionally followed by arguments */
#define FTS_CMD_SENSE_OFF		0x11
#define FTS_READ_DEVICE_ID		0x22
#define FTS_CMD_SET_TOUCHTYPE		0x30
#define FTS_READ_ONE_EVENT		0x60
#define FTS_READ_ALL_EVENT		0x61
#define FTS_CMD_CLEAR_ALL_EVENT		0x62
#define FTS_CMD_SCANMODE		0xa0

#define FTS_SCAN_MODE_MS_SS		BIT(0)

/* touch types the chip is asked to report: finger, palm, wet finger */
#define FTS_TOUCHTYPE_TOUCH		BIT(0)
#define FTS_TOUCHTYPE_PALM		BIT(5)
#define FTS_TOUCHTYPE_WET		BIT(6)

/* event id: the low two bits of the first byte */
#define FTS_EID_COORDINATE		0
#define FTS_EID_STATUS			1

/* action of a coordinate event: the top two bits of the first byte */
#define FTS_ACTION_PRESS		1
#define FTS_ACTION_MOVE			2
#define FTS_ACTION_RELEASE		3

/* touch types in a coordinate event */
#define FTS_TTYPE_NORMAL		0
#define FTS_TTYPE_GLOVE			3
#define FTS_TTYPE_PALM			5
#define FTS_TTYPE_WET			6

/* status events: type in bits 2..5 of byte 0, id in byte 1 */
#define FTS_STYPE_ERROR			1
#define FTS_STYPE_INFORMATION		2
#define FTS_INFO_READY			0x00
#define FTS_ERR_QUEUE_FULL		0x01

#define FTS_READY_TRIES			10

#define FTS_MAX_X			1599
#define FTS_MAX_Y			2559

/*
 * Without an interrupt in the device tree (a client made by hand through
 * new_device, which is how the driver is first tried) the FIFO is polled.
 */
static bool debug;
module_param(debug, bool, 0644);
MODULE_PARM_DESC(debug, "log every event that is not all zeros (bring-up aid)");

static unsigned int poll_ms = 10;
module_param(poll_ms, uint, 0444);
MODULE_PARM_DESC(poll_ms, "FIFO polling period in ms when the device has no interrupt (default 10, 0 = never read)");

struct fts_ts {
	struct i2c_client *client;
	struct input_dev *input;
	struct touchscreen_properties prop;
	struct regulator_bulk_data supplies[2];
	struct delayed_work poll;
};

static const char * const fts_supply_names[] = { "vdd", "avdd" };

/* write <cmd>, then read <len> bytes with a repeated start */
static int fts_read(struct fts_ts *ts, const u8 *cmd, int cmd_len, u8 *buf, int len)
{
	struct i2c_msg msgs[2] = {
		{ .addr = ts->client->addr, .flags = 0, .len = cmd_len, .buf = (u8 *)cmd },
		{ .addr = ts->client->addr, .flags = I2C_M_RD, .len = len, .buf = buf },
	};
	int ret = i2c_transfer(ts->client->adapter, msgs, 2);

	if (ret < 0)
		return ret;
	return ret == 2 ? 0 : -EIO;
}

static int fts_write(struct fts_ts *ts, const u8 *cmd, int len)
{
	int ret = i2c_master_send(ts->client, cmd, len);

	if (ret < 0)
		return ret;
	return ret == len ? 0 : -EIO;
}

static int fts_command(struct fts_ts *ts, u8 cmd)
{
	return fts_write(ts, &cmd, 1);
}

static void fts_release_all(struct fts_ts *ts)
{
	int i;

	for (i = 0; i < FTS_FINGER_MAX; i++) {
		input_mt_slot(ts->input, i);
		input_mt_report_slot_inactive(ts->input);
	}
	input_sync(ts->input);
}

static bool fts_ttype_reported(u8 ttype)
{
	/* hover and the other kinds are not reported */
	return ttype == FTS_TTYPE_NORMAL || ttype == FTS_TTYPE_GLOVE ||
	       ttype == FTS_TTYPE_PALM || ttype == FTS_TTYPE_WET;
}

static void fts_report_coordinate(struct fts_ts *ts, const u8 *ev)
{
	u8 tid = (ev[0] >> 2) & 0x0f;
	u8 action = ev[0] >> 6;
	u8 ttype = ((ev[6] >> 6) << 2) | (ev[7] >> 6);
	int x = (ev[1] << 4) | (ev[3] >> 4);
	int y = (ev[2] << 4) | (ev[3] & 0x0f);
	int tool = ttype == FTS_TTYPE_PALM ? MT_TOOL_PALM : MT_TOOL_FINGER;

	if (tid >= FTS_FINGER_MAX || !fts_ttype_reported(ttype))
		return;

	input_mt_slot(ts->input, tid);

	if (action == FTS_ACTION_RELEASE) {
		input_mt_report_slot_inactive(ts->input);
		return;
	}
	if (action != FTS_ACTION_PRESS && action != FTS_ACTION_MOVE)
		return;

	input_mt_report_slot_state(ts->input, tool, true);
	touchscreen_report_pos(ts->input, &ts->prop, x, y, true);
	input_report_abs(ts->input, ABS_MT_TOUCH_MAJOR, ev[4]);
	input_report_abs(ts->input, ABS_MT_TOUCH_MINOR, ev[5]);
	input_report_abs(ts->input, ABS_MT_PRESSURE, max(ev[6] & 0x3f, 1));
}

static void fts_handle_status(struct fts_ts *ts, const u8 *ev)
{
	u8 stype = (ev[0] >> 2) & 0x0f;

	if (stype == FTS_STYPE_ERROR && ev[1] == FTS_ERR_QUEUE_FULL) {
		dev_warn(&ts->client->dev, "event queue full\n");
		fts_release_all(ts);
	}
}

static irqreturn_t fts_irq_handler(int irq, void *data)
{
	struct fts_ts *ts = data;
	u8 buf[FTS_FIFO_MAX * FTS_EVENT_SIZE];
	u8 cmd = FTS_READ_ONE_EVENT;
	int left, i;

	if (fts_read(ts, &cmd, 1, buf, FTS_EVENT_SIZE))
		return IRQ_HANDLED;

	left = buf[7] & 0x3f;
	if (left >= FTS_FIFO_MAX)
		left = FTS_FIFO_MAX - 1;
	if (left) {
		cmd = FTS_READ_ALL_EVENT;
		if (fts_read(ts, &cmd, 1, buf + FTS_EVENT_SIZE, left * FTS_EVENT_SIZE))
			left = 0;
	}

	for (i = 0; i <= left; i++) {
		const u8 *ev = buf + i * FTS_EVENT_SIZE;

		if (debug && memchr_inv(ev, 0, FTS_EVENT_SIZE))
			dev_info(&ts->client->dev, "event %d/%d: %*ph\n", i, left, FTS_EVENT_SIZE, ev);

		switch (ev[0] & 0x03) {
		case FTS_EID_COORDINATE:
			fts_report_coordinate(ts, ev);
			break;
		case FTS_EID_STATUS:
			fts_handle_status(ts, ev);
			break;
		default:
			break;
		}
	}

	input_mt_sync_frame(ts->input);
	input_sync(ts->input);
	return IRQ_HANDLED;
}

static void fts_poll(struct work_struct *work)
{
	struct fts_ts *ts = container_of(work, struct fts_ts, poll.work);

	fts_irq_handler(0, ts);
	schedule_delayed_work(&ts->poll, msecs_to_jiffies(poll_ms));
}

static void fts_stop_polling(void *data)
{
	struct fts_ts *ts = data;

	cancel_delayed_work_sync(&ts->poll);
}

static int fts_start_events(struct fts_ts *ts)
{
	struct device *dev = &ts->client->dev;
	int err;

	if (ts->client->irq > 0) {
		err = devm_request_threaded_irq(dev, ts->client->irq, NULL, fts_irq_handler,
						IRQF_ONESHOT, "fts1ba90a", ts);
		if (err)
			return dev_err_probe(dev, err, "irq %d\n", ts->client->irq);
		return 0;
	}

	if (!poll_ms) {
		dev_warn(dev, "no interrupt and poll_ms=0: the controller runs, nothing is read\n");
		return 0;
	}
	dev_warn(dev, "no interrupt: polling every %u ms\n", poll_ms);
	INIT_DELAYED_WORK(&ts->poll, fts_poll);
	err = devm_add_action_or_reset(dev, fts_stop_polling, ts);
	if (err)
		return err;
	schedule_delayed_work(&ts->poll, msecs_to_jiffies(poll_ms));
	return 0;
}

/* the controller says it is ready with an information event, id 0 */
static int fts_wait_ready(struct fts_ts *ts)
{
	u8 cmd = FTS_READ_ONE_EVENT;
	u8 ev[FTS_EVENT_SIZE];
	int i, err;

	for (i = 0; i < FTS_READY_TRIES; i++) {
		err = fts_read(ts, &cmd, 1, ev, sizeof(ev));
		if (err)
			return err;
		if ((ev[0] & 0x03) == FTS_EID_STATUS &&
		    ((ev[0] >> 2) & 0x0f) == FTS_STYPE_INFORMATION &&
		    ev[1] == FTS_INFO_READY)
			return 0;
		msleep(20);
	}
	return -ETIMEDOUT;
}

static int fts_check_id(struct fts_ts *ts)
{
	u8 cmd = FTS_READ_DEVICE_ID;
	u8 id[4];
	int err = fts_read(ts, &cmd, 1, id, sizeof(id));

	if (err)
		return err;
	if (id[2] != FTS_ID0 || id[3] != FTS_ID1) {
		dev_err(&ts->client->dev, "unexpected chip id %02x %02x %02x %02x\n",
			id[0], id[1], id[2], id[3]);
		return -ENODEV;
	}
	return 0;
}

static int fts_start(struct fts_ts *ts)
{
	/* the system reset command, six bytes, as Samsung's driver sends it */
	static const u8 reset[] = { 0xfa, 0x20, 0x00, 0x00, 0x24, 0x81 };
	static const u8 touchtype[] = {
		FTS_CMD_SET_TOUCHTYPE,
		FTS_TOUCHTYPE_TOUCH | FTS_TOUCHTYPE_PALM | FTS_TOUCHTYPE_WET,
		0x00,
	};
	static const u8 scan[] = { FTS_CMD_SCANMODE, 0x00, FTS_SCAN_MODE_MS_SS };
	int err;

	err = fts_write(ts, reset, sizeof(reset));
	if (err)
		return err;
	msleep(20);

	err = fts_wait_ready(ts);
	if (err) {
		dev_err(&ts->client->dev, "controller not ready after reset: %d\n", err);
		return err;
	}
	err = fts_check_id(ts);
	if (err)
		return err;

	err = fts_command(ts, FTS_CMD_CLEAR_ALL_EVENT);
	if (err)
		return err;
	err = fts_write(ts, touchtype, sizeof(touchtype));
	if (err)
		return err;
	msleep(50);
	return fts_write(ts, scan, sizeof(scan));
}

static void fts_stop(void *data)
{
	struct fts_ts *ts = data;

	fts_command(ts, FTS_CMD_SENSE_OFF);
}

static void fts_disable_supplies(void *data)
{
	struct fts_ts *ts = data;

	regulator_bulk_disable(ARRAY_SIZE(ts->supplies), ts->supplies);
}

static int fts_probe_input(struct fts_ts *ts)
{
	struct device *dev = &ts->client->dev;
	struct input_dev *input;
	int err;

	input = devm_input_allocate_device(dev);
	if (!input)
		return -ENOMEM;
	ts->input = input;

	input->name = "FTS1BA90A Touchscreen";
	input->id.bustype = BUS_I2C;

	input_set_abs_params(input, ABS_MT_POSITION_X, 0, FTS_MAX_X, 0, 0);
	input_set_abs_params(input, ABS_MT_POSITION_Y, 0, FTS_MAX_Y, 0, 0);
	input_set_abs_params(input, ABS_MT_TOUCH_MAJOR, 0, 255, 0, 0);
	input_set_abs_params(input, ABS_MT_TOUCH_MINOR, 0, 255, 0, 0);
	input_set_abs_params(input, ABS_MT_PRESSURE, 0, 63, 0, 0);
	/* the palm tool type is how libinput learns to ignore a palm */
	input_set_abs_params(input, ABS_MT_TOOL_TYPE, 0, MT_TOOL_MAX, 0, 0);
	touchscreen_parse_properties(input, true, &ts->prop);

	err = input_mt_init_slots(input, FTS_FINGER_MAX, INPUT_MT_DIRECT);
	if (err)
		return err;
	return input_register_device(input);
}

static int fts_power_up(struct fts_ts *ts)
{
	struct device *dev = &ts->client->dev;
	int i, err;

	for (i = 0; i < ARRAY_SIZE(ts->supplies); i++)
		ts->supplies[i].supply = fts_supply_names[i];
	/* on the Tab S5e both rails are always on; a missing one is a dummy */
	err = devm_regulator_bulk_get(dev, ARRAY_SIZE(ts->supplies), ts->supplies);
	if (err)
		return dev_err_probe(dev, err, "supplies\n");
	err = regulator_bulk_enable(ARRAY_SIZE(ts->supplies), ts->supplies);
	if (err)
		return err;
	err = devm_add_action_or_reset(dev, fts_disable_supplies, ts);
	if (err)
		return err;
	msleep(20);
	return 0;
}

static int fts_probe(struct i2c_client *client)
{
	struct device *dev = &client->dev;
	struct fts_ts *ts;
	int err;

	if (!i2c_check_functionality(client->adapter, I2C_FUNC_I2C))
		return -ENODEV;

	ts = devm_kzalloc(dev, sizeof(*ts), GFP_KERNEL);
	if (!ts)
		return -ENOMEM;
	ts->client = client;
	i2c_set_clientdata(client, ts);

	err = fts_power_up(ts);
	if (err)
		return err;
	err = fts_probe_input(ts);
	if (err)
		return dev_err_probe(dev, err, "input device\n");
	err = fts_start(ts);
	if (err)
		return dev_err_probe(dev, err, "start\n");
	err = devm_add_action_or_reset(dev, fts_stop, ts);
	if (err)
		return err;

	err = fts_start_events(ts);
	if (err)
		return err;

	dev_info(dev, "FTS1BA90A ready, irq %d\n", client->irq);
	return 0;
}

static const struct of_device_id fts_of_match[] = {
	{ .compatible = "st,fts1ba90a" },
	{ }
};
MODULE_DEVICE_TABLE(of, fts_of_match);

static const struct i2c_device_id fts_id[] = {
	{ "fts1ba90a" },
	{ }
};
MODULE_DEVICE_TABLE(i2c, fts_id);

static struct i2c_driver fts_driver = {
	.driver = {
		.name = "fts1ba90a",
		.of_match_table = fts_of_match,
	},
	.probe = fts_probe,
	.id_table = fts_id,
};
module_i2c_driver(fts_driver);

MODULE_DESCRIPTION("STMicroelectronics FTS1BA90A touchscreen driver");
MODULE_LICENSE("GPL");
