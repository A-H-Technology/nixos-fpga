// SPDX-License-Identifier: GPL-2.0
/*
 * /dev/fpga-load: write a whole bitstream, close, and it goes to the FPGA
 * through the fpga-manager framework.
 *
 * Mainline gives userspace no way to start a load. fpga-mgr's sysfs is
 * read-only (the Xilinx fork's `firmware` attribute never went upstream), and
 * the in-kernel route, a device-tree overlay on an fpga-region, needs an
 * overlay interface mainline doesn't have either.
 *
 * The load runs on close, so close() returns its result: `cat x > /dev/fpga-load`
 * fails when the load does. The device is exclusive, one writer at a time.
 */
#include <linux/fpga/fpga-mgr.h>
#include <linux/fs.h>
#include <linux/miscdevice.h>
#include <linux/mm.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/slab.h>
#include <linux/uaccess.h>
#include <linux/vmalloc.h>

/* Agilex 5's largest RBFs are tens of MB; this leaves room above that. */
#define MAX_BITSTREAM (256 * 1024 * 1024)

static char *manager = "";
module_param(manager, charp, 0444);
MODULE_PARM_DESC(manager,
		 "DT compatible of the fpga-manager node, e.g. xlnx,zynq-devcfg-1.0");

static atomic_t busy = ATOMIC_INIT(0);

struct pending {
	struct mutex lock;
	void *buf;
	size_t len;
	size_t cap;
};

static int load(const void *buf, size_t len)
{
	struct fpga_image_info *info;
	struct fpga_manager *mgr;
	struct device_node *np;
	int ret;

	np = of_find_compatible_node(NULL, NULL, manager);
	if (!np) {
		pr_err("fpga-load: no DT node compatible with \"%s\"\n", manager);
		return -ENODEV;
	}
	/* -ENODEV here too while the manager's driver hasn't bound yet. */
	mgr = of_fpga_mgr_get(np);
	of_node_put(np);
	if (IS_ERR(mgr))
		return PTR_ERR(mgr);

	info = fpga_image_info_alloc(&mgr->dev);
	if (!info) {
		ret = -ENOMEM;
		goto put;
	}
	info->buf = buf;
	info->count = len;

	ret = fpga_mgr_lock(mgr);
	if (ret)
		goto free;
	ret = fpga_mgr_load(mgr, info);
	fpga_mgr_unlock(mgr);
	if (!ret)
		dev_info(&mgr->dev, "fpga-load: loaded %zu bytes\n", len);
free:
	fpga_image_info_free(info);
put:
	fpga_mgr_put(mgr);
	return ret;
}

static int fl_open(struct inode *inode, struct file *file)
{
	struct pending *p;

	if (atomic_cmpxchg(&busy, 0, 1))
		return -EBUSY;
	p = kzalloc(sizeof(*p), GFP_KERNEL);
	if (!p) {
		atomic_set(&busy, 0);
		return -ENOMEM;
	}
	mutex_init(&p->lock);
	file->private_data = p;
	return nonseekable_open(inode, file);
}

static ssize_t fl_write(struct file *file, const char __user *ubuf, size_t n,
			loff_t *off)
{
	struct pending *p = file->private_data;
	ssize_t ret = n;

	mutex_lock(&p->lock);
	if (n > MAX_BITSTREAM - p->len) {
		ret = -EFBIG;
		goto out;
	}
	if (p->len + n > p->cap) {
		size_t cap = min_t(size_t, MAX_BITSTREAM,
				   max(p->cap * 2, PAGE_ALIGN(p->len + n)));
		/* vmalloc is page-aligned, which covers Zynq's 8-byte DMA alignment. */
		void *grown = vmalloc(cap);

		if (!grown) {
			ret = -ENOMEM;
			goto out;
		}
		if (p->len)
			memcpy(grown, p->buf, p->len);
		vfree(p->buf);
		p->buf = grown;
		p->cap = cap;
	}
	if (copy_from_user(p->buf + p->len, ubuf, n)) {
		ret = -EFAULT;
		goto out;
	}
	p->len += n;
out:
	mutex_unlock(&p->lock);
	return ret;
}

/* flush runs on close() and its result is close()'s, which release's isn't. */
static int fl_flush(struct file *file, fl_owner_t id)
{
	struct pending *p = file->private_data;
	int ret = 0;

	mutex_lock(&p->lock);
	if (p->len) {
		ret = load(p->buf, p->len);
		p->len = 0;
	}
	mutex_unlock(&p->lock);
	return ret;
}

static int fl_release(struct inode *inode, struct file *file)
{
	struct pending *p = file->private_data;

	vfree(p->buf);
	kfree(p);
	atomic_set(&busy, 0);
	return 0;
}

static const struct file_operations fl_fops = {
	.owner = THIS_MODULE,
	.open = fl_open,
	.write = fl_write,
	.flush = fl_flush,
	.release = fl_release,
};

static struct miscdevice fl_dev = {
	.minor = MISC_DYNAMIC_MINOR,
	.name = "fpga-load",
	.fops = &fl_fops,
	.mode = 0600,
};

static int __init fl_init(void)
{
	if (!*manager) {
		pr_err("fpga-load: set the manager= parameter\n");
		return -EINVAL;
	}
	return misc_register(&fl_dev);
}

static void __exit fl_exit(void)
{
	misc_deregister(&fl_dev);
}

module_init(fl_init);
module_exit(fl_exit);

MODULE_DESCRIPTION("Load a bitstream written to /dev/fpga-load through fpga-manager");
MODULE_LICENSE("GPL");
