using System;
using System.Diagnostics;
using System.IO;
// Used only for short setup/check jobs; production guard has no child process.
internal static class WindowlessRunner {
 [STAThread] static int Main(string[] args) {
  try {
   if(args.Length!=1) return 2;
   string script=Path.GetFullPath(args[0]);
   var start=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),@"WindowsPowerShell\v1.0\powershell.exe"));
   start.Arguments="-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \""+script+"\"";
   start.UseShellExecute=false;start.CreateNoWindow=true;
   using(var child=Process.Start(start)){child.WaitForExit();return child.ExitCode;}
  }catch{return 1;}
 }
}
