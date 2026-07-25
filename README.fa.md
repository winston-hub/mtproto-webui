# MTProto Manager — Web UI

پنل مدیریت پروکسی MTProto تلگرام با رابط وب.

---

## نصب سریع

```bash
bash <(curl -s https://raw.githubusercontent.com/winston-hub/mtproto-webui/main/mtproto-manager.sh)
```

## امکانات

- ✅ نصب با یک دستور
- ✅ پنل ترمینالی + پنل وب مدرن
- ✅ لاگین امن (یوزرنیم/پسورد)
- ✅ اضافه/حذف پروکسی
- ✅ تغییر پورت و دامنه Fake-TLS
- ✅ محدودیت حجم و اتصال همزمان
- ✅ کانال اسپانسر
- ✅ کپی لینک پروکسی با یک کلیک

## استفاده

### پنل ترمینال
```bash
mtproto-manager
```

### پنل وب
```
http://IP_سرور:5000
```

### ساخت رمز عبور
```bash
mtproto-manager
# → 8) Web UI
# → 5) Set/change login password
```

## حذف کامل

```bash
systemctl stop mtproto-webui mtprotoproxy 2>/dev/null
systemctl disable mtproto-webui mtprotoproxy 2>/dev/null
rm -f /etc/systemd/system/mtproto-webui.service /etc/systemd/system/mtprotoproxy.service
systemctl daemon-reload
rm -rf /opt/mtprotoproxy /opt/mtprotoproxy-webui
rm -f /usr/local/bin/mtproto-manager
```

## لایسنس

MIT
