using System;
using System.Runtime.InteropServices;

public class Program {
    [DllImport("winspool.drv", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern int DocumentProperties(IntPtr hwnd, IntPtr hPrinter, string pDeviceName, IntPtr pDevModeOutput, IntPtr pDevModeInput, int fMode);
    
    [DllImport("winspool.drv", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern bool OpenPrinter(string pPrinterName, out IntPtr phPrinter, ref PRINTER_DEFAULTS pDefault);
    
    [DllImport("winspool.drv", SetLastError = true)]
    public static extern bool ClosePrinter(IntPtr hPrinter);
    
    [DllImport("winspool.drv", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern bool SetPrinter(IntPtr hPrinter, int Level, IntPtr pPrinter, int Command);

    [DllImport("gdi32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr CreateDC(string lpszDriver, string lpszDevice, string lpszOutput, IntPtr lpInitData);
    
    [DllImport("gdi32.dll")]
    public static extern bool DeleteDC(IntPtr hdc);
    
    [DllImport("gdi32.dll")]
    public static extern int GetDeviceCaps(IntPtr hdc, int nIndex);

    [StructLayout(LayoutKind.Sequential)]
    public struct PRINTER_DEFAULTS {
        public IntPtr pDatatype;
        public IntPtr pDevMode;
        public int DesiredAccess;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;
        public short dmOrientation;
        public short dmPaperSize;
        public short dmPaperLength;
        public short dmPaperWidth;
        public short dmScale;
        public short dmCopies;
        public short dmDefaultSource;
        public short dmPrintQuality;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel;
        public int dmPelsWidth;
        public int dmPelsHeight;
        public int dmNup;
        public int dmDisplayFrequency;
        public int dmICMMethod;
        public int dmICMIntent;
        public int dmMediaType;
        public int dmDitherType;
        public int dmReserved1;
        public int dmReserved2;
        public int dmPanningWidth;
        public int dmPanningHeight;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PRINTER_INFO_9 {
        public IntPtr pDevMode;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PRINTER_INFO_8 {
        public IntPtr pDevMode;
    }

    public static int Main(string[] args) {
        if (args.Length < 1) {
            Console.WriteLine("Usage: printer_config_helper <check|apply> <printerName> [dpi] [colorMode 1=Mono,2=Color]");
            return 1;
        }

        string cmd = args[0].ToLower();
        string printerName = args.Length > 1 ? args[1] : "";

        if (cmd == "check") {
            IntPtr hdc = CreateDC("WINSPOOL", printerName, null, IntPtr.Zero);
            if (hdc == IntPtr.Zero) {
                Console.WriteLine("{\"error\":\"CreateDC failed\"}");
                return 1;
            }
            int horzRes = GetDeviceCaps(hdc, 8);
            int vertRes = GetDeviceCaps(hdc, 10);
            int dpiX = GetDeviceCaps(hdc, 88);
            int dpiY = GetDeviceCaps(hdc, 90);
            int physW = GetDeviceCaps(hdc, 110);
            int physH = GetDeviceCaps(hdc, 111);
            int offX = GetDeviceCaps(hdc, 112);
            int offY = GetDeviceCaps(hdc, 113);
            DeleteDC(hdc);

            Console.WriteLine(string.Format(
                "{{\"dpiX\":{0},\"dpiY\":{1},\"horzRes\":{2},\"vertRes\":{3},\"physWidth\":{4},\"physHeight\":{5},\"offsetX\":{6},\"offsetY\":{7}}}",
                dpiX, dpiY, horzRes, vertRes, physW, physH, offX, offY
            ));
            return 0;
        }

        if (cmd == "apply" && args.Length >= 4) {
            short dpi = short.Parse(args[2]);
            short colorMode = short.Parse(args[3]);

            PRINTER_DEFAULTS def = new PRINTER_DEFAULTS();
            def.DesiredAccess = 0xF000C; // PRINTER_ALL_ACCESS
            IntPtr hPrinter;
            if (!OpenPrinter(printerName, out hPrinter, ref def)) {
                def.DesiredAccess = 0x00020000; // READ_CONTROL
                if (!OpenPrinter(printerName, out hPrinter, ref def)) {
                    Console.WriteLine("{\"error\":\"OpenPrinter failed\"}");
                    return 1;
                }
            }

            int size = DocumentProperties(IntPtr.Zero, hPrinter, printerName, IntPtr.Zero, IntPtr.Zero, 0);
            if (size <= 0) {
                ClosePrinter(hPrinter);
                Console.WriteLine("{\"error\":\"DocumentProperties size failed\"}");
                return 1;
            }

            IntPtr buffer = Marshal.AllocHGlobal(size);
            if (DocumentProperties(IntPtr.Zero, hPrinter, printerName, buffer, IntPtr.Zero, 2) < 0) {
                Marshal.FreeHGlobal(buffer);
                ClosePrinter(hPrinter);
                Console.WriteLine("{\"error\":\"DocumentProperties read failed\"}");
                return 1;
            }

            DEVMODE dm = (DEVMODE)Marshal.PtrToStructure(buffer, typeof(DEVMODE));
            dm.dmPrintQuality = dpi;
            dm.dmYResolution = dpi;
            dm.dmColor = colorMode;
            dm.dmFields |= (0x00000400 | 0x00002000 | 0x00000800); // DM_PRINTQUALITY | DM_YRESOLUTION | DM_COLOR

            Marshal.StructureToPtr(dm, buffer, false);
            DocumentProperties(IntPtr.Zero, hPrinter, printerName, buffer, buffer, 10); // DM_IN_BUFFER | DM_OUT_BUFFER

            // Set user default (Level 9)
            PRINTER_INFO_9 pi9 = new PRINTER_INFO_9();
            pi9.pDevMode = buffer;
            IntPtr pPi9 = Marshal.AllocHGlobal(Marshal.SizeOf(pi9));
            Marshal.StructureToPtr(pi9, pPi9, false);
            SetPrinter(hPrinter, 9, pPi9, 0);
            Marshal.FreeHGlobal(pPi9);

            // Set global default (Level 8)
            PRINTER_INFO_8 pi8 = new PRINTER_INFO_8();
            pi8.pDevMode = buffer;
            IntPtr pPi8 = Marshal.AllocHGlobal(Marshal.SizeOf(pi8));
            Marshal.StructureToPtr(pi8, pPi8, false);
            SetPrinter(hPrinter, 8, pPi8, 0);
            Marshal.FreeHGlobal(pPi8);

            Marshal.FreeHGlobal(buffer);
            ClosePrinter(hPrinter);

            Console.WriteLine("{\"status\":\"success\"}");
            return 0;
        }

        return 1;
    }
}
