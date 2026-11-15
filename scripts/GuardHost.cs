using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Threading;
using System.Web.Script.Serialization;
using Microsoft.Win32;
using Microsoft.Win32.SafeHandles;

internal sealed class GuardConfig {
 public string Sid { get; set; }
 public string TaskName { get; set; }
 public string RunPath { get; set; }
 public string ValueName { get; set; }
 public string Command { get; set; }
}
internal static class GuardHost {
 [DllImport("advapi32.dll", SetLastError=true)]
 static extern int RegNotifyChangeKeyValue(SafeRegistryHandle key, bool subtree, uint filter, IntPtr signal, bool asynchronous);
 [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
 static string root;
 static readonly JavaScriptSerializer Json = new JavaScriptSerializer();
 static void Log(string text) {
  string path=Path.Combine(root,"guard.log");
  if(File.Exists(path) && new FileInfo(path).Length>262144) File.WriteAllText(path,"");
  File.AppendAllText(path,DateTimeOffset.Now.ToString("o")+" "+text+Environment.NewLine);
 }
 static void Heartbeat(string sid) {
  string path=Path.Combine(root,"heartbeat.json");
  string temporary=path+".tmp";
  File.WriteAllText(temporary,Json.Serialize(new {Pid=Process.GetCurrentProcess().Id,Sid=sid,At=DateTimeOffset.Now.ToString("o"),ConsoleHandle=GetConsoleWindow().ToInt64(),Host="native-winexe"}));
  if(File.Exists(path)) File.Replace(temporary,path,null); else File.Move(temporary,path);
 }
 [STAThread] static int Main(string[] args) {
  root=AppDomain.CurrentDomain.BaseDirectory;
  try {
   if(args.Length!=1) throw new ArgumentException("Expected one config file path");
   string path=Path.GetFullPath(args[0]);root=Path.GetDirectoryName(path);
   GuardConfig c=Json.Deserialize<GuardConfig>(File.ReadAllText(path));
   string sid=WindowsIdentity.GetCurrent().User.Value;
   if(c.Sid!=sid) throw new InvalidOperationException("Wrong user SID");
   bool production=c.RunPath==@"Software\Microsoft\Windows\CurrentVersion\Run";
   bool test=c.RunPath!=null && c.RunPath.StartsWith(@"Software\CodexNcmGuardTests\",StringComparison.Ordinal) && c.TaskName.StartsWith("Codex-NCMGuard-Test-",StringComparison.Ordinal);
   if((!production && !test) || c.ValueName!="cloudmusic" || String.IsNullOrEmpty(c.Command)) throw new InvalidOperationException("Unsupported target");
   if(production && c.TaskName!="Codex-NetEaseStartupGuard-"+sid) throw new InvalidOperationException("Wrong task identity");
   using(Mutex mutex=new Mutex(false,"Local\\"+c.TaskName)) {
    bool owned=false;
    try {
     try {owned=mutex.WaitOne(0);} catch(AbandonedMutexException){owned=true;}
     if(!owned) return 0;
     using(RegistryKey hive=RegistryKey.OpenBaseKey(RegistryHive.CurrentUser,RegistryView.Registry64))
     using(RegistryKey key=hive.OpenSubKey(c.RunPath,true))
     using(AutoResetEvent signal=new AutoResetEvent(false)) {
      if(key==null) throw new InvalidOperationException("Target key does not exist");
      Log("Started native-winexe ConsoleHandle="+GetConsoleWindow().ToInt64());
      while(true) {
       int code=RegNotifyChangeKeyValue(key.Handle,false,4,signal.SafeWaitHandle.DangerousGetHandle(),true);
       if(code!=0) throw new InvalidOperationException("Registry notification error "+code);
       string value=key.GetValue(c.ValueName,null,RegistryValueOptions.DoNotExpandEnvironmentNames) as string;
       if(String.Equals(value,c.Command,StringComparison.Ordinal)){key.DeleteValue(c.ValueName,false);Log("Removed verified autorun value");}
       Heartbeat(sid);
       while(!signal.WaitOne(60000)) Heartbeat(sid);
      }
     }
    } finally {if(owned) mutex.ReleaseMutex();}
   }
  } catch(Exception error) {Log("ERROR "+error);return 1;}
 }
}
