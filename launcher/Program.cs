using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        Application.EnableVisualStyles();

        string applicationDirectory = AppDomain.CurrentDomain.BaseDirectory;
        string scriptPath = Path.Combine(applicationDirectory, "m4s-converter.ps1");

        if (!File.Exists(scriptPath))
        {
            MessageBox.Show(
                "Cannot find m4s-converter.ps1. Keep the EXE and PS1 files in the same folder.",
                "M4S Converter",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return;
        }

        try
        {
            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.FileName = "powershell.exe";
            startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -File \"" + scriptPath + "\" -Gui";
            startInfo.WorkingDirectory = applicationDirectory;
            startInfo.UseShellExecute = false;
            startInfo.CreateNoWindow = true;
            startInfo.WindowStyle = ProcessWindowStyle.Hidden;

            Process process = Process.Start(startInfo);
            if (process == null)
            {
                throw new InvalidOperationException("PowerShell did not start.");
            }
            process.Dispose();
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                "Unable to start the converter.\r\n\r\n" + exception.Message,
                "M4S Converter",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }
}
