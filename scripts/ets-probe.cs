using System;
using System.Reflection;
using System.Runtime.CompilerServices;

class EtsProbe
{
    static void Main()
    {
        var asm = Assembly.LoadFrom(@"C:\Program Files (x86)\ETS5\ETS5N.exe");
        var type = asm.GetType("Knx.Ets.Ets5.App", true);
        Console.WriteLine("type=" + type.FullName);
        try
        {
            RuntimeHelpers.RunClassConstructor(type.TypeHandle);
            Console.WriteLine("cctor OK");
        }
        catch (Exception ex)
        {
            for (var cur = ex; cur != null; cur = cur.InnerException)
            {
                Console.WriteLine("EX " + cur.GetType().FullName);
                Console.WriteLine("  HResult=0x" + cur.HResult.ToString("X8"));
                Console.WriteLine("  Message=" + cur.Message);
            }
            Environment.Exit(1);
        }
    }
}
