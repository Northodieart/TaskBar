<#
  make-icon.ps1 —— 把带绿底的图扣成透明图标，并打包成多尺寸 .ico
  用法: .\make-icon.ps1                                  # 用项目里的 icon-source.png 重生成 taskbar-toggle.ico
        .\make-icon.ps1 -Src "D:\path\to\新设计图.png" -Out taskbar-toggle.ico
  换图标后必须重编译才会生效（-win32icon 不能漏）:
    csc -nologo -target:winexe -win32icon:taskbar-toggle.ico -r:System.Windows.Forms.dll -r:System.Drawing.dll -out:TaskBar.exe TaskbarAutoHideToggle.cs
#>
param(
  [string]$Src = "icon-source.png",
  [string]$Out = "taskbar-toggle.ico",
  [string]$Preview = "icon-preview.png"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

if (-not ('Ico.Maker' -as [type])) {
  Add-Type -ReferencedAssemblies 'System.Drawing' -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

namespace Ico {

  public static class Maker {

    // 绿通道相对红蓝最大值的超出量 -> 越大越像绿幕
    static int GreenDominance(int r, int g, int b) {
      int rb = r > b ? r : b;
      return g - rb;
    }

    public static string Build(string srcPath, string icoPath, int[] sizes, double fillRatio, string dumpPngPath) {
      Bitmap src = new Bitmap(srcPath);
      int w = src.Width, h = src.Height;
      Rectangle full = new Rectangle(0, 0, w, h);

      Bitmap key = new Bitmap(w, h, PixelFormat.Format32bppArgb);
      BitmapData sd = src.LockBits(full, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
      BitmapData kd = key.LockBits(full, ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);

      int[] pix = new int[w * h];
      Marshal.Copy(sd.Scan0, pix, 0, pix.Length);

      int minX = w, minY = h, maxX = -1, maxY = -1;
      const int Lo = 18;   // 低于此：完全不透明
      const int Hi = 60;   // 高于此：完全透明

      for (int y = 0; y < h; y++) {
        int row = y * w;
        for (int x = 0; x < w; x++) {
          int c = pix[row + x];
          int b = c & 0xFF, g = (c >> 8) & 0xFF, r = (c >> 16) & 0xFF;

          int gd = GreenDominance(r, g, b);
          int a;
          if (gd <= Lo) a = 255;
          else if (gd >= Hi) a = 0;
          else a = 255 * (Hi - gd) / (Hi - Lo);          // 边缘羽化

          if (a > 0) {
            // 去绿溢：保留像素的绿通道不超过红蓝最大值
            int rb = r > b ? r : b;
            if (g > rb) g = rb;
            int outC = (a << 24) | (r << 16) | (g << 8) | b;
            pix[row + x] = outC;
            if (a > 40) {                                  // 参与外接框计算，忽略几乎全透的
              if (x < minX) minX = x;
              if (x > maxX) maxX = x;
              if (y < minY) minY = y;
              if (y > maxY) maxY = y;
            }
          } else {
            pix[row + x] = 0;
          }
        }
      }

      Marshal.Copy(pix, 0, kd.Scan0, pix.Length);
      key.UnlockBits(kd);
      src.UnlockBits(sd);
      src.Dispose();

      if (maxX < 0) { key.Dispose(); throw new Exception("整张图都被扣掉了，没找到主体"); }

      // 内容外接框 -> 正方形，按 fillRatio 留出边距
      int bw = maxX - minX + 1, bh = maxY - minY + 1;
      float cx = minX + bw / 2f, cy = minY + bh / 2f;
      int side = (int)(Math.Max(bw, bh) / fillRatio);
      if (side > Math.Min(w, h)) side = Math.Min(w, h);
      Rectangle crop = new Rectangle((int)(cx - side / 2f), (int)(cy - side / 2f), side, side);

      var pngs = new byte[sizes.Length][];
      for (int i = 0; i < sizes.Length; i++) {
        using (Bitmap big = new Bitmap(sizes[i], sizes[i], PixelFormat.Format32bppArgb)) {
          using (Graphics gr = Graphics.FromImage(big)) {
            gr.InterpolationMode = InterpolationMode.HighQualityBicubic;
            gr.PixelOffsetMode = PixelOffsetMode.HighQuality;
            gr.SmoothingMode = SmoothingMode.HighQuality;
            gr.DrawImage(key, new Rectangle(0, 0, sizes[i], sizes[i]), crop, GraphicsUnit.Pixel);
          }
          using (MemoryStream ms = new MemoryStream()) {
            big.Save(ms, ImageFormat.Png);
            pngs[i] = ms.ToArray();
          }
        }
      }
      key.Dispose();

      // 写 ICO：ICONDIR + ICONDIRENTRY[] + 各档 PNG 数据
      using (FileStream fs = new FileStream(icoPath, FileMode.Create, FileAccess.Write)) {
        using (BinaryWriter bw2 = new BinaryWriter(fs)) {
          bw2.Write((ushort)0);                 // reserved
          bw2.Write((ushort)1);                 // type = icon
          bw2.Write((ushort)sizes.Length);      // count
          int offset = 6 + 16 * sizes.Length;
          for (int i = 0; i < sizes.Length; i++) {
            int s = sizes[i];
            bw2.Write((byte)(s >= 256 ? 0 : s));
            bw2.Write((byte)(s >= 256 ? 0 : s));
            bw2.Write((byte)0);                 // 调色板颜色数
            bw2.Write((byte)0);                 // reserved
            bw2.Write((ushort)1);               // planes
            bw2.Write((ushort)32);              // bit count
            bw2.Write((uint)pngs[i].Length);
            bw2.Write((uint)offset);
            offset += pngs[i].Length;
          }
          for (int i = 0; i < sizes.Length; i++) bw2.Write(pngs[i]);
        }
      }
      if (!string.IsNullOrEmpty(dumpPngPath)) File.WriteAllBytes(dumpPngPath, pngs[0]);
      return "ok";
    }

    // 预览：白底 / 黑底各画一遍，扣边不干净会立刻暴露
    public static string Preview(string sourcePng, string pngPath, int[] showSizes) {
      Bitmap probe = new Bitmap(sourcePng);
      int cell = 140, pad = 10;
      int n = showSizes.Length;
      using (Bitmap canvas = new Bitmap(pad + n * cell * 2, pad + cell * 2)) {
        using (Graphics gr = Graphics.FromImage(canvas)) {
          gr.Clear(Color.Gray);
          for (int half = 0; half < 2; half++) {
            using (SolidBrush sb = new SolidBrush(half == 0 ? Color.White : Color.Black))
              gr.FillRectangle(sb, pad + half * n * cell, pad, n * cell, cell * 2);
          }
          gr.InterpolationMode = InterpolationMode.HighQualityBicubic;
          for (int i = 0; i < n; i++) {
            int s = showSizes[i];
            int ox = pad + i * cell + (cell - s) / 2;
            gr.DrawImage(probe, ox, pad + (cell - s) / 2, s, s);
            gr.DrawImage(probe, ox + n * cell, pad + cell + (cell - s) / 2, s, s);
          }
          using (Pen p = new Pen(Color.Fuchsia)) {
            for (int i = 0; i <= n; i++) {
              float x = pad + i * cell;
              gr.DrawLine(p, x, pad, x, pad + cell * 2);
            }
          }
        }
        canvas.Save(pngPath, ImageFormat.Png);
      }
      probe.Dispose();
      return "ok";
    }
  }
}
'@
}
if (-not ('Ico.Maker' -as [type])) { Write-Error '编译失败'; exit 1 }

$sizes = @(256, 64, 48, 32, 24, 16) -as [int[]]
if (-not [IO.Path]::IsPathRooted($Src))     { $Src     = Join-Path $PSScriptRoot $Src }
if (-not [IO.Path]::IsPathRooted($Out))     { $Out     = Join-Path $PSScriptRoot $Out }
if (-not [IO.Path]::IsPathRooted($Preview)) { $Preview = Join-Path $PSScriptRoot $Preview }
# 路径不对时 GDI+ 只会抛 "Out of memory"，先说清楚
if (-not (Test-Path -LiteralPath $Src -PathType Leaf)) { throw "找不到源图: $Src" }
$dump = Join-Path $PSScriptRoot 'icon-256.png'
"src: $Src"
[void][Ico.Maker]::Build($Src, $Out, $sizes, 0.98, $dump)
[void][Ico.Maker]::Preview($dump, $Preview, @(48, 32, 16) -as [int[]])
"ico: $Out  ($((Get-Item $Out).Length) 字节)"
"preview: $Preview"
