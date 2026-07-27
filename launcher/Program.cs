using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        Application.EnableVisualStyles();

        string applicationDirectory = AppDomain.CurrentDomain.BaseDirectory;
        string temporaryDirectory = Path.Combine(
            Path.GetTempPath(),
            "m4s-converter-" + Guid.NewGuid().ToString("N"));

        try
        {
            string assetsDirectory = Path.Combine(temporaryDirectory, "assets");
            string scriptPath = Path.Combine(temporaryDirectory, "m4s-converter.ps1");
            string iconPath = Path.Combine(assetsDirectory, "app-icon.ico");

            Directory.CreateDirectory(assetsDirectory);
            Assembly assembly = Assembly.GetExecutingAssembly();
            ExtractResource(assembly, "M4SConverter.Script", scriptPath);
            ExtractResource(assembly, "M4SConverter.Icon", iconPath);

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

            using (process)
            {
                process.WaitForExit();
            }
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                "Unable to start the converter.\r\n\r\n" + exception.Message,
                "M4S Converter",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
        finally
        {
            try
            {
                if (Directory.Exists(temporaryDirectory))
                {
                    Directory.Delete(temporaryDirectory, true);
                }
            }
            catch
            {
                // Windows may briefly retain a handle after PowerShell exits.
            }
        }
    }

    private static void ExtractResource(Assembly assembly, string resourceName, string destinationPath)
    {
        using (Stream input = assembly.GetManifestResourceStream(resourceName))
        {
            if (input == null)
            {
                throw new InvalidOperationException("Missing embedded resource: " + resourceName);
            }

            using (FileStream output = File.Create(destinationPath))
            {
                input.CopyTo(output);
            }
        }
    }
}
