// TaskbarAutoHideToggle.cs
// 双击切换 Windows 任务栏「自动隐藏」。
// 只用一个官方接口：shell32.dll 的 SHAppBarMessage。
//   ABM_GETSTATE(4)  读当前状态，返回值的 bit0 就是 ABS_AUTOHIDE
//   ABM_SETSTATE(10) 写状态，lParam 给 ABS_AUTOHIDE(1) 或 ABS_ALWAYSONTOP(0)
//   hWnd 填 Shell_TrayWnd，cbSize 必须是结构体真实字节数（64 位上是 48）
//
// 重新编译（-win32icon 必须带上，否则图标会退回默认）：
//   C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe -nologo -target:winexe ^
//     -win32icon:taskbar-toggle.ico -r:System.Windows.Forms.dll -r:System.Drawing.dll ^
//     -out:切换任务栏自动隐藏.exe TaskbarAutoHideToggle.cs
// 图标本身由 make-icon.ps1 从绿底原图生成（taskbar-toggle.ico，含 256/64/48/32/24/16 六档）

using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

static class TaskbarAutoHideToggle
{
    [StructLayout(LayoutKind.Sequential)]
    struct RECT { public int left, top, right, bottom; }

    [StructLayout(LayoutKind.Sequential)]
    struct APPBARDATA
    {
        public uint cbSize;
        public IntPtr hWnd;
        public uint uCallbackMessage;
        public uint uEdge;
        public RECT rc;
        public IntPtr lParam;
    }

    [DllImport("shell32.dll", CallingConvention = CallingConvention.StdCall)]
    static extern IntPtr SHAppBarMessage(uint dwMessage, ref APPBARDATA pData);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    const uint ABM_GETSTATE = 4;
    const uint ABM_SETSTATE = 10;
    const int ABS_AUTOHIDE = 1;
    const int ABS_ALWAYSONTOP = 0;

    static APPBARDATA NewTrayData()
    {
        APPBARDATA d = new APPBARDATA();
        d.cbSize = (uint)Marshal.SizeOf(typeof(APPBARDATA));
        d.hWnd = FindWindow("Shell_TrayWnd", null);
        return d;
    }

    static bool GetAutoHide()
    {
        APPBARDATA d = NewTrayData();
        long state = (long)SHAppBarMessage(ABM_GETSTATE, ref d);
        return (state & ABS_AUTOHIDE) == ABS_AUTOHIDE;
    }

    [STAThread]
    static void Main()
    {
        try
        {
            if (FindWindow("Shell_TrayWnd", null) == IntPtr.Zero)
                throw new Exception("找不到任务栏窗口 Shell_TrayWnd（explorer 可能没在运行）。");

            bool want = !GetAutoHide();

            APPBARDATA d = NewTrayData();
            d.lParam = (IntPtr)(want ? ABS_AUTOHIDE : ABS_ALWAYSONTOP);
            SHAppBarMessage(ABM_SETSTATE, ref d);

            // 回读确认。成功就不弹窗——任务栏本身出现/消失就是最直接的反馈。
            if (GetAutoHide() != want)
            {
                MessageBox.Show(
                    "切换没有生效，当前仍是「" + (GetAutoHide() ? "开" : "关") + "」。\n\n" +
                    "常见原因：使用了第三方任务栏替换程序，或 explorer 状态异常。",
                    "任务栏自动隐藏",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show("出错：" + ex.Message, "任务栏自动隐藏",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
