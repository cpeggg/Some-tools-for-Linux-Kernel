qemu -kernel ./bzImage -initrd /boot/initrd.img-2.6.31-22-generic -gdb tcp::1234 -S

# -kernel 用来指定内核，注arch/x86/bzImage是不带调试信息的内核，vmlinux是带有调试信息的内核

# -initrd 用来指定内核启动时使用的ram disk，

# -gdb tcp::1234表示启动gdbserver，并在tcp的1234端口监听，-S表示在开始的时候冻结CPU直到远程的gdb输入相应的控制命令